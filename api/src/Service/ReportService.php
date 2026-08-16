<?php

declare(strict_types=1);

namespace RatiteRun\Api\Service;

use RatiteRun\Api\Core\ApiException;
use RatiteRun\Api\Core\Clock;
use RatiteRun\Api\Domain\Engines;
use RatiteRun\Api\Domain\SpeciesPreset;

/**
 * Серверный отчёт. Разделы и формулировки те же, что в ReportGenerator.swift —
 * PDF из приложения и PDF по ссылке должны совпадать.
 */
final class ReportService
{
    public const SECTIONS = ['spaceFence', 'diet', 'safety', 'health', 'breeding'];

    // палитра из Theme.swift
    private const COLOR_ACCENT    = '#C27D18';
    private const COLOR_TEXT      = '#3A2C12';
    private const COLOR_SECONDARY = '#6E5A2C';
    private const COLOR_MUTED     = '#A89464';
    private const COLOR_GOOD      = '#5FA84A';
    private const COLOR_WATCH     = '#F5B400';
    private const COLOR_ALERT     = '#E5484D';
    private const COLOR_RULE      = '#E8D9BD';

    /**
     * @param array<string,mixed> $flock  агрегат в формате API
     * @param list<string>        $sections
     */
    public function render(
        array $flock,
        SpeciesPreset $preset,
        array $sections,
        string $currency,
        string $notes,
        string $disclaimer,
    ): string {
        $unknown = array_diff($sections, self::SECTIONS);
        if ($unknown !== []) {
            throw ApiException::validation([
                'sections' => ['Unknown section(s): ' . implode(', ', $unknown) . '.'],
            ]);
        }

        $e = Engines::evaluateAll($flock, $preset);
        $pdf = new PdfWriter();

        // -- шапка ------------------------------------------------------------

        $pdf->text('Ratite Run — Flock Report', 24, true, self::COLOR_ACCENT);
        $pdf->text((string) ($flock['title'] ?? 'Flock'), 16, true, self::COLOR_TEXT);
        $pdf->text(
            sprintf(
                '%s · %d birds · %s · %s',
                $preset->species->label(),
                (int) ($flock['count'] ?? 0),
                (string) ($flock['age'] ?? ''),
                gmdate('j M Y'),
            ),
            12,
            false,
            self::COLOR_SECONDARY,
        );
        $pdf->rule(self::COLOR_RULE);

        // -- готовность -------------------------------------------------------

        $readiness = $e['readiness'];
        $pdf->text(
            sprintf('Overall readiness: %d%% — %s', $readiness['percent'], $readiness['band']),
            15,
            true,
            $this->bandColor($readiness['percent']),
        );

        foreach ($readiness['parts'] as $label => $value) {
            $pdf->text(
                sprintf('  %-12s %s  %d%%', ucfirst($label), $this->bar($value), (int) round($value * 100)),
                10,
                false,
                self::COLOR_SECONDARY,
                spacingAfter: 2,
            );
        }
        $pdf->space(6);

        // -- разделы ----------------------------------------------------------

        if (in_array('spaceFence', $sections, true)) {
            $pdf->text('Space & Fencing', 16, true, self::COLOR_ACCENT);
            $pdf->text('• Space: ' . $e['space']['headline'] . '. ' . $e['space']['detail'], 12);
            $pdf->text('• Fencing: ' . $e['fencing']['headline'] . '. ' . $e['fencing']['detail'], 12);
            $pdf->rule(self::COLOR_RULE);
        }

        if (in_array('diet', $sections, true)) {
            $pdf->text('Diet & Grit', 16, true, self::COLOR_ACCENT);
            $pdf->text('• Diet: ' . $e['diet']['headline'] . '. ' . $e['diet']['detail'], 12);
            $pdf->text('• Grit/Water: ' . $e['gritWater']['headline'] . '. ' . $e['gritWater']['detail'], 12);
            $pdf->rule(self::COLOR_RULE);
        }

        if (in_array('safety', $sections, true)) {
            $pdf->text('Handling Safety', 16, true, self::COLOR_ACCENT);
            $pdf->text(
                sprintf('• %s — score %d/100', $e['safety']['headline'], $e['safety']['safetyScore']),
                12,
            );
            foreach ($e['safety']['rules'] as $rule) {
                $pdf->text('• ' . $rule, 11, false, self::COLOR_SECONDARY, spacingAfter: 4);
            }
            $pdf->rule(self::COLOR_RULE);
        }

        if (in_array('health', $sections, true)) {
            $pdf->text('Health & Legs', 16, true, self::COLOR_ACCENT);
            $pdf->text('• ' . $e['health']['headline'] . '. ' . $e['health']['detail'], 12);
            $pdf->rule(self::COLOR_RULE);
        }

        if (in_array('breeding', $sections, true)) {
            $pdf->text('Breeding & Eggs', 16, true, self::COLOR_ACCENT);
            $pdf->text('• ' . $e['breeding']['headline'] . '. ' . $e['breeding']['detail'], 12);
            $pdf->text(
                sprintf(
                    '• Expected hatch: %s (%s)',
                    gmdate('j M Y', strtotime((string) $e['breeding']['hatchDate'])),
                    $e['breeding']['window'],
                ),
                12,
            );
            $pdf->rule(self::COLOR_RULE);
        }

        // -- смета ------------------------------------------------------------

        $kit = $e['kit'];
        $cost = $e['cost'];

        $pdf->text('Estimated kit cost', 16, true, self::COLOR_ACCENT);
        $pdf->text(
            sprintf(
                '• Fence %.0f m · Shelter %.0f m² · %d feeders / %d waterers · Grit %.1f kg',
                $kit['fenceMeters'],
                $kit['shelterM2'],
                $kit['feeders'],
                $kit['waterers'],
                $kit['gritKg'],
            ),
            12,
        );
        $pdf->text(sprintf('• Total ~ %s%.0f', $currency, $cost['total']), 13, true, self::COLOR_GOOD);

        // -- записи о птицах --------------------------------------------------

        $birds = is_array($flock['birds'] ?? null) ? $flock['birds'] : [];
        if ($birds !== []) {
            $pdf->rule(self::COLOR_RULE);
            $pdf->text(sprintf('Bird records (%d)', count($birds)), 14, true, self::COLOR_TEXT);
            foreach (array_slice($birds, 0, 60) as $bird) {
                $pdf->text(
                    sprintf(
                        '• %s — %.0f kg · %.0f cm%s',
                        (string) ($bird['birdID'] ?? '?'),
                        (float) ($bird['weightKg'] ?? 0),
                        (float) ($bird['heightCm'] ?? 0),
                        ($bird['note'] ?? '') !== '' ? ' · ' . $bird['note'] : '',
                    ),
                    11,
                    false,
                    self::COLOR_SECONDARY,
                    spacingAfter: 3,
                );
            }
            if (count($birds) > 60) {
                $pdf->text(sprintf('… and %d more', count($birds) - 60), 10, false, self::COLOR_MUTED);
            }
        }

        // -- приёмка ----------------------------------------------------------

        $signoff = is_array($flock['signoff'] ?? null) ? $flock['signoff'] : [];
        if (($signoff['approved'] ?? false) === true) {
            $pdf->rule(self::COLOR_RULE);
            $pdf->text('Sign-off', 14, true, self::COLOR_TEXT);
            $pdf->text(
                sprintf(
                    'Approved by %s on %s.',
                    (string) ($signoff['reviewer'] ?? 'unnamed reviewer'),
                    gmdate('j M Y', strtotime((string) ($signoff['date'] ?? Clock::iso()))),
                ),
                12,
                false,
                self::COLOR_SECONDARY,
            );
        }

        // -- примечания и дисклеймер -----------------------------------------

        if (trim($notes) !== '') {
            $pdf->rule(self::COLOR_RULE);
            $pdf->text('Notes', 14, true, self::COLOR_TEXT);
            $pdf->text($notes, 12, false, self::COLOR_SECONDARY);
        }

        $pdf->rule(self::COLOR_RULE);
        $pdf->text($disclaimer, 10, false, self::COLOR_MUTED);

        return $pdf->output();
    }

    private function bandColor(int $percent): string
    {
        return match (true) {
            $percent >= 80 => self::COLOR_GOOD,
            $percent >= 55 => self::COLOR_ACCENT,
            $percent >= 35 => self::COLOR_WATCH,
            default        => self::COLOR_ALERT,
        };
    }

    /** Текстовая шкала — PdfWriter умеет только текст и линии. */
    private function bar(float $value): string
    {
        $filled = (int) round(max(0.0, min(1.0, $value)) * 20);

        return str_repeat('#', $filled) . str_repeat('.', 20 - $filled);
    }
}
