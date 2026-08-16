<?php

declare(strict_types=1);

namespace RatiteRun\Api\Core;

/**
 * UUID v4. Swift-клиент шлёт UUID в верхнем регистре — храним и отдаём так же,
 * чтобы `UUID(uuidString:)` на клиенте совпадал побайтово.
 */
final class Uuid
{
    private const PATTERN = '/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/';

    public static function v4(): string
    {
        $bytes = random_bytes(16);
        $bytes[6] = chr((ord($bytes[6]) & 0x0f) | 0x40);
        $bytes[8] = chr((ord($bytes[8]) & 0x3f) | 0x80);

        $hex = strtoupper(bin2hex($bytes));

        return sprintf(
            '%s-%s-%s-%s-%s',
            substr($hex, 0, 8),
            substr($hex, 8, 4),
            substr($hex, 12, 4),
            substr($hex, 16, 4),
            substr($hex, 20, 12),
        );
    }

    public static function isValid(string $value): bool
    {
        return preg_match(self::PATTERN, $value) === 1;
    }

    /** Приводит к каноничному верхнему регистру. */
    public static function normalize(string $value): string
    {
        return strtoupper(trim($value));
    }

    /** @throws ApiException 404 — невалидный id снаружи неотличим от отсутствующего */
    public static function requireValid(string $value, string $what = 'resource'): string
    {
        $normalized = self::normalize($value);
        if (!self::isValid($normalized)) {
            throw ApiException::notFound(ucfirst($what) . ' id is not a valid UUID.');
        }

        return $normalized;
    }
}
