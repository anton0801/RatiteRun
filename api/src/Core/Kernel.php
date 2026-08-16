<?php

declare(strict_types=1);

namespace RatiteRun\Api\Core;

use RatiteRun\Api\Controller\AuthController;
use RatiteRun\Api\Controller\CollectionController;
use RatiteRun\Api\Controller\ExportController;
use RatiteRun\Api\Controller\FlockController;
use RatiteRun\Api\Controller\PageController;
use RatiteRun\Api\Controller\PhotoController;
use RatiteRun\Api\Controller\ReferenceController;
use RatiteRun\Api\Controller\ReportController;
use RatiteRun\Api\Controller\SupportController;

final class Kernel
{
    private Container $container;
    private Router $router;

    public function __construct()
    {
        $this->container = new Container();
        $this->router = new Router(prefix: '/v1');
        $this->registerRoutes();
    }

    public function handle(Request $request): Response
    {
        // Незашифрованное соединение отсекается до всего остального: токен
        // в заголовке Authorization не должен уйти по открытому каналу.
        if ($response = $this->enforceHttps($request)) {
            return $this->harden($response, $request);
        }

        // Предзапрос CORS отвечает до роутинга — у него нет своего обработчика.
        if ($request->method === 'OPTIONS') {
            return $this->harden(
                $this->applyCors(Response::noContent(), $request)
                    ->withHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS')
                    ->withHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type, If-Match, If-None-Match, Idempotency-Key')
                    ->withHeader('Access-Control-Max-Age', '86400'),
                $request,
            );
        }

        $route = $this->router->match($request);
        $request->params = $route['params'];

        // Порядок важен: сначала по адресу — до обращения к БД на проверке
        // токена, затем поимённо, чтобы один NAT не блокировал всех за ним.
        $this->throttleByAddress($request);
        $this->authenticate($request, required: $route['auth']);
        $this->throttleByUser($request);

        $response = $this->withIdempotency($request, $route['handler']);

        return $this->harden($this->applyCors($response, $request), $request);
    }

    // -- транспорт ------------------------------------------------------------

    /**
     * @return Response|null редирект/ошибка, если соединение не по TLS
     */
    private function enforceHttps(Request $request): ?Response
    {
        if ($request->isSecure() || !Config::bool('FORCE_HTTPS', true)) {
            return null;
        }

        // Локальная разработка по http://127.0.0.1 остаётся рабочей.
        $host = $request->host();
        if ($host === 'localhost' || $host === '127.0.0.1' || str_ends_with($host, '.local')) {
            return null;
        }

        // Браузеру полезен редирект, клиенту API — честная ошибка:
        // молча «починить» уже утёкший в открытый канал токен нельзя.
        if ($request->method === 'GET' && !str_starts_with($request->path, '/v1/')) {
            return Response::redirect('https://' . $host . $request->path, 308);
        }

        throw new ApiException(
            403,
            'https://api.ratiterun.online/problems/insecure-transport',
            'HTTPS Required',
            'This API refuses plaintext connections. Use https://.',
        );
    }

    /**
     * Заголовки безопасности на каждый ответ. CSP для HTML жёстче некуда:
     * страницы не подключают ни одного внешнего ресурса и не содержат скриптов.
     */
    private function harden(Response $response, Request $request): Response
    {
        $isHtml = str_contains($response->contentType() ?? '', 'text/html');

        $response = $response
            ->withHeader('X-Content-Type-Options', 'nosniff')
            ->withHeader('X-Frame-Options', 'DENY')
            ->withHeader('Permissions-Policy', 'geolocation=(), camera=(), microphone=(), payment=(), usb=(), interest-cohort=()')
            ->withHeader(
                'Content-Security-Policy',
                $isHtml
                    ? "default-src 'none'; style-src 'unsafe-inline'; img-src 'self' data:; "
                      . "form-action 'self'; base-uri 'none'; frame-ancestors 'none'"
                    : "default-src 'none'; frame-ancestors 'none'; base-uri 'none'",
            )
            ->withHeader(
                'Referrer-Policy',
                // на страницах ссылки наружу допустимы, у API реферер не нужен вовсе
                $isHtml ? 'strict-origin-when-cross-origin' : 'no-referrer',
            );

        if ($request->isSecure()) {
            $response = $response->withHeader(
                'Strict-Transport-Security',
                'max-age=31536000; includeSubDomains; preload',
            );
        }

        return $response;
    }

    // -- аутентификация -------------------------------------------------------

