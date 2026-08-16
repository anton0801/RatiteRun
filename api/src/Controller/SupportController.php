<?php

declare(strict_types=1);

namespace RatiteRun\Api\Controller;

use RatiteRun\Api\Core\Request;
use RatiteRun\Api\Core\Response;

/**
 * Обращение в поддержку из приложения. Веб-форма живёт в PageController;
 * здесь тот же сценарий, но в JSON и с уже известным пользователем —
 * поэтому CSRF не нужен, его роль играет access-токен.
 */
final class SupportController extends Controller
{
    /** POST /v1/support */
    public function submit(Request $request): Response
    {
        $userId = $this->userId($request);
        $ip = $request->clientIp();

        $this->c->rateLimiter()->hit('support-api:' . $userId, 10, 3600);
        $this->c->support()->assertNotFlooding($ip);

        $body = $request->json();

        // Имя и почта необязательны для анонимного аккаунта: если человек их
        // не указал, подставляем заглушки, чтобы обращение всё равно дошло.
        if (!isset($body['name']) || trim((string) $body['name']) === '') {
            $body['name'] = 'Ratite Run user';
        }
        if (!isset($body['email']) || trim((string) $body['email']) === '') {
            $user = $this->c->users()->find($userId);
            $body['email'] = is_string($user['email'] ?? null) && $user['email'] !== ''
                ? $user['email']
                : 'no-reply@ratiterun.online';
        }

        $result = $this->c->support()->create(
            $body,
            source: 'app',
            userId: $userId,
            ip: $ip,
            userAgent: $request->userAgent(),
        );

        $this->c->audit()->record($userId, null, 'support.create', null, null, $ip);

        return Response::created(
            [
                'id'        => $result['id'],
                'createdAt' => $result['createdAt'],
                'message'   => 'Thanks — we have your message and will reply by email.',
            ],
            '/v1/support/' . $result['id'],
        );
    }
}
