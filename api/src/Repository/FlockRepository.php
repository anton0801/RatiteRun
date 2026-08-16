<?php

declare(strict_types=1);

namespace RatiteRun\Api\Repository;

use RatiteRun\Api\Core\ApiException;
use RatiteRun\Api\Core\Clock;
use RatiteRun\Api\Core\Database;
use RatiteRun\Api\Core\Uuid;
use RatiteRun\Api\Domain\Engines;
use RatiteRun\Api\Domain\FlockSections;
use RatiteRun\Api\Domain\Species;

final class FlockRepository
{
    public function __construct(
        private readonly Database $db,
        private readonly PresetRepository $presets,
    ) {
    }

    // -- чтение ---------------------------------------------------------------

    /**
     * Список сводок. Полные агрегаты здесь не отдаются — иначе выбор стада
     * в приложении тянет мегабайты.
     *
     * @return array{items:list<array<string,mixed>>,nextCursor:?string}
     */
    public function list(string $userId, ?string $status, ?string $species, int $limit, ?string $cursor): array
    {
        $sql = 'SELECT id, title, species, bird_count, age, priority, status, photo_key,
                       readiness_percent, version, created_at, updated_at
                FROM flocks
                WHERE user_id = ? AND deleted_at IS NULL';
        $params = [$userId];

        if ($status !== null) {
            $sql .= ' AND status = ?';
            $params[] = $status;
        }
        if ($species !== null) {
            $sql .= ' AND species = ?';
            $params[] = $species;
        }

        if ($cursor !== null) {
            $decoded = $this->decodeCursor($cursor);
            $sql .= ' AND (updated_at < ? OR (updated_at = ? AND id < ?))';
            $params[] = $decoded['updatedAt'];
            $params[] = $decoded['updatedAt'];
            $params[] = $decoded['id'];
        }

        // +1 строка, чтобы понять, есть ли следующая страница
        $sql .= ' ORDER BY updated_at DESC, id DESC LIMIT ' . ($limit + 1);

        $rows = $this->db->fetchAll($sql, $params);

        $nextCursor = null;
        if (count($rows) > $limit) {
            $last = $rows[$limit - 1];
            $nextCursor = $this->encodeCursor((string) $last['updated_at'], (string) $last['id']);
            $rows = array_slice($rows, 0, $limit);
        }

        return [
            'items'      => array_map([$this, 'presentSummary'], $rows),
            'nextCursor' => $nextCursor,
        ];
    }

    /** @return array<string,mixed>|null сырая строка без коллекций */
    public function findRow(string $userId, string $flockId): ?array
    {
        return $this->db->fetchOne(
            'SELECT * FROM flocks WHERE id = ? AND user_id = ? AND deleted_at IS NULL',
            [$flockId, $userId],
        );
    }

    /** @return array<string,mixed> @throws ApiException 404 */
    public function requireRow(string $userId, string $flockId): array
    {
        return $this->findRow($userId, $flockId)
            ?? throw ApiException::notFound('Flock not found.');
    }

    /**
     * Полный агрегат вместе с коллекциями.
     *
     * @return array<string,mixed>
     */
    public function findFull(string $userId, string $flockId): array
    {
        $row = $this->requireRow($userId, $flockId);

        return $this->presentFull($row);
    }

    // -- запись ---------------------------------------------------------------