    private function authenticate(Request $request, bool $required): void
    {
        $token = $request->bearerToken();

        if ($token === null) {
            if ($required) {
                throw ApiException::unauthorized();
            }

            return;
        }

        try {
            $claims = Jwt::decode($token, Config::require('JWT_SECRET'));
        } catch (ApiException $e) {
            // на публичных маршрутах негодный токен просто игнорируется
            if ($required) {
                throw $e;
            }

            return;
        }

        $sub = $claims['sub'] ?? null;
        if (!is_string($sub) || !Uuid::isValid($sub)) {
            if ($required) {
                throw ApiException::unauthorized('Access token subject is invalid.');
            }

            return;
        }

        // аккаунт мог быть удалён после выдачи токена
        if ($this->container->users()->find($sub) === null) {
            if ($required) {
                throw ApiException::unauthorized('Account no longer exists.');
            }

            return;
        }

        $request->userId = $sub;
    }

    private function throttleByAddress(Request $request): void
    {
        if (!Config::bool('RATE_LIMIT_ENABLED', true)) {
            return;
        }

        $this->container->rateLimiter()->hit(
            'ip:' . ($request->clientIp() ?? 'unknown'),
            Config::int('RATE_LIMIT_PER_IP_PER_MINUTE', 600),
            60,
        );
    }

    private function throttleByUser(Request $request): void
    {
        if (!Config::bool('RATE_LIMIT_ENABLED', true) || $request->userId === null) {
            return;
        }

        $this->container->rateLimiter()->hit(
            'user:' . $request->userId,
            Config::int('RATE_LIMIT_PER_MINUTE', 300),
            60,
        );
    }

    // -- идемпотентность ------------------------------------------------------

    private function withIdempotency(Request $request, callable $handler): Response
    {
        $key = $request->header('idempotency-key');

        if ($request->method !== 'POST' || $key === null || $key === '' || $request->userId === null) {
            return $handler($request);
        }

        if (strlen($key) > 191) {
            throw ApiException::badRequest('Idempotency-Key must be at most 191 characters.');
        }

        $store = $this->container->idempotency();
        $userId = $request->userId;
        $body = $request->rawBody();

        $replay = $store->lookup($userId, $key, $request->method, $request->path, $body);
        if ($replay !== null) {
            return Response::json($replay['body'], $replay['statusCode'])
                ->withHeader('Idempotency-Replayed', 'true');
        }

        $store->begin($userId, $key, $request->method, $request->path, $body);

        try {
            $response = $handler($request);
        } catch (\Throwable $e) {
            $store->abandon($userId, $key);
            throw $e;
        }

        $store->complete($userId, $key, $response->status, $response->body);

        return $response;
    }

    // -- CORS -----------------------------------------------------------------

    private function applyCors(Response $response, Request $request): Response
    {
        $allowed = Config::get('CORS_ORIGINS', '');
        if ($allowed === null || $allowed === '') {
            return $response;
        }

        $origin = $request->header('origin');
        if ($origin === null) {
            return $response;
        }

        $list = array_map('trim', explode(',', $allowed));
        if (!in_array($origin, $list, true) && !in_array('*', $list, true)) {
            return $response;
        }

        return $response
            ->withHeader('Access-Control-Allow-Origin', in_array('*', $list, true) ? '*' : $origin)
            ->withHeader('Vary', 'Origin')
            ->withHeader('Access-Control-Expose-Headers', 'ETag, Location, Idempotency-Replayed');
    }

    // -- маршруты -------------------------------------------------------------

