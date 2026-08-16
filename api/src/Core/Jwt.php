<?php

declare(strict_types=1);

namespace RatiteRun\Api\Core;

/**
 * HS256 JWT без внешних зависимостей.
 */
final class Jwt
{
    /**
     * @param array<string,mixed> $claims
     */
    public static function encode(array $claims, string $secret, int $ttlSeconds): string
    {
        $now = time();
        $payload = array_merge($claims, [
            'iat' => $now,
            'nbf' => $now,
            'exp' => $now + $ttlSeconds,
            'jti' => bin2hex(random_bytes(8)),
        ]);

        $segments = [
            self::base64UrlEncode(self::jsonEncode(['alg' => 'HS256', 'typ' => 'JWT'])),
            self::base64UrlEncode(self::jsonEncode($payload)),
        ];

        $signing = implode('.', $segments);
        $signature = hash_hmac('sha256', $signing, $secret, true);
        $segments[] = self::base64UrlEncode($signature);

        return implode('.', $segments);
    }

    /**
     * @return array<string,mixed>
     * @throws ApiException 401 при любой проблеме с токеном
     */
    public static function decode(string $token, string $secret): array
    {
        $parts = explode('.', $token);
        if (count($parts) !== 3) {
            throw ApiException::unauthorized('Malformed access token.');
        }

        [$header64, $payload64, $signature64] = $parts;

        $expected = hash_hmac('sha256', $header64 . '.' . $payload64, $secret, true);
        $actual = self::base64UrlDecode($signature64);

        if ($actual === null || !hash_equals($expected, $actual)) {
            throw ApiException::unauthorized('Access token signature is invalid.');
        }

        $headerJson = self::base64UrlDecode($header64);
        $header = $headerJson === null ? null : json_decode($headerJson, true);
        if (!is_array($header) || ($header['alg'] ?? null) !== 'HS256') {
            throw ApiException::unauthorized('Unsupported token algorithm.');
        }

        $payloadJson = self::base64UrlDecode($payload64);
        $payload = $payloadJson === null ? null : json_decode($payloadJson, true);
        if (!is_array($payload)) {
            throw ApiException::unauthorized('Access token payload is invalid.');
        }

        $now = time();
        if (isset($payload['nbf']) && is_int($payload['nbf']) && $now < $payload['nbf'] - 60) {
            throw ApiException::unauthorized('Access token is not valid yet.');
        }
        if (!isset($payload['exp']) || !is_int($payload['exp'])) {
            throw ApiException::unauthorized('Access token has no expiry.');
        }
        if ($now >= $payload['exp']) {
            throw ApiException::unauthorized('Access token has expired.');
        }

        /** @var array<string,mixed> $payload */
        return $payload;
    }

    private static function jsonEncode(mixed $value): string
    {
        return json_encode($value, JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
    }

    private static function base64UrlEncode(string $data): string
    {
        return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
    }

    private static function base64UrlDecode(string $data): ?string
    {
        $padded = strtr($data, '-_', '+/');
        $remainder = strlen($padded) % 4;
        if ($remainder !== 0) {
            $padded .= str_repeat('=', 4 - $remainder);
        }

        $decoded = base64_decode($padded, true);

        return $decoded === false ? null : $decoded;
    }
}
