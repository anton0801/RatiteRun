<?php

declare(strict_types=1);

namespace RatiteRun\Api\Repository;

use RatiteRun\Api\Core\ApiException;
use RatiteRun\Api\Core\Clock;
use RatiteRun\Api\Core\Database;
use RatiteRun\Api\Core\Uuid;
use RatiteRun\Api\Core\Validator;

final class SupportRepository
{
    public function __construct(private readonly Database $db)
    {
    }

    /**
     * Проверяет и сохраняет обращение.
     *
     * @param array<string,mixed> $input
     * @return array{id:string,createdAt:string}
     */
    public function create(
        array $input,
        string $source,
        ?string $userId,
        ?string $ip,
        ?string $userAgent,
    ): array {
        $v = new Validator($input);

        $name    = $v->requiredString('name', 120);
        $email   = $v->requiredString('email', 255);
        $subject = $v->requiredString('subject', 200);
        $message = $v->requiredString('message', 5000);

        $appVersion = $v->string('appVersion', 32);
        $deviceInfo = $v->string('deviceInfo', 191);

        if ($email !== null && filter_var($email, FILTER_VALIDATE_EMAIL) === false) {
            $v->addError('email', 'Must be a valid email address.');
        }
        if ($message !== null && mb_strlen($message) < 10) {
            $v->addError('message', 'Please describe the problem in at least 10 characters.');
        }

        $v->validate();

        $id = Uuid::v4();
        $now = Clock::now();

        $this->db->run(
            'INSERT INTO support_requests
                (id, user_id, name, email, subject, message, source,
                 app_version, device_info, ip, user_agent, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
                $id,
                $userId,
                $name,
                $email,
                $subject,
                $message,
                $source,
                ($appVersion === '' ? null : $appVersion),
                ($deviceInfo === '' ? null : $deviceInfo),
                $ip === null ? null : (@inet_pton($ip) ?: null),
                $userAgent,
                Clock::sql($now),
            ],
        );

        return ['id' => $id, 'createdAt' => Clock::iso($now)];
    }

    /**
     * Грубая защита от заваливания формы: не больше N обращений с одного
     * адреса за окно. Работает поверх общего rate limit.
     */
    public function assertNotFlooding(?string $ip, int $maxPerHour = 5): void
    {
        if ($ip === null) {
            return;
        }

        $packed = @inet_pton($ip);
        if ($packed === false) {
            return;
        }

        $count = (int) $this->db->fetchValue(
            'SELECT COUNT(*) FROM support_requests WHERE ip = ? AND created_at > ?',
            [$packed, Clock::sql(Clock::now()->sub(new \DateInterval('PT1H')))],
        );

        if ($count >= $maxPerHour) {
            throw ApiException::tooManyRequests(3600);
        }
    }

    /** IP-адреса живут 90 дней — см. политику конфиденциальности. */
    public function purgeOldIpAddresses(): int
    {
        $stmt = $this->db->run(
            'UPDATE support_requests SET ip = NULL, user_agent = NULL
             WHERE ip IS NOT NULL AND created_at < ?',
            [Clock::sql(Clock::now()->sub(new \DateInterval('P90D')))],
        );

        return $stmt->rowCount();
    }
}
