<?php

declare(strict_types=1);

namespace RatiteRun\Api\Repository;

use RatiteRun\Api\Core\ApiException;
use RatiteRun\Api\Core\Clock;
use RatiteRun\Api\Core\Database;
use RatiteRun\Api\Core\Uuid;
use RatiteRun\Api\Core\Validator;
use RatiteRun\Api\Domain\LayoutKind;

final class LayoutRepository
{
    private const MAX_ITEMS = 200;

    public function __construct(private readonly Database $db)
    {
    }

    /** @return list<array<string,mixed>> */
    public function listForFlock(string $flockId): array
    {
        return array_map(
            [self::class, 'present'],
            $this->db->fetchAll('SELECT * FROM layout_items WHERE flock_id = ? ORDER BY created_at', [$flockId]),
        );
    }

    /** @return array<string,mixed> */
    public function find(string $flockId, string $id): array
    {
        $row = $this->db->fetchOne('SELECT * FROM layout_items WHERE id = ? AND flock_id = ?', [$id, $flockId]);

        return $row === null
            ? throw ApiException::notFound('Layout item not found.')
            : self::present($row);
    }

    /**
     * @param array<string,mixed> $input
     * @return array<string,mixed>
     */
    public function create(string $flockId, array $input): array
    {
        $count = (int) $this->db->fetchValue('SELECT COUNT(*) FROM layout_items WHERE flock_id = ?', [$flockId]);
        if ($count >= self::MAX_ITEMS) {
            throw ApiException::conflict('Layout board is full (max ' . self::MAX_ITEMS . ' items).');
        }

        $v = new Validator($input);
        $kind = $v->requiredEnum('kind', LayoutKind::values());
        $x = $v->float('x', 0, 1);
        $y = $v->float('y', 0, 1);
        $v->validate();

        $id = Uuid::v4();
        $now = Clock::sql();

        $this->db->run(
            'INSERT INTO layout_items (id, flock_id, kind, x, y, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
            [$id, $flockId, $kind, $x ?? 0.5, $y ?? 0.5, $now, $now],
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
            $params[] = $v->requiredEnum('kind', LayoutKind::values());
        }
        if ($v->has('x')) {
            $sets[] = 'x = ?';
            $params[] = $v->float('x', 0, 1);
        }
        if ($v->has('y')) {
            $sets[] = 'y = ?';
            $params[] = $v->float('y', 0, 1);
        }
        $v->validate();

        if ($sets !== []) {
            $sets[] = 'updated_at = ?';
            $params[] = Clock::sql();
            $params[] = $id;
            $params[] = $flockId;

            $this->db->run(
                'UPDATE layout_items SET ' . implode(', ', $sets) . ' WHERE id = ? AND flock_id = ?',
                $params,
            );
        }

        return $this->find($flockId, $id);
    }

    public function delete(string $flockId, string $id): void
    {
        $stmt = $this->db->run('DELETE FROM layout_items WHERE id = ? AND flock_id = ?', [$id, $flockId]);

        if ($stmt->rowCount() === 0) {
            throw ApiException::notFound('Layout item not found.');
        }
    }

    /**
     * Замена всей доски целиком — LayoutBoardView двигает объекты пачкой,
     * поштучные PATCH на каждый кадр перетаскивания не нужны.
     *
     * @param list<mixed> $items
     * @return list<array<string,mixed>>
     */
    public function replaceAll(string $flockId, array $items): array
    {
        if (count($items) > self::MAX_ITEMS) {
            throw ApiException::validation(['items' => ['At most ' . self::MAX_ITEMS . ' layout items allowed.']]);
        }

        $validated = [];
        foreach ($items as $index => $item) {
            if (!is_array($item)) {
                throw ApiException::validation(["items.{$index}" => ['Must be an object.']]);
            }

            $v = new Validator($item);
            $kind = $v->requiredEnum('kind', LayoutKind::values());
            $x = $v->float('x', 0, 1);
            $y = $v->float('y', 0, 1);

            if ($v->fails()) {
                $prefixed = [];
                foreach ($v->errors() as $field => $messages) {
                    $prefixed["items.{$index}.{$field}"] = $messages;
                }
                throw ApiException::validation($prefixed);
            }

            $validated[] = ['kind' => $kind, 'x' => $x ?? 0.5, 'y' => $y ?? 0.5];
        }

        return $this->db->transaction(function (Database $db) use ($flockId, $validated): array {
            $db->run('DELETE FROM layout_items WHERE flock_id = ?', [$flockId]);

            $now = Clock::sql();
            foreach ($validated as $item) {
                $db->run(
                    'INSERT INTO layout_items (id, flock_id, kind, x, y, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
                    [Uuid::v4(), $flockId, $item['kind'], $item['x'], $item['y'], $now, $now],
                );
            }

            return $this->listForFlock($flockId);
        });
    }

    /**
     * @param array<string,mixed> $row
     * @return array<string,mixed>
     */
    public static function present(array $row): array
    {
        return [
            'id'   => (string) $row['id'],
            'kind' => (string) $row['kind'],
            'x'    => (float) $row['x'],
            'y'    => (float) $row['y'],
        ];
    }
}
