<?php

declare(strict_types=1);

namespace RatiteRun\Api\Core;

/**
 * Защита веб-формы от подделки запроса (double submit cookie).
 *
 * Сервер генерирует случайное значение, кладёт его одновременно в HttpOnly-куку
 * и в скрытое поле формы. При отправке значения должны совпасть. Прочитать
 * куку чужой сайт не может (HttpOnly + SameSite=Strict), угадать поле — тоже.
 *
 * Состояние на сервере не хранится: токен самодостаточен, таблица не нужна.
 */
final class Csrf
{
    public const COOKIE = 'rr_csrf';
    public const FIELD  = '_token';

    /** Выпускает токен и возвращает значение для скрытого поля. */
    public static function issue(): string
    {
        $token = rtrim(strtr(base64_encode(random_bytes(32)), '+/', '-_'), '=');

        setcookie(self::COOKIE, $token, [
            'expires'  => time() + 7200,
            'path'     => '/',
            'secure'   => !Config::bool('ALLOW_INSECURE_COOKIES', false),
            'httponly' => true,
            'samesite' => 'Strict',
        ]);

        return $token;
    }

    /**
     * @param array<string,mixed> $formData
     * @throws ApiException 403 если токены не совпали
     */
    public static function verify(Request $request, array $formData): void
    {
        $fromCookie = $request->cookie(self::COOKIE);
        $fromForm = $formData[self::FIELD] ?? null;

        if (!is_string($fromCookie) || $fromCookie === ''
            || !is_string($fromForm) || $fromForm === ''
            || !hash_equals($fromCookie, $fromForm)
        ) {
            throw ApiException::forbidden(
                'Your session expired while the form was open. Reload the page and send it again.',
            );
        }
    }

    public static function clear(): void
    {
        setcookie(self::COOKIE, '', [
            'expires'  => time() - 3600,
            'path'     => '/',
            'secure'   => !Config::bool('ALLOW_INSECURE_COOKIES', false),
            'httponly' => true,
            'samesite' => 'Strict',
        ]);
    }
}
