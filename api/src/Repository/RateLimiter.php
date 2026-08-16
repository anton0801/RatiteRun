<?php

declare(strict_types=1);

namespace RatiteRun\Api\Repository;

use RatiteRun\Api\Core\ApiException;
use RatiteRun\Api\Core\Database;

/**
 * Ограничитель с фиксированным окном на таблице MySQL — без Redis.
 * Для одного инстанса этого достаточно; при масштабировании заменить на Redis.
 */
final class RateLimiter
{
    public function __construct(private readonly Database $db)
    {
    }

    /**
     * @throws ApiException 429 при превышении
     */
    public function hit(string $bucket, int $limit, int $windowSeconds): void
    {
        $now = time();
        $windowStart = $now - ($now % $windowSeconds);
        $windowAt = gmdate('Y-m-d H:i:s', $windowStart);

        $this->db->run(
            'INSERT INTO rate_limits (bucket, window_at, hits) VALUES (?, ?, 1)
             ON DUPLICATE KEY UPDATE hits = hits + 1',
            [$bucket, $windowAt],
        );

        $hits = (int) $this->db->fetchValue(
            'SELECT hits FROM rate_limits WHERE bucket = ? AND window_at = ?',
            [$bucket, $windowAt],
        );

        if ($hits > $limit) {
            throw ApiException::tooManyRequests($windowStart + $windowSeconds - $now);
        }
    }

    /** Чистка старых окон — из bin/cleanup.php. */
    public function purge(): int
    {
        $stmt = $this->db->run(
            'DELETE FROM rate_limits WHERE window_at < ?',
            [gmdate('Y-m-d H:i:s', time() - 86400)],
        );

        return $stmt->rowCount();
    }
}
