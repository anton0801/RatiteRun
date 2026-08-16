<?php

declare(strict_types=1);

namespace RatiteRun\Api\Repository;

use RatiteRun\Api\Core\ApiException;
use RatiteRun\Api\Core\Clock;
use RatiteRun\Api\Core\Config;
use RatiteRun\Api\Core\Database;
use RatiteRun\Api\Core\Uuid;

final class ReportRepository
{
    public function __construct(private readonly Database $db)
    {
    }

    /**
     * @param list<string>        $sections
     * @param array<string,mixed> $snapshot
     * @return array<string,mixed>
     */
    public function create(
        string $userId,
        string $flockId,
        array $sections,
        string $notes,
        string $currency,
        array $snapshot,
        string $pdfKey,
        bool $shareable,
    ): array {
        $id = Uuid::v4();
        $ttlDays = Config::int('REPORT_TTL_DAYS', 30);
        $expiresAt = Clock::now()->add(new \DateInterval('P' . $ttlDays . 'D'));

        $this->db->run(
            'INSERT INTO reports (id, flock_id, user_id, status, sections, notes, currency, snapshot,
                                  share_token, pdf_key, created_at, expires_at)
             VALUES (?, ?, ?, "ready", ?, ?, ?, ?, ?, ?, ?, ?)',
            [
                $id,
                $flockId,
                $userId,
                json_encode($sections, JSON_UNESCAPED_UNICODE),
                $notes,
                $currency,
                json_encode($snapshot, JSON_UNESCAPED_UNICODE),
                $shareable ? bin2hex(random_bytes(16)) : null,
                $pdfKey,
                Clock::sql(),
                Clock::sql($expiresAt),
            ],
        );

        return $this->find($userId, $id);
    }

    /** @return array<string,mixed> */
    public function find(string $userId, string $id): array
    {
        $row = $this->db->fetchOne('SELECT * FROM reports WHERE id = ? AND user_id = ?', [$id, $userId]);

        return $row === null
            ? throw ApiException::notFound('Report not found.')
            : $this->present($row);
    }

    /** @return array<string,mixed>|null публичный доступ по токену — без авторизации */
    public function findByShareToken(string $token): ?array
    {
        $row = $this->db->fetchOne('SELECT * FROM reports WHERE share_token = ?', [$token]);

        if ($row === null) {
            return null;
        }

        $expiresAt = Clock::isoFromSql(is_string($row['expires_at']) ? $row['expires_at'] : null);
        if ($expiresAt !== null && new \DateTimeImmutable($expiresAt) <= Clock::now()) {
            return null;
        }

        return $row;
    }

    /** @return list<array<string,mixed>> */
    public function listForFlock(string $userId, string $flockId, int $limit = 25): array
    {
        return array_map(
            [$this, 'present'],
            $this->db->fetchAll(
                'SELECT * FROM reports WHERE flock_id = ? AND user_id = ? ORDER BY created_at DESC LIMIT ' . $limit,
                [$flockId, $userId],
            ),
        );
    }

    public function pdfKey(string $userId, string $id): string
    {
        $key = $this->db->fetchValue(
            'SELECT pdf_key FROM reports WHERE id = ? AND user_id = ? AND status = "ready"',
            [$id, $userId],
        );

        return is_string($key) && $key !== ''
            ? $key
            : throw ApiException::notFound('Report PDF is not available.');
    }

    /**
     * @param array<string,mixed> $row
     * @return array<string,mixed>
     */
    private function present(array $row): array
    {
        $shareToken = $row['share_token'] ?? null;

        return [
            'id'        => (string) $row['id'],
            'flockId'   => (string) $row['flock_id'],
            'status'    => (string) $row['status'],
            'sections'  => is_string($row['sections']) ? json_decode($row['sections'], true) : [],
            'notes'     => (string) ($row['notes'] ?? ''),
            'currency'  => (string) $row['currency'],
            'pdfUrl'    => '/v1/reports/' . $row['id'] . '/pdf',
            'shareUrl'  => is_string($shareToken) ? '/v1/shared/reports/' . $shareToken : null,
            'createdAt' => Clock::isoFromSql((string) $row['created_at']),
            'expiresAt' => Clock::isoFromSql(is_string($row['expires_at']) ? $row['expires_at'] : null),
        ];
    }

    /** @return list<string> ключи PDF, которые можно удалить с диска */
    public function purgeExpired(): array
    {
        $rows = $this->db->fetchAll(
            'SELECT id, pdf_key FROM reports WHERE expires_at IS NOT NULL AND expires_at < ?',
            [Clock::sql()],
        );

        if ($rows === []) {
            return [];
        }

        $ids = array_map(static fn (array $r): string => (string) $r['id'], $rows);
        $placeholders = implode(',', array_fill(0, count($ids), '?'));
        $this->db->run("DELETE FROM reports WHERE id IN ({$placeholders})", $ids);

        return array_values(array_filter(
            array_map(static fn (array $r): ?string => is_string($r['pdf_key']) ? $r['pdf_key'] : null, $rows),
        ));
    }
}