    /**
     * @param array<string,mixed> $input
     * @return array<string,mixed> полный агрегат
     */
    public function create(string $userId, array $input): array
    {
        $now = Clock::sql();

        // Клиент может задать id сам: приложение вставляет стадо в список
        // оптимистично и не должно потом переклеивать идентификатор.
        $id = isset($input['id']) && is_string($input['id'])
            ? Uuid::normalize($input['id'])
            : Uuid::v4();

        if ($this->db->fetchValue('SELECT 1 FROM flocks WHERE id = ?', [$id]) !== null) {
            throw ApiException::conflict('A flock with this id already exists.');
        }

        $species = Species::from((string) ($input['species'] ?? 'emu'));
        $preset = $this->presets->find($species);

        $sections = FlockSections::allDefaults();

        // те же стартовые значения, что даёт AppStore.addEmpty() на клиенте
        $sections['housing']['spacePerBird'] = $preset->spacePerBirdM2;
        $sections['fencing']['height']       = $preset->recFenceHeightM;
        $sections['fencing']['strength']     = $preset->recFenceStrength;
        $sections['feed']['proteinPct']      = $preset->targetProteinPct;

        $core = [
            'title'    => (string) ($input['title'] ?? 'New Flock'),
            'species'  => $species->value,
            'count'    => (int) ($input['count'] ?? 2),
            'age'      => (string) ($input['age'] ?? 'Adult'),
            'notes'    => (string) ($input['notes'] ?? ''),
            'priority' => (string) ($input['priority'] ?? 'medium'),
            'status'   => (string) ($input['status'] ?? 'setup'),
        ];

        $sections['kit'] = Engines::materials($core + $sections, $preset);
        $readiness = Engines::readiness($core + $sections, $preset);

        $this->db->run(
            'INSERT INTO flocks
                (id, user_id, title, species, bird_count, age, notes, priority, status,
                 housing, fencing, feed, water_grit, handling, breeding, rearing, health,
                 predator, terrain, kit, signoff, markup,
                 readiness_percent, version, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)',
            [
                $id, $userId, $core['title'], $core['species'], $core['count'], $core['age'],
                $core['notes'], $core['priority'], $core['status'],
                $this->encode($sections['housing']),
                $this->encode($sections['fencing']),
                $this->encode($sections['feed']),
                $this->encode($sections['waterGrit']),
                $this->encode($sections['handling']),
                $this->encode($sections['breeding']),
                $this->encode($sections['rearing']),
                $this->encode($sections['health']),
                $this->encode($sections['predator']),
                $this->encode($sections['terrain']),
                $this->encode($sections['kit']),
                $this->encode($sections['signoff']),
                $this->encode($sections['markup']),
                $readiness['percent'],
                $now, $now,
            ],
        );

        return $this->findFull($userId, $id);
    }

    /**
     * Обновление полей верхнего уровня (PATCH /flocks/{id}).
     *
     * @param array<string,mixed> $changes
     * @return array<string,mixed>
     */
    public function updateCore(string $userId, string $flockId, array $changes, ?string $expectedVersion): array
    {
        return $this->db->transaction(function (Database $db) use ($userId, $flockId, $changes, $expectedVersion): array {
            $row = $this->lockRow($db, $userId, $flockId, $expectedVersion);

            $map = [
                'title'    => 'title',
                'species'  => 'species',
                'count'    => 'bird_count',
                'age'      => 'age',
                'notes'    => 'notes',
                'priority' => 'priority',
                'status'   => 'status',
            ];

            $sets = [];
            $params = [];
            foreach ($map as $field => $column) {
                if (array_key_exists($field, $changes)) {
                    $sets[] = "{$column} = ?";
                    $params[] = $changes[$field];
                    $row[$column] = $changes[$field];
                }
            }

            if ($sets === []) {
                return $this->presentFull($row);
            }

            // смена вида или поголовья меняет и норматив, и смету
            $preset = $this->presets->find(Species::from((string) $row['species']));
            $flock = $this->toEngineInput($row);
            $kit = Engines::materials($flock, $preset);
            $flock['kit'] = $kit;
            $readiness = Engines::readiness($flock, $preset);

            $sets[] = 'kit = ?';
            $params[] = $this->encode($kit);
            $sets[] = 'readiness_percent = ?';
            $params[] = $readiness['percent'];
            $sets[] = 'version = version + 1';
            $sets[] = 'updated_at = ?';
            $params[] = Clock::sql();

            $params[] = $flockId;

            $db->run('UPDATE flocks SET ' . implode(', ', $sets) . ' WHERE id = ?', $params);

            return $this->findFull($userId, $flockId);
        });
    }

    /**
     * PUT /flocks/{id}/{section}
     *
     * @param array<string,mixed> $input
     * @return array{section:array<string,mixed>,version:int}
     */
    public function updateSection(string $userId, string $flockId, string $section, array $input, ?string $expectedVersion): array
    {
        if (!in_array($section, FlockSections::WRITABLE, true)) {
            throw ApiException::notFound('Unknown flock section.');
        }

        return $this->db->transaction(function (Database $db) use ($userId, $flockId, $section, $input, $expectedVersion): array {
            $row = $this->lockRow($db, $userId, $flockId, $expectedVersion);

            $column = FlockSections::COLUMNS[$section];
            $current = $this->decode($row[$column] ?? null);
            $validated = FlockSections::validate($section, $input, $current);

            $row[$column] = $this->encode($validated);

            $preset = $this->presets->find(Species::from((string) $row['species']));
            $flock = $this->toEngineInput($row);

            // площадь и поголовье влияют на смету материалов
            $kit = Engines::materials($flock, $preset);
            $flock['kit'] = $kit;
            $readiness = Engines::readiness($flock, $preset);

            $db->run(
                "UPDATE flocks SET {$column} = ?, kit = ?, readiness_percent = ?, version = version + 1, updated_at = ?
                 WHERE id = ?",
                [$this->encode($validated), $this->encode($kit), $readiness['percent'], Clock::sql(), $flockId],
            );

            return [
                'section' => $validated,
                'version' => (int) $row['version'] + 1,
            ];
        });
    }

