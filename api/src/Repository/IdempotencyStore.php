<?php

declare(strict_types=1);

namespace RatiteRun\Api\Repository;

use RatiteRun\Api\Core\ApiException;
use RatiteRun\Api\Core\Clock;
use RatiteRun\Api\Core\Database;
use RatiteRun\Api\Core\Uuid;

/**
 * Idempotency-Key на POST. Повторный запрос с тем же ключом и тем же телом
 * возвращает сохранённый ответ вместо создания дубликата.
 */
final class IdempotencyStore
{
    public function __construct(private readonly Database $db)
    {
    }

    /**
     * Возвращает готовый ответ, если этот ключ уже отработал.
     *
     * @return array{statusCode:int,body:mixed}|null
     * @throws ApiException 409 если ключ переиспользован с другим телом
     */
    public function lookup(string $userId, string $key, string $method, string $path, string $rawBody): ?array
    {
        $hash = hash('sha256', $method . '|' . $path . '|' . $rawBody);

        $row = $this->db->fetchOne(
            'SELECT * FROM idempotency_keys WHERE user_id = ? AND idem_key = ?',
            [$userId, $key],
        );

        if ($row === null) {
            return null;
        }

        if ((string) $row['request_hash'] !== $hash) {
            throw ApiException::conflict('This Idempotency-Key was already used with a different request body.');
        }

        if ($row['status_code'] === null) {
            // предыдущая попытка ещё в работе или упала на полпути
            throw ApiException::conflict('A request with this Idempotency-Key is already in progress.');
        }

        return [
            'statusCode' => (int) $row['status_code'],
            'body'       => is_string($row['response_body']) ? json_decode($row['response_body'], true) : null,
        ];
    }

    public function begin(string $userId, string $key, string $method, string $path, string $rawBody): void
    {
        $this->db->run(
            'INSERT INTO idempotency_keys (id, user_id, idem_key, method, path, request_hash, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?)',
            [
                Uuid::v4(), $userId, $key, $method, $path,
                hash('sha256', $method . '|' . $path . '|' . $rawBody),
                Clock::sql(),
            ],
        );
    }

    public function complete(string $userId, string $key, int $statusCode, mixed $body): void
    {
        $this->db->run(
            'UPDATE idempotency_keys SET status_code = ?, response_body = ? WHERE user_id = ? AND idem_key = ?',
            [$statusCode, json_encode($body, JSON_UNESCAPED_UNICODE), $userId, $key],
        );
    }

    /** Неудавшаяся попытка не должна блокировать повтор. */
    public function abandon(string $userId, string $key): void
    {
        $this->db->run(
            'DELETE FROM idempotency_keys WHERE user_id = ? AND idem_key = ? AND status_code IS NULL',
            [$userId, $key],
        );
    }

    public function purge(int $olderThanHours = 48): int
    {
        $stmt = $this->db->run(
            'DELETE FROM idempotency_keys WHERE created_at < ?',
            [Clock::sql(Clock::now()->sub(new \DateInterval('PT' . $olderThanHours . 'H')))],
        );

        return $stmt->rowCount();
    }
}
