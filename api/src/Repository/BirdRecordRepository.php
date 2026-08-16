<?php

declare(strict_types=1);

namespace RatiteRun\Api\Repository;

use RatiteRun\Api\Core\ApiException;
use RatiteRun\Api\Core\Clock;
use RatiteRun\Api\Core\Database;
use RatiteRun\Api\Core\Uuid;
use RatiteRun\Api\Core\Validator;

final class BirdRecordRepository
{
    public function __construct(private readonly Database $db)
    {
    }

    /** @return list<array<string,mixed>> */
    public function listForFlock(string $flockId, ?string $birdId = null): array
    {
        $sql = 'SELECT * FROM bird_records WHERE flock_id = ?';
        $params = [$flockId];

        if ($birdId !== null) {
            $sql .= ' AND bird_id = ?';
            $params[] = $birdId;
        }

        $sql .= ' ORDER BY recorded_at DESC, id DESC';

        return array_map([self::class, 'present'], $this->db->fetchAll($sql, $params));
    }

    /** @return array<string,mixed> */
    public function find(string $flockId, string $id): array
    {
        $row = $this->db->fetchOne('SELECT * FROM bird_records WHERE id = ? AND flock_id = ?', [$id, $flockId]);

        return $row === null
            ? throw ApiException::notFound('Bird record not found.')
            : self::present($row);
    }

    /**
     * @param array<string,mixed> $input
     * @return array<string,mixed>
     */
    public function create(string $flockId, array $input): array
    {
        $v = new Validator($input);
        $birdId = $v->requiredString('birdId', 80);
        $weight = $v->float('weightKg', 0, 1000);
        $height = $v->float('heightCm', 0, 1000);
        $note = $v->string('note', 2000);
        $recordedAt = $v->isoDate('recordedAt');
        $v->validate();

        $id = Uuid::v4();
        $now = Clock::sql();

        $this->db->run(
            'INSERT INTO bird_records (id, flock_id, bird_id, weight_kg, height_cm, note, recorded_at, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [$id, $flockId, $birdId, $weight ?? 0, $height ?? 0, $note ?? '', Clock::sql($recordedAt), $now, $now],
        );

        return $this->find($flockId, $id);
    }

    /**
     * @param array<string,mixed> $input
     * @return array<string,mixed>
     */
    public function update(string $flockId, string $id, array $input): array
    {
        $this->find($flockId, $id); // 404, если чужая или нет

        $v = new Validator($input);
        $sets = [];
        $params = [];

        if ($v->has('birdId')) {
            $sets[] = 'bird_id = ?';
            $params[] = $v->requiredString('birdId', 80);
        }
        if ($v->has('weightKg')) {
            $sets[] = 'weight_kg = ?';
            $params[] = $v->float('weightKg', 0, 1000);
        }
        if ($v->has('heightCm')) {
            $sets[] = 'height_cm = ?';
            $params[] = $v->float('heightCm', 0, 1000);
        }
        if ($v->has('note')) {
            $sets[] = 'note = ?';
            $params[] = $v->string('note', 2000);
        }
        if ($v->has('recordedAt')) {
            $sets[] = 'recorded_at = ?';
            $params[] = Clock::sql($v->isoDate('recordedAt'));
        }
        $v->validate();

        if ($sets !== []) {
            $sets[] = 'updated_at = ?';
            $params[] = Clock::sql();
            $params[] = $id;
            $params[] = $flockId;

            $this->db->run(
                'UPDATE bird_records SET ' . implode(', ', $sets) . ' WHERE id = ? AND flock_id = ?',
                $params,
            );
        }

        return $this->find($flockId, $id);
    }

    public function delete(string $flockId, string $id): void
    {
        $stmt = $this->db->run('DELETE FROM bird_records WHERE id = ? AND flock_id = ?', [$id, $flockId]);

        if ($stmt->rowCount() === 0) {
            throw ApiException::notFound('Bird record not found.');
        }
    }

    /**
     * Кривая роста по одной птице — данные для графика, которого сейчас нет
     * в приложении, хотя вес и рост уже собираются.
     *
     * @return list<array<string,mixed>>
     */
    public function growthSeries(string $flockId): array
    {
        $rows = $this->db->fetchAll(
            'SELECT bird_id,
                    COUNT(*)          AS points,
                    MIN(recorded_at)  AS first_at,
                    MAX(recorded_at)  AS last_at,
                    MIN(weight_kg)    AS min_weight,
                    MAX(weight_kg)    AS max_weight
             FROM bird_records
             WHERE flock_id = ?
             GROUP BY bird_id
             ORDER BY bird_id',
            [$flockId],
        );

        return array_map(
            static fn (array $r): array => [
                'birdId'     => (string) $r['bird_id'],
                'points'     => (int) $r['points'],
                'firstAt'    => Clock::isoFromSql((string) $r['first_at']),
                'lastAt'     => Clock::isoFromSql((string) $r['last_at']),
                'minWeightKg' => (float) $r['min_weight'],
                'maxWeightKg' => (float) $r['max_weight'],
                'gainKg'     => round((float) $r['max_weight'] - (float) $r['min_weight'], 2),
            ],
            $rows,
        );
    }

    /**
     * @param array<string,mixed> $row
     * @return array<string,mixed>
     */
    public static function present(array $row): array
    {
        return [
            'id'         => (string) $row['id'],
            'birdID'     => (string) $row['bird_id'],
            'weightKg'   => (float) $row['weight_kg'],
            'heightCm'   => (float) $row['height_cm'],
            'note'       => (string) ($row['note'] ?? ''),
            'date'       => Clock::isoFromSql((string) $row['recorded_at']),
        ];
    }
}
