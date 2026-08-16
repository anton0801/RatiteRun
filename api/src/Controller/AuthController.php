<?php

declare(strict_types=1);

namespace RatiteRun\Api\Controller;

use RatiteRun\Api\Core\ApiException;
use RatiteRun\Api\Core\Request;
use RatiteRun\Api\Core\Response;
use RatiteRun\Api\Core\Uuid;
use RatiteRun\Api\Core\Validator;
use RatiteRun\Api\Repository\UserRepository;
use RatiteRun\Api\Service\AppleIdentityVerifier;

final class AuthController extends Controller
{
    /**
     * POST /v1/auth/anonymous
     *
     * Сохраняет обещание приложения «no account, no sign-up»: клиент шлёт
     * identifierForVendor, получает токены, пользователь ничего не заполняет.
     */
    public function anonymous(Request $request): Response
    {
        $this->c->rateLimiter()->hit('auth:' . ($request->clientIp() ?? 'unknown'), 30, 300);

        $v = new Validator($request->json());
        $deviceKey = $v->requiredString('deviceId', 191);
        $platform = $v->enum('platform', ['ios', 'ipados', 'macos']);
        $timezone = $v->string('timezone', 64);
        $appVersion = $v->string('appVersion', 32);
        $v->validate();

        $user = $this->c->users()->findOrCreateForDevice(
            (string) $deviceKey,
            $platform,
            $timezone,
            $appVersion,
        );

        $tokens = $this->c->tokens()->issue((string) $user['id']);

        return Response::json($tokens + ['user' => UserRepository::present($user)]);
    }

    /**
     * POST /v1/auth/apple
     *
     * Привязка Apple ID к текущему анонимному аккаунту — синхронизация между
     * устройствами без обязательной регистрации.
     */
    public function apple(Request $request): Response
    {
        $this->c->rateLimiter()->hit('auth:' . ($request->clientIp() ?? 'unknown'), 30, 300);

        $v = new Validator($request->json());
        $identityToken = $v->requiredString('identityToken', 4096);
        $displayName = $v->string('displayName', 120);
        $v->validate();

        $claims = (new AppleIdentityVerifier())->verify((string) $identityToken);

        $sub = $claims['sub'] ?? null;
        if (!is_string($sub) || $sub === '') {
            throw ApiException::unauthorized('Apple identity token has no subject.');
        }

        $email = isset($claims['email']) && is_string($claims['email']) ? $claims['email'] : null;

        // если запрос пришёл с access-токеном — привязываем к нему, иначе просто входим
        $currentUserId = $request->userId;

        if ($currentUserId === null) {
            $existing = $this->c->users()->findByAppleSub($sub);
            if ($existing === null) {
                throw ApiException::unauthorized(
                    'No account for this Apple ID. Sign in anonymously first, then link.',
                );
            }
            $tokens = $this->c->tokens()->issue((string) $existing['id']);

            return Response::json($tokens + ['user' => UserRepository::present($existing), 'linked' => false]);
        }

        $result = $this->c->users()->linkApple($currentUserId, $sub, $email, $displayName);
        $tokens = $this->c->tokens()->issue((string) $result['user']['id']);

        return Response::json($tokens + [
            'user'   => UserRepository::present($result['user']),
            'linked' => $result['merged'],
        ]);
    }

    /** POST /v1/auth/refresh */
    public function refresh(Request $request): Response
    {
        $v = new Validator($request->json());
        $refreshToken = $v->requiredString('refreshToken', 128);
        $v->validate();

        $result = $this->c->tokens()->rotate((string) $refreshToken);
        $userId = $result['userId'];
        unset($result['userId']);

        $user = $this->c->users()->find($userId);
        if ($user === null) {
            throw ApiException::unauthorized('Account no longer exists.');
        }

        return Response::json($result + ['user' => UserRepository::present($user)]);
    }

    /** POST /v1/auth/logout */
    public function logout(Request $request): Response
    {
        $v = new Validator($request->json());
        $refreshToken = $v->string('refreshToken', 128);
        $all = $v->bool('allDevices');
        $v->validate();

        if ($all === true) {
            $this->c->tokens()->revokeAllForUser($this->userId($request));
        } elseif ($refreshToken !== null && $refreshToken !== '') {
            $this->c->tokens()->revoke($refreshToken);
        }

        return Response::noContent();
    }

    /** GET /v1/me */
    public function me(Request $request): Response
    {
        $user = $this->c->users()->find($this->userId($request))
            ?? throw ApiException::unauthorized('Account no longer exists.');

        $flockCount = (int) $this->c->db()->fetchValue(
            'SELECT COUNT(*) FROM flocks WHERE user_id = ? AND deleted_at IS NULL',
            [$user['id']],
        );

        return Response::json(UserRepository::present($user) + ['flockCount' => $flockCount]);
    }

    /** DELETE /v1/me — удаление аккаунта и данных. */
    public function deleteMe(Request $request): Response
    {
        $userId = $this->userId($request);
        $this->c->users()->softDelete($userId);
        $this->c->audit()->record($userId, null, 'account.delete', null, null, $request->clientIp());

        return Response::noContent();
    }

    /** POST /v1/devices — регистрация APNs-токена. */
    public function registerDevice(Request $request): Response
    {
        $v = new Validator($request->json());
        $deviceKey = $v->requiredString('deviceId', 191);
        $apnsToken = $v->string('apnsToken', 255);
        $platform = $v->enum('platform', ['ios', 'ipados', 'macos']);
        $timezone = $v->string('timezone', 64);
        $appVersion = $v->string('appVersion', 32);
        $v->validate();

        $id = $this->c->users()->registerDevice(
            $this->userId($request),
            (string) $deviceKey,
            $apnsToken,
            $platform,
            $timezone,
            $appVersion,
        );

        return Response::json(['id' => $id, 'deviceId' => $deviceKey]);
    }

    /** DELETE /v1/devices/{id} */
    public function removeDevice(Request $request): Response
    {
        $deviceId = Uuid::requireValid($request->param('id'), 'device');

        if (!$this->c->users()->removeDevice($this->userId($request), $deviceId)) {
            throw ApiException::notFound('Device not found.');
        }

        return Response::noContent();
    }
}
