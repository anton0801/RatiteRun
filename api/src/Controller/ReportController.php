<?php

declare(strict_types=1);

namespace RatiteRun\Api\Controller;

use RatiteRun\Api\Core\ApiException;
use RatiteRun\Api\Core\Config;
use RatiteRun\Api\Core\Request;
use RatiteRun\Api\Core\Response;
use RatiteRun\Api\Core\Uuid;
use RatiteRun\Api\Core\Validator;
use RatiteRun\Api\Domain\Species;
use RatiteRun\Api\Service\ReportService;

final class ReportController extends Controller
{
    /**
     * POST /v1/flocks/{id}/reports
     *
     * PDF собирается синхронно — отчёт текстовый и укладывается в миллисекунды.
     * Если появятся тяжёлые отчёты, здесь меняется на очередь + 202.
     */
    public function store(Request $request): Response
    {
        $userId = $this->userId($request);
        $flockId = $this->flockId($request);

        $this->c->rateLimiter()->hit('reports:' . $userId, 60, 3600);

        $v = new Validator($request->json());
        $sections = $v->list('sections', 20);
        $notes = $v->string('notes', 4000);
        $currency = $v->string('currency', 8);
        $shareable = $v->bool('shareable');
        $v->validate();

        if ($sections !== null) {
            foreach ($sections as $section) {
                if (!is_string($section)) {
                    throw ApiException::validation(['sections' => ['Must be an array of strings.']]);
                }
            }
        }

        /** @var list<string> $selected */
        $selected = $sections === null ? ReportService::SECTIONS : array_values($sections);

        $row = $this->c->flocks()->requireRow($userId, $flockId);
        $flock = $this->c->flocks()->presentFull($row);
        $preset = $this->c->presets()->find(Species::from((string) $row['species']));

        $disclaimer = $this->c->presets()->content('disclaimer')
            ?? 'Figures are estimates for planning only; consult a specialist ratite vet for health decisions.';

        $pdf = $this->c->reportService()->render(
            $flock,
            $preset,
            $selected,
            ($currency === null || $currency === '') ? '£' : $currency,
            $notes ?? '',
            $disclaimer,
        );

        $pdfKey = $this->writePdf($flockId, $pdf);

        $report = $this->c->reports()->create(
            $userId,
            $flockId,
            $selected,
            $notes ?? '',
            ($currency === null || $currency === '') ? '£' : $currency,
            ['readiness' => $flock['readiness'], 'title' => $flock['title'], 'species' => $flock['species']],
            $pdfKey,
            $shareable === true,
        );

        $this->c->audit()->record($userId, $flockId, 'report.create', null, ['sections' => $selected], $request->clientIp());

        return Response::created($report, '/v1/reports/' . $report['id']);
    }

    /** GET /v1/flocks/{id}/reports */
    public function index(Request $request): Response
    {
        return Response::json([
            'data' => $this->c->reports()->listForFlock($this->userId($request), $this->flockId($request)),
        ]);
    }

    /** GET /v1/reports/{reportId} */
    public function show(Request $request): Response
    {
        $reportId = Uuid::requireValid($request->param('reportId'), 'report');

        return Response::json($this->c->reports()->find($this->userId($request), $reportId));
    }

    /** GET /v1/reports/{reportId}/pdf */
    public function pdf(Request $request): Response
    {
        $reportId = Uuid::requireValid($request->param('reportId'), 'report');
        $key = $this->c->reports()->pdfKey($this->userId($request), $reportId);

        return $this->servePdf($key, "ratiterun-report-{$reportId}.pdf");
    }

    /**
     * GET /v1/shared/reports/{token}
     *
     * Публичная ссылка на отчёт — ветеринар или инспектор открывает PDF
     * без аккаунта. Токен случайный, отчёт протухает по expires_at.
     */
    public function shared(Request $request): Response
    {
        $token = $request->param('token');
        if (preg_match('/^[0-9a-f]{32}$/', $token) !== 1) {
            throw ApiException::notFound('Report link is not valid.');
        }

        $row = $this->c->reports()->findByShareToken($token)
            ?? throw ApiException::notFound('Report link has expired or does not exist.');

        $key = $row['pdf_key'] ?? null;
        if (!is_string($key) || $key === '') {
            throw ApiException::notFound('Report PDF is not available.');
        }

        return $this->servePdf($key, 'ratiterun-report.pdf');
    }

    private function servePdf(string $key, string $filename): Response
    {
        $path = $this->storageRoot() . '/reports/' . $key;

        if (str_contains($key, '..') || !is_file($path)) {
            throw ApiException::notFound('Report PDF is not available.');
        }

        $data = file_get_contents($path);
        if ($data === false) {
            throw ApiException::internal('Could not read the report PDF.');
        }

        return Response::binary($data, 'application/pdf', [
            'Content-Disposition' => 'inline; filename="' . $filename . '"',
        ]);
    }

    private function writePdf(string $flockId, string $pdf): string
    {
        $dir = $this->storageRoot() . '/reports/' . $flockId;
        if (!is_dir($dir) && !mkdir($dir, 0775, true) && !is_dir($dir)) {
            throw ApiException::internal('Could not create report storage directory.');
        }

        $key = $flockId . '/' . Uuid::v4() . '.pdf';
        if (file_put_contents($this->storageRoot() . '/reports/' . $key, $pdf) === false) {
            throw ApiException::internal('Could not write the report PDF.');
        }

        return $key;
    }

    private function storageRoot(): string
    {
        return rtrim(Config::get('STORAGE_PATH', dirname(__DIR__, 2) . '/storage') ?? '', '/');
    }
}