    /** @return array<string,mixed> */
    public function duplicate(string $userId, string $flockId): array
    {
        return $this->db->transaction(function (Database $db) use ($userId, $flockId): array {
            $row = $this->requireRow($userId, $flockId);
            $newId = Uuid::v4();
            $now = Clock::sql();

            $db->run(
                'INSERT INTO flocks
                    (id, user_id, title, species, bird_count, age, notes, priority, status,
                     housing, fencing, feed, water_grit, handling, breeding, rearing, health,
                     predator, terrain, kit, signoff, markup, photo_key,
                     readiness_percent, version, created_at, updated_at)
                 SELECT ?, user_id, CONCAT(title, " (copy)"), species, bird_count, age, notes, priority, status,
                     housing, fencing, feed, water_grit, handling, breeding, rearing, health,
                     predator, terrain, kit, signoff, markup, photo_key,
                     readiness_percent, 1, ?, ?
                 FROM flocks WHERE id = ?',
                [$newId, $now, $now, $flockId],
            );

            // подпись не копируется — приёмка периода относится к исходному стаду
            $db->run(
                'UPDATE flocks SET signoff = ? WHERE id = ?',
                [$this->encode(FlockSections::defaults('signoff')), $newId],
            );

            // коллекции копируются с новыми id
            foreach ($db->fetchAll('SELECT * FROM bird_records WHERE flock_id = ?', [$flockId]) as $bird) {
                $db->run(
                    'INSERT INTO bird_records (id, flock_id, bird_id, weight_kg, height_cm, note, recorded_at, created_at, updated_at)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
                    [Uuid::v4(), $newId, $bird['bird_id'], $bird['weight_kg'], $bird['height_cm'],
                     $bird['note'], $bird['recorded_at'], $now, $now],
                );
            }
            foreach ($db->fetchAll('SELECT * FROM reminders WHERE flock_id = ?', [$flockId]) as $reminder) {
                $db->run(
                    'INSERT INTO reminders (id, flock_id, kind, title, hour, minute, enabled, created_at, updated_at)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
                    [Uuid::v4(), $newId, $reminder['kind'], $reminder['title'], $reminder['hour'],
                     $reminder['minute'], $reminder['enabled'], $now, $now],
                );
            }
            foreach ($db->fetchAll('SELECT * FROM layout_items WHERE flock_id = ?', [$flockId]) as $item) {
                $db->run(
                    'INSERT INTO layout_items (id, flock_id, kind, x, y, created_at, updated_at)
                     VALUES (?, ?, ?, ?, ?, ?, ?)',
                    [Uuid::v4(), $newId, $item['kind'], $item['x'], $item['y'], $now, $now],
                );
            }

            return $this->findFull($userId, $newId);
        });
    }

    public function softDelete(string $userId, string $flockId): void
    {
        $stmt = $this->db->run(
            'UPDATE flocks SET deleted_at = ?, updated_at = ? WHERE id = ? AND user_id = ? AND deleted_at IS NULL',
            [Clock::sql(), Clock::sql(), $flockId, $userId],
        );

        if ($stmt->rowCount() === 0) {
            throw ApiException::notFound('Flock not found.');
        }
    }

    public function setPhotoKey(string $userId, string $flockId, ?string $key): void
    {
        $this->db->run(
            'UPDATE flocks SET photo_key = ?, version = version + 1, updated_at = ? WHERE id = ? AND user_id = ?',
            [$key, Clock::sql(), $flockId, $userId],
        );
    }

    /** Пересчёт после изменения коллекций (записи о птицах не влияют, но кит — да). */
    public function touch(string $flockId): void
    {
        $this->db->run(
            'UPDATE flocks SET version = version + 1, updated_at = ? WHERE id = ?',
            [Clock::sql(), $flockId],
        );
    }

    // -- блокировка и версии --------------------------------------------------

    /**
     * SELECT … FOR UPDATE + проверка If-Match.
     *
     * @return array<string,mixed>
     */
    private function lockRow(Database $db, string $userId, string $flockId, ?string $expectedVersion): array
    {
        $row = $db->fetchOne(
            'SELECT * FROM flocks WHERE id = ? AND user_id = ? AND deleted_at IS NULL FOR UPDATE',
            [$flockId, $userId],
        );

        if ($row === null) {
            throw ApiException::notFound('Flock not found.');
        }

        $currentVersion = (int) $row['version'];

        if ($expectedVersion !== null && $expectedVersion !== '*' && (int) $expectedVersion !== $currentVersion) {
            throw ApiException::preconditionFailed($currentVersion);
        }

        return $row;
    }

