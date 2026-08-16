<?php

declare(strict_types=1);

namespace RatiteRun\Api\Repository;

use RatiteRun\Api\Core\ApiException;
use RatiteRun\Api\Core\Clock;
use RatiteRun\Api\Core\Config;
use RatiteRun\Api\Core\Database;
use RatiteRun\Api\Core\Jwt;
use RatiteRun\Api\Core\Uuid;

/**
 * Выдача пар access/refresh. В БД лежит только SHA-256 refresh-токена.
 */
final class TokenRepository
{
    public function __construct(private readonly Database $db)
    {
    }

    /**
     * @return array{accessToken:string,refreshToken:string,tokenType:string,expiresIn:int}
     */
    public function issue(string $userId): array
    {
        $accessTtl = Config::int('JWT_ACCESS_TTL', 3600);
        $refreshTtlDays = Config::int('REFRESH_TTL_DAYS', 90);

        $access = Jwt::encode(['sub' => $userId], Config::require('JWT_SECRET'), $accessTtl);

        $refresh = bin2hex(random_bytes(32));
        $expiresAt = Clock::now()->add(new \DateInterval('P' . $refreshTtlDays . 'D'));

        $this->db->run(
            'INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at, created_at) VALUES (?, ?, ?, ?, ?)',
            [Uuid::v4(), $userId, hash('sha256', $refresh), Clock::sql($expiresAt), Clock::sql()],
        );

        return [
            'accessToken'  => $access,
            'refreshToken' => $refresh,
            'tokenType'    => 'Bearer',
            'expiresIn'    => $accessTtl,
        ];
    }

    /**
     * Обмен refresh-токена. Старый отзывается — ротация на каждое обновление.
     *
     * @return array{accessToken:string,refreshToken:string,tokenType:string,expiresIn:int,userId:string}
     */
    public function rotate(string $refreshToken): array
    {
        $hash = hash('sha256', $refreshToken);

        $row = $this->db->fetchOne(
            'SELECT * FROM refresh_tokens WHERE token_hash = ?',
            [$hash],
        );

        if ($row === null) {
            throw ApiException::unauthorized('Refresh token is not recognised.');
        }
        if ($row['revoked_at'] !== null) {
            // Повторное использование отозванного токена — возможная кража.
            // Гасим всю цепочку пользователя.
            $this->revokeAllForUser((string) $row['user_id']);
            throw ApiException::unauthorized('Refresh token has already been used.');
        }

        $expiresAt = Clock::isoFromSql(is_string($row['expires_at']) ? $row['expires_at'] : null);
        if ($expiresAt === null || new \DateTimeImmutable($expiresAt) <= Clock::now()) {
            throw ApiException::unauthorized('Refresh token has expired.');
        }

        $userId = (string) $row['user_id'];

        $this->db->run(
            'UPDATE refresh_tokens SET revoked_at = ? WHERE id = ?',
            [Clock::sql(), $row['id']],
        );

        return $this->issue($userId) + ['userId' => $userId];
    }

    public function revoke(string $refreshToken): void
    {
        $this->db->run(
            'UPDATE refresh_tokens SET revoked_at = ? WHERE token_hash = ? AND revoked_at IS NULL',
            [Clock::sql(), hash('sha256', $refreshToken)],
        );
    }

    public function revokeAllForUser(string $userId): void
    {
        $this->db->run(
            'UPDATE refresh_tokens SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL',
            [Clock::sql(), $userId],
        );
    }

    /** Чистка просроченных — вызывается из bin/cleanup.php по крону. */
    public function purgeExpired(): int
    {
        $stmt = $this->db->run(
            'DELETE FROM refresh_tokens WHERE expires_at < ? OR (revoked_at IS NOT NULL AND revoked_at < ?)',
            [Clock::sql(), Clock::sql(Clock::now()->sub(new \DateInterval('P30D')))],
        );

        return $stmt->rowCount();
    }
}
