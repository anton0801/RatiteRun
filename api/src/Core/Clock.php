<?php

declare(strict_types=1);

namespace RatiteRun\Api\Core;

/**
 * Всё время в UTC. Наружу — ISO-8601 с миллисекундами, как ждёт Swift-клиент.
 */
final class Clock
{
    public const SQL_FORMAT = 'Y-m-d H:i:s.v';
    public const ISO_FORMAT = 'Y-m-d\TH:i:s.v\Z';

    public static function now(): \DateTimeImmutable
    {
        return new \DateTimeImmutable('now', new \DateTimeZone('UTC'));
    }

    /** Формат для DATETIME(3) в MySQL. */
    public static function sql(?\DateTimeImmutable $at = null): string
    {
        return ($at ?? self::now())->format(self::SQL_FORMAT);
    }

    /** Формат для JSON-ответа. */
    public static function iso(?\DateTimeImmutable $at = null): string
    {
        return ($at ?? self::now())->setTimezone(new \DateTimeZone('UTC'))->format(self::ISO_FORMAT);
    }

    /** Строка из БД → ISO-8601 для ответа. */
    public static function isoFromSql(?string $sqlValue): ?string
    {
        if ($sqlValue === null || $sqlValue === '') {
            return null;
        }

        $dt = \DateTimeImmutable::createFromFormat('Y-m-d H:i:s.u', $sqlValue, new \DateTimeZone('UTC'))
            ?: \DateTimeImmutable::createFromFormat('Y-m-d H:i:s', $sqlValue, new \DateTimeZone('UTC'));

        return $dt === false ? null : $dt->format(self::ISO_FORMAT);
    }

    /**
     * Разбирает ISO-8601 из тела запроса.
     *
     * @throws ApiException 422 если формат не распознан
     */
    public static function parseIso(string $value, string $field): \DateTimeImmutable
    {
        try {
            $dt = new \DateTimeImmutable($value);
        } catch (\Exception) {
            throw ApiException::validation([$field => ['Must be an ISO-8601 date-time string.']]);
        }

        return $dt->setTimezone(new \DateTimeZone('UTC'));
    }
}
