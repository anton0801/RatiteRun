<?php

declare(strict_types=1);

namespace RatiteRun\Api\Controller;

use RatiteRun\Api\Core\Clock;
use RatiteRun\Api\Core\Request;
use RatiteRun\Api\Core\Response;

/**
 * Полный экспорт данных пользователя — серверный аналог
 * ReportGenerator.exportJSON и основа для «Backup & Data» в настройках.
 */
final class ExportController extends Controller
{
    /** GET /v1/export */
    public function export(Request $request): Response
    {
        $userId = $this->userId($request);
        $this->c->rateLimiter()->hit('export:' . $userId, 10, 3600);

        $rows = $this->c->db()->fetchAll(
            'SELECT * FROM flocks WHERE user_id = ? AND deleted_at IS NULL ORDER BY created_at',
            [$userId],
        );

        $flocks = array_map(
            fn (array $row): array => $this->c->flocks()->presentFull($row),
            $rows,
        );

        return Response::json([
            'schemaVersion' => 1,
            'exportedAt'    => Clock::iso(),
            'flockCount'    => count($flocks),
            'flocks'        => $flocks,
        ])->withHeader('Content-Disposition', 'attachment; filename="ratiterun-backup.json"');
    }

    /** GET /v1/health — проверка живости для мониторинга и деплоя. */
    public function health(Request $request): Response
    {
        $dbOk = true;
        try {
            $this->c->db()->fetchValue('SELECT 1');
        } catch (\Throwable) {
            $dbOk = false;
        }

        return Response::json([
            'status'   => $dbOk ? 'ok' : 'degraded',
            'database' => $dbOk,
            'time'     => Clock::iso(),
        ], $dbOk ? 200 : 503);
    }
}
