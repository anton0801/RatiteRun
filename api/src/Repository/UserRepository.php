<?php

declare(strict_types=1);

namespace RatiteRun\Api\Repository;

use RatiteRun\Api\Core\Clock;
use RatiteRun\Api\Core\Database;
use RatiteRun\Api\Core\Uuid;

final class UserRepository
{
    public function __construct(private readonly Database $db)
    {
    }

    /** @return array<string,mixed>|null */
    public function find(string $id): ?array
    {
        return $this->db->fetchOne(
            'SELECT * FROM users WHERE id = ? AND deleted_at IS NULL',
            [$id],
        );
    }

    /** @return array<string,mixed>|null */
    public function findByAppleSub(string $sub): ?array
    {
        return $this->db->fetchOne(
            'SELECT * FROM users WHERE apple_sub = ? AND deleted_at IS NULL',
            [$sub],
        );
    }

    /**
     * Анонимный пользователь, привязанный к устройству.
     * Повторный вызов с тем же deviceKey возвращает того же пользователя —
     * переустановка приложения не плодит аккаунты.
     *
     * @return array<string,mixed>
     */
    public function findOrCreateForDevice(string $deviceKey, ?string $platform, ?string $timezone, ?string $appVersion): array
    {
        $existing = $this->db->fetchOne(
            'SELECT u.* FROM devices d
             JOIN users u ON u.id = d.user_id
             WHERE d.device_key = ? AND u.deleted_at IS NULL',
            [$deviceKey],
        );

        if ($existing !== null) {
            $this->db->run(
                'UPDATE devices SET platform = COALESCE(?, platform), timezone = COALESCE(?, timezone),
                        app_version = COALESCE(?, app_version), updated_at = ?
                 WHERE device_key = ?',
                [$platform, $timezone, $appVersion, Clock::sql(), $deviceKey],
            );

            return $existing;
        }

        return $this->db->transaction(function (Database $db) use ($deviceKey, $platform, $timezone, $appVersion): array {
            $now = Clock::sql();
            $userId = Uuid::v4();

            $db->run(
                'INSERT INTO users (id, is_anonymous, created_at, updated_at) VALUES (?, 1, ?, ?)',
                [$userId, $now, $now],
            );
            $db->run(
                'INSERT INTO devices (id, user_id, device_key, platform, timezone, app_version, created_at, updated_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
                [Uuid::v4(), $userId, $deviceKey, $platform ?? 'ios', $timezone, $appVersion, $now, $now],
            );

            /** @var array<string,mixed> */
            return $db->fetchOne('SELECT * FROM users WHERE id = ?', [$userId]);
        });
    }

    /**
     * Привязывает Apple-идентичность к уже существующему анонимному аккаунту.
     * Если под этим Apple ID аккаунт уже есть — возвращает его (данные не сливаются,
     * клиент показывает выбор).
     *
     * @return array{user:array<string,mixed>,merged:bool}
     */
    public function linkApple(string $currentUserId, string $appleSub, ?string $email, ?string $displayName): array
    {
        $existing = $this->findByAppleSub($appleSub);

        if ($existing !== null && $existing['id'] !== $currentUserId) {
            return ['user' => $existing, 'merged' => false];
        }

        $this->db->run(
            'UPDATE users SET apple_sub = ?, email = COALESCE(?, email), display_name = COALESCE(?, display_name),
                    is_anonymous = 0, updated_at = ?
             WHERE id = ?',
            [$appleSub, $email, $displayName, Clock::sql(), $currentUserId],
        );

        /** @var array<string,mixed> $user */
        $user = $this->find($currentUserId);

        return ['user' => $user, 'merged' => true];
    }

    public function softDelete(string $userId): void
    {
        $now = Clock::sql();
        $this->db->transaction(function (Database $db) use ($userId, $now): void {
            $db->run('UPDATE flocks SET deleted_at = ? WHERE user_id = ? AND deleted_at IS NULL', [$now, $userId]);
            $db->run('UPDATE refresh_tokens SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL', [$now, $userId]);

            // Привязки к устройствам удаляются насовсем, а не помечаются.
            // Две причины. Во-первых, в них лежит APNs-токен — это личные
            // данные, и «удалить аккаунт» должно означать удалить и их.
            // Во-вторых, device_key уникален: если строку оставить, следующий
            // анонимный вход с этого же устройства не найдёт живого владельца,
            // попытается создать нового и упрётся в UNIQUE — приложение
            // навсегда потеряет возможность войти.
            $db->run('DELETE FROM devices WHERE user_id = ?', [$userId]);

            $db->run('UPDATE users SET deleted_at = ?, apple_sub = NULL, email = NULL, updated_at = ? WHERE id = ?', [$now, $now, $userId]);
        });
    }

    public function registerDevice(string $userId, string $deviceKey, ?string $apnsToken, ?string $platform, ?string $timezone, ?string $appVersion): string
    {
        $existingId = $this->db->fetchValue('SELECT id FROM devices WHERE device_key = ?', [$deviceKey]);
        $now = Clock::sql();

        if (is_string($existingId)) {
            $this->db->run(
                'UPDATE devices SET user_id = ?, apns_token = COALESCE(?, apns_token), platform = COALESCE(?, platform),
                        timezone = COALESCE(?, timezone), app_version = COALESCE(?, app_version), updated_at = ?
                 WHERE id = ?',
                [$userId, $apnsToken, $platform, $timezone, $appVersion, $now, $existingId],
            );

            return $existingId;
        }

        $id = Uuid::v4();
        $this->db->run(
            'INSERT INTO devices (id, user_id, device_key, platform, apns_token, timezone, app_version, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [$id, $userId, $deviceKey, $platform ?? 'ios', $apnsToken, $timezone, $appVersion, $now, $now],
        );

        return $id;
    }

    public function removeDevice(string $userId, string $deviceId): bool
    {
        $stmt = $this->db->run('DELETE FROM devices WHERE id = ? AND user_id = ?', [$deviceId, $userId]);

        return $stmt->rowCount() > 0;
    }

    /**
     * @param array<string,mixed> $row
     * @return array<string,mixed>
     */
    public static function present(array $row): array
    {
        return [
            'id'          => (string) $row['id'],
            'isAnonymous' => (bool) $row['is_anonymous'],
            'email'       => $row['email'] ?? null,
            'displayName' => $row['display_name'] ?? null,
            'createdAt'   => Clock::isoFromSql(is_string($row['created_at']) ? $row['created_at'] : null),
        ];
    }
}
