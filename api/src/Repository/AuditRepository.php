<?php

declare(strict_types=1);

namespace RatiteRun\Api\Repository;

use RatiteRun\Api\Core\Clock;
use RatiteRun\Api\Core\Database;

/**
 * Журнал изменений — «кто и когда поменял высоту забора».
 * Пишется best-effort: сбой аудита не должен ронять основной запрос.
 */
final class AuditRepository
{
    public function __construct(private readonly Database $db)
    {
    }

    /** @param array<string,mixed>|null $payload */
    public function record(string $userId, ?string $flockId, string $action, ?string $path, ?array $payload, ?string $ip): void
    {
        try {
            $this->db->run(
                'INSERT INTO audit_log (user_id, flock_id, action, path, payload, ip, created_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?)',
                [
                    $userId,
                    $flockId,
                    $action,
                    $path,
                    $payload === null ? null : json_encode($payload, JSON_UNESCAPED_UNICODE),
                    $ip === null ? null : (@inet_pton($ip) ?: null),
                    Clock::sql(),
                ],
            );
        } catch (\Throwable) {
            // намеренно проглатываем
        }
    }

    /** @return list<array<string,mixed>> */
    public function listForFlock(string $flockId, int $limit = 100): array
    {
        $rows = $this->db->fetchAll(
            'SELECT id, action, path, payload, created_at FROM audit_log
             WHERE flock_id = ? ORDER BY id DESC LIMIT ' . $limit,
            [$flockId],
        );

        return array_map(
            static fn (array $r): array => [
                'id'        => (int) $r['id'],
                'action'    => (string) $r['action'],
                'path'      => $r['path'] ?? null,
                'payload'   => is_string($r['payload']) ? json_decode($r['payload'], true) : null,
                'createdAt' => Clock::isoFromSql((string) $r['created_at']),
            ],
            $rows,
        );
    }
}
