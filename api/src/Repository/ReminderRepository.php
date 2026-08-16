<?php

declare(strict_types=1);

namespace RatiteRun\Api\Repository;

use RatiteRun\Api\Core\ApiException;
use RatiteRun\Api\Core\Clock;
use RatiteRun\Api\Core\Database;
use RatiteRun\Api\Core\Uuid;
use RatiteRun\Api\Core\Validator;
use RatiteRun\Api\Domain\ReminderKind;

final class ReminderRepository
{
    public function __construct(private readonly Database $db)
    {
    }

    /** @return list<array<string,mixed>> */
    public function listForFlock(string $flockId): array
    {
        return array_map(
            [self::class, 'present'],
            $this->db->fetchAll('SELECT * FROM reminders WHERE flock_id = ? ORDER BY hour, minute', [$flockId]),
        );
    }

    /** @return array<string,mixed> */
    public function find(string $flockId, string $id): array
    {
        $row = $this->db->fetchOne('SELECT * FROM reminders WHERE id = ? AND flock_id = ?', [$id, $flockId]);

        return $row === null
            ? throw ApiException::notFound('Reminder not found.')
            : self::present($row);
    }

    /**
     * @param array<string,mixed> $input
     * @return array<string,mixed>
     */
    public function create(string $flockId, array $input): array
    {
        $v = new Validator($input);
        $kindValue = $v->requiredEnum('kind', ReminderKind::values());
        $title = $v->string('title', 160);
        $hour = $v->int('hour', 0, 23);
        $minute = $v->int('minute', 0, 59);
        $enabled = $v->bool('enabled');
        $v->validate();

        $kind = ReminderKind::from((string) $kindValue);
        $id = Uuid::v4();
        $now = Clock::sql();

        $this->db->run(
            'INSERT INTO reminders (id, flock_id, kind, title, hour, minute, enabled, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
                $id, $flockId, $kind->value,
                ($title === null || $title === '') ? $kind->label() : $title,
                $hour ?? 8, $minute ?? 0, ($enabled ?? true) ? 1 : 0, $now, $now,
            ],
        );

        return $this->find($flockId, $id);
    }

    /**
     * @param array<string,mixed> $input
     * @return array<string,mixed>
     */
    public function update(string $flockId, string $id, array $input): array
    {
        $this->find($flockId, $id);

        $v = new Validator($input);
        $sets = [];
        $params = [];

        if ($v->has('kind')) {
            $sets[] = 'kind = ?';
            $params[] = $v->requiredEnum('kind', ReminderKind::values());
        }
        if ($v->has('title')) {
            $sets[] = 'title = ?';
            $params[] = $v->string('title', 160);
        }
        if ($v->has('hour')) {
            $sets[] = 'hour = ?';
            $params[] = $v->int('hour', 0, 23);
        }
        if ($v->has('minute')) {
            $sets[] = 'minute = ?';
            $params[] = $v->int('minute', 0, 59);
        }
        if ($v->has('enabled')) {
            $sets[] = 'enabled = ?';
            $params[] = $v->bool('enabled') ? 1 : 0;
        }
        $v->validate();

        if ($sets !== []) {
            $sets[] = 'updated_at = ?';
            $params[] = Clock::sql();
            $params[] = $id;
            $params[] = $flockId;

            $this->db->run(
                'UPDATE reminders SET ' . implode(', ', $sets) . ' WHERE id = ? AND flock_id = ?',
                $params,
            );
        }

        return $this->find($flockId, $id);
    }

    public function delete(string $flockId, string $id): void
    {
        $stmt = $this->db->run('DELETE FROM reminders WHERE id = ? AND flock_id = ?', [$id, $flockId]);

        if ($stmt->rowCount() === 0) {
            throw ApiException::notFound('Reminder not found.');
        }
    }

    /**
     * @param array<string,mixed> $row
     * @return array<string,mixed>
     */
    public static function present(array $row): array
    {
        return [
            'id'      => (string) $row['id'],
            'kind'    => (string) $row['kind'],
            'title'   => (string) $row['title'],
            'hour'    => (int) $row['hour'],
            'minute'  => (int) $row['minute'],
            'enabled' => (bool) $row['enabled'],
        ];
    }
}