    // -- представление --------------------------------------------------------

    /**
     * @param array<string,mixed> $row
     * @return array<string,mixed>
     */
    private function presentSummary(array $row): array
    {
        return [
            'id'               => (string) $row['id'],
            'title'            => (string) $row['title'],
            'species'          => (string) $row['species'],
            'count'            => (int) $row['bird_count'],
            'age'              => (string) $row['age'],
            'priority'         => (string) $row['priority'],
            'status'           => (string) $row['status'],
            'readinessPercent' => (int) $row['readiness_percent'],
            'photoUrl'         => $this->photoUrl($row),
            'version'          => (int) $row['version'],
            'createdDate'      => Clock::isoFromSql((string) $row['created_at']),
            'updatedAt'        => Clock::isoFromSql((string) $row['updated_at']),
        ];
    }

    /**
     * @param array<string,mixed> $row
     * @return array<string,mixed>
     */
    public function presentFull(array $row): array
    {
        $flockId = (string) $row['id'];

        $result = $this->presentSummary($row);
        $result['notes'] = (string) ($row['notes'] ?? '');

        foreach (FlockSections::COLUMNS as $section => $column) {
            $result[$section] = $this->decode($row[$column] ?? null) ?: FlockSections::defaults($section);
        }

        $result['birds'] = array_map(
            static fn (array $r): array => BirdRecordRepository::present($r),
            $this->db->fetchAll(
                'SELECT * FROM bird_records WHERE flock_id = ? ORDER BY recorded_at DESC, id DESC',
                [$flockId],
            ),
        );

        $result['reminders'] = array_map(
            static fn (array $r): array => ReminderRepository::present($r),
            $this->db->fetchAll('SELECT * FROM reminders WHERE flock_id = ? ORDER BY hour, minute', [$flockId]),
        );

        $result['layout'] = array_map(
            static fn (array $r): array => LayoutRepository::present($r),
            $this->db->fetchAll('SELECT * FROM layout_items WHERE flock_id = ? ORDER BY created_at', [$flockId]),
        );

        $preset = $this->presets->find(Species::from((string) $row['species']));
        $result['readiness'] = Engines::readiness($this->toEngineInput($row), $preset);

        return $result;
    }

    /**
     * Строка БД → вход для движков (camelCase, как в JSON).
     *
     * @param array<string,mixed> $row
     * @return array<string,mixed>
     */
    public function toEngineInput(array $row): array
    {
        $flock = [
            'species' => (string) $row['species'],
            'count'   => (int) $row['bird_count'],
        ];

        foreach (FlockSections::COLUMNS as $section => $column) {
            $flock[$section] = $this->decode($row[$column] ?? null) ?: FlockSections::defaults($section);
        }

        return $flock;
    }

    /** @param array<string,mixed> $row */
    private function photoUrl(array $row): ?string
    {
        $key = $row['photo_key'] ?? null;

        return is_string($key) && $key !== ''
            ? '/v1/flocks/' . $row['id'] . '/photo'
            : null;
    }

    // -- JSON-колонки ---------------------------------------------------------

    /** @param array<string,mixed> $value */
    private function encode(array $value): string
    {
        return json_encode($value, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
    }

    /** @return array<string,mixed> */
    private function decode(mixed $value): array
    {
        if (!is_string($value) || $value === '') {
            return [];
        }

        $decoded = json_decode($value, true);

        return is_array($decoded) ? $decoded : [];
    }

    // -- курсор ---------------------------------------------------------------

    private function encodeCursor(string $updatedAt, string $id): string
    {
        return rtrim(strtr(base64_encode($updatedAt . '|' . $id), '+/', '-_'), '=');
    }

    /** @return array{updatedAt:string,id:string} */
    private function decodeCursor(string $cursor): array
    {
        $padded = strtr($cursor, '-_', '+/');
        $remainder = strlen($padded) % 4;
        if ($remainder !== 0) {
            $padded .= str_repeat('=', 4 - $remainder);
        }

        $decoded = base64_decode($padded, true);
        if ($decoded === false || !str_contains($decoded, '|')) {
            throw ApiException::badRequest('Invalid cursor.');
        }

        [$updatedAt, $id] = explode('|', $decoded, 2);
        if (!Uuid::isValid($id)) {
            throw ApiException::badRequest('Invalid cursor.');
        }

        return ['updatedAt' => $updatedAt, 'id' => $id];
    }
}