    /**
     * Порядок значим: конкретные подресурсы стада регистрируются раньше
     * шаблона /flocks/{id}/{section}, иначе «birds» уедет в обработчик секций.
     */
    private function registerRoutes(): void
    {
        $auth       = new AuthController($this->container);
        $flocks     = new FlockController($this->container);
        $collection = new CollectionController($this->container);
        $photos     = new PhotoController($this->container);
        $reports    = new ReportController($this->container);
        $reference  = new ReferenceController($this->container);
        $export     = new ExportController($this->container);
        $support    = new SupportController($this->container);
        $pages      = new PageController($this->container);

        $r = $this->router;

        // -- HTML-страницы (вне префикса /v1) ---------------------------------
        $r->page('GET',  '/', [$pages, 'home']);
        $r->page('GET',  '/privacy-terms', [$pages, 'privacy']);
        $r->page('GET',  '/support-form', [$pages, 'supportForm']);
        $r->page('POST', '/support-form', [$pages, 'submitSupportForm']);

        // -- публичные --------------------------------------------------------
        $r->get('/health', [$export, 'health'], auth: false);

        $r->post('/auth/anonymous', [$auth, 'anonymous'], auth: false);
        $r->post('/auth/apple', [$auth, 'apple'], auth: false);      // токен опционален
        $r->post('/auth/refresh', [$auth, 'refresh'], auth: false);

        $r->get('/species-presets', [$reference, 'presets'], auth: false);
        $r->get('/species-presets/{species}', [$reference, 'preset'], auth: false);
        $r->get('/content/{slug}', [$reference, 'content'], auth: false);

        $r->get('/shared/reports/{token}', [$reports, 'shared'], auth: false);

        // -- аккаунт ----------------------------------------------------------
        $r->post('/auth/logout', [$auth, 'logout']);
        $r->get('/me', [$auth, 'me']);
        $r->delete('/me', [$auth, 'deleteMe']);
        $r->post('/devices', [$auth, 'registerDevice']);
        $r->delete('/devices/{id}', [$auth, 'removeDevice']);

        // -- стада ------------------------------------------------------------
        $r->get('/flocks', [$flocks, 'index']);
        $r->post('/flocks', [$flocks, 'store']);
        $r->get('/flocks/{id}', [$flocks, 'show']);
        $r->patch('/flocks/{id}', [$flocks, 'update']);
        $r->delete('/flocks/{id}', [$flocks, 'destroy']);

        // производные и подресурсы — строго до шаблона секций
        $r->post('/flocks/{id}/duplicate', [$flocks, 'duplicate']);
        $r->get('/flocks/{id}/readiness', [$flocks, 'readiness']);
        $r->get('/flocks/{id}/evaluation', [$flocks, 'evaluation']);
        $r->get('/flocks/{id}/kit', [$flocks, 'kit']);
        $r->get('/flocks/{id}/cost', [$flocks, 'cost']);
        $r->get('/flocks/{id}/history', [$collection, 'history']);
        $r->get('/flocks/{id}/growth', [$collection, 'growth']);

        $r->get('/flocks/{id}/birds', [$collection, 'birds']);
        $r->post('/flocks/{id}/birds', [$collection, 'createBird']);
        $r->get('/flocks/{id}/birds/{recordId}', [$collection, 'showBird']);
        $r->patch('/flocks/{id}/birds/{recordId}', [$collection, 'updateBird']);
        $r->delete('/flocks/{id}/birds/{recordId}', [$collection, 'deleteBird']);

        $r->get('/flocks/{id}/reminders', [$collection, 'reminders']);
        $r->post('/flocks/{id}/reminders', [$collection, 'createReminder']);
        $r->patch('/flocks/{id}/reminders/{reminderId}', [$collection, 'updateReminder']);
        $r->delete('/flocks/{id}/reminders/{reminderId}', [$collection, 'deleteReminder']);

        $r->get('/flocks/{id}/layout', [$collection, 'layout']);
        $r->put('/flocks/{id}/layout', [$collection, 'replaceLayout']);
        $r->post('/flocks/{id}/layout', [$collection, 'createLayoutItem']);
        $r->patch('/flocks/{id}/layout/{itemId}', [$collection, 'updateLayoutItem']);
        $r->delete('/flocks/{id}/layout/{itemId}', [$collection, 'deleteLayoutItem']);

        $r->get('/flocks/{id}/photo', [$photos, 'show']);
        $r->post('/flocks/{id}/photo', [$photos, 'upload']);
        $r->delete('/flocks/{id}/photo', [$photos, 'destroy']);

        $r->get('/flocks/{id}/reports', [$reports, 'index']);
        $r->post('/flocks/{id}/reports', [$reports, 'store']);

        // шаблон секций — последним среди /flocks/{id}/*
        $r->get('/flocks/{id}/{section}', [$flocks, 'showSection']);
        $r->put('/flocks/{id}/{section}', [$flocks, 'updateSection']);

        // -- отчёты, оценка, экспорт -----------------------------------------
        $r->get('/reports/{reportId}', [$reports, 'show']);
        $r->get('/reports/{reportId}/pdf', [$reports, 'pdf']);

        $r->post('/evaluate', [$flocks, 'evaluateDraft']);
        $r->get('/export', [$export, 'export']);

        // -- поддержка из приложения -----------------------------------------
        $r->post('/support', [$support, 'submit']);
    }
}
