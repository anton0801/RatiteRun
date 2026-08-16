<?php

declare(strict_types=1);

namespace RatiteRun\Api\Service;

/**
 * Минимальный писатель PDF на базовых шрифтах Helvetica — без внешних библиотек.
 *
 * Достаточен ровно для того, что рисует ReportGenerator.swift: текст,
 * переносы по словам, горизонтальные линейки, цвет, разбивка на страницы.
 * Картинки и произвольные шрифты не поддерживаются — они здесь и не нужны.
 */
final class PdfWriter
{
    private const PAGE_WIDTH  = 612.0;
    private const PAGE_HEIGHT = 792.0;
    private const MARGIN      = 48.0;

    /** @var list<string> содержимое страниц */
    private array $pages = [];
    private string $current = '';
    private float $y;

    /** @var array<int,int> ширины Helvetica для кодов WinAnsi */
    private static array $widthsRegular = [];
    /** @var array<int,int> ширины Helvetica-Bold */
    private static array $widthsBold = [];

    public function __construct()
    {
        self::initWidths();
        $this->y = self::MARGIN;
    }

    // -- рисование ------------------------------------------------------------

    public function text(
        string $value,
        float $size = 12,
        bool $bold = false,
        string $hexColor = '#1A1A1A',
        float $indent = 0,
        float $spacingAfter = 8,
    ): void {
        $maxWidth = self::PAGE_WIDTH - self::MARGIN * 2 - $indent;
        $lineHeight = $size * 1.28;

        foreach ($this->wrap($value, $size, $bold, $maxWidth) as $line) {
            $this->ensureSpace($lineHeight);

            $font = $bold ? '/F2' : '/F1';
            $x = self::MARGIN + $indent;
            $baseline = self::PAGE_HEIGHT - $this->y - $size;

            $this->current .= sprintf(
                "%s\nBT %s %.2f Tf 1 0 0 1 %.2f %.2f Tm (%s) Tj ET\n",
                $this->colorOp($hexColor),
                $font,
                $size,
                $x,
                $baseline,
                $this->escape($line),
            );

            $this->y += $lineHeight;
        }

        $this->y += $spacingAfter;
    }

    public function rule(string $hexColor = '#D8D2C6'): void
    {
        $this->ensureSpace(16);

        [$r, $g, $b] = $this->rgb($hexColor);
        $yPos = self::PAGE_HEIGHT - $this->y;

        $this->current .= sprintf(
            "%.3f %.3f %.3f RG 1 w %.2f %.2f m %.2f %.2f l S\n",
            $r,
            $g,
            $b,
            self::MARGIN,
            $yPos,
            self::PAGE_WIDTH - self::MARGIN,
            $yPos,
        );

        $this->y += 14;
    }

    public function space(float $points): void
    {
        $this->y += $points;
    }

    // -- страницы -------------------------------------------------------------

    private function ensureSpace(float $needed): void
    {
        if ($this->y + $needed > self::PAGE_HEIGHT - 60) {
            $this->breakPage();
        }
    }

    private function breakPage(): void
    {
        $this->pages[] = $this->current;
        $this->current = '';
        $this->y = self::MARGIN;
    }

    // -- перенос по словам ----------------------------------------------------

    /** @return list<string> */
    private function wrap(string $value, float $size, bool $bold, float $maxWidth): array
    {
        $value = $this->toWinAnsi($value);
        $lines = [];

        foreach (explode("\n", $value) as $paragraph) {
            $words = preg_split('/\s+/', trim($paragraph)) ?: [];
            if ($words === [''] || $words === []) {
                $lines[] = '';
                continue;
            }

            $line = '';
            foreach ($words as $word) {
                $candidate = $line === '' ? $word : $line . ' ' . $word;

                if ($this->stringWidth($candidate, $size, $bold) <= $maxWidth) {
                    $line = $candidate;
                    continue;
                }

                if ($line !== '') {
                    $lines[] = $line;
                }

                // слово длиннее строки — режем принудительно
                while ($this->stringWidth($word, $size, $bold) > $maxWidth && strlen($word) > 1) {
                    $cut = 1;
                    while ($cut < strlen($word)
                        && $this->stringWidth(substr($word, 0, $cut + 1), $size, $bold) <= $maxWidth
                    ) {
                        $cut++;
                    }
                    $lines[] = substr($word, 0, $cut);
                    $word = substr($word, $cut);
                }

                $line = $word;
            }

            if ($line !== '') {
                $lines[] = $line;
            }
        }

        return $lines;
    }

    private function stringWidth(string $text, float $size, bool $bold): float
    {
        $widths = $bold ? self::$widthsBold : self::$widthsRegular;
        $total = 0;

        for ($i = 0, $len = strlen($text); $i < $len; $i++) {
            $total += $widths[ord($text[$i])] ?? 556;
        }

        return $total / 1000 * $size;
    }

    // -- кодировки и экранирование -------------------------------------------

    /** UTF-8 → WinAnsi (CP1252). Непереводимое транслитерируется. */
    private function toWinAnsi(string $value): string
    {
        // символы, которых нет в CP1252, но которые есть в текстах движков
        $value = strtr($value, [
            '≥' => '>=',
            '≤' => '<=',
            '≈' => '~',
        ]);

        $converted = @iconv('UTF-8', 'CP1252//TRANSLIT', $value);

        return $converted === false ? preg_replace('/[^\x20-\x7E]/', '?', $value) ?? '' : $converted;
    }

    private function escape(string $value): string
    {
        return str_replace(['\\', '(', ')', "\r"], ['\\\\', '\\(', '\\)', ''], $value);
    }

    /** @return array{float,float,float} */
    private function rgb(string $hex): array
    {
        $hex = ltrim($hex, '#');
        if (strlen($hex) !== 6) {
            return [0.1, 0.1, 0.1];
        }

        return [
            hexdec(substr($hex, 0, 2)) / 255,
            hexdec(substr($hex, 2, 2)) / 255,
            hexdec(substr($hex, 4, 2)) / 255,
        ];
    }

    private function colorOp(string $hex): string
    {
        [$r, $g, $b] = $this->rgb($hex);

        return sprintf('%.3f %.3f %.3f rg', $r, $g, $b);
    }

    // -- сборка файла ---------------------------------------------------------

    public function output(): string
    {
        if ($this->current !== '' || $this->pages === []) {
            $this->pages[] = $this->current;
        }

        $pageCount = count($this->pages);

        $objects = [];
        // 1: Catalog, 2: Pages, 3: F1, 4: F2, далее пары Page/Contents
        $objects[1] = "<< /Type /Catalog /Pages 2 0 R >>";

        $kids = [];
        for ($i = 0; $i < $pageCount; $i++) {
            $kids[] = (5 + $i * 2) . ' 0 R';
        }
        $objects[2] = sprintf(
            "<< /Type /Pages /Count %d /Kids [%s] >>",
            $pageCount,
            implode(' ', $kids),
        );

        $objects[3] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>";
        $objects[4] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>";

        foreach ($this->pages as $i => $content) {
            $pageObj = 5 + $i * 2;
            $contentObj = $pageObj + 1;

            $objects[$pageObj] = sprintf(
                "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %.0f %.0f] "
                . "/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents %d 0 R >>",
                self::PAGE_WIDTH,
                self::PAGE_HEIGHT,
                $contentObj,
            );

            $objects[$contentObj] = sprintf(
                "<< /Length %d >>\nstream\n%s\nendstream",
                strlen($content),
                $content,
            );
        }

        $pdf = "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n";
        $offsets = [];

        ksort($objects);
        foreach ($objects as $number => $body) {
            $offsets[$number] = strlen($pdf);
            $pdf .= "{$number} 0 obj\n{$body}\nendobj\n";
        }

        $xrefOffset = strlen($pdf);
        $maxObj = max(array_keys($objects));

        $pdf .= "xref\n0 " . ($maxObj + 1) . "\n";
        $pdf .= "0000000000 65535 f \n";
        for ($i = 1; $i <= $maxObj; $i++) {
            $pdf .= sprintf("%010d 00000 n \n", $offsets[$i] ?? 0);
        }

        $pdf .= sprintf(
            "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF",
            $maxObj + 1,
            $xrefOffset,
        );

        return $pdf;
    }

    // -- метрики шрифтов ------------------------------------------------------

    private static function initWidths(): void
    {
        if (self::$widthsRegular !== []) {
            return;
        }

        // ширины Helvetica и Helvetica-Bold для ASCII 32..126 (единицы 1/1000 em)
        $regular = [
            278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278,
            556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556,
            1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778,
            667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556,
            333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556,
            556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584,
        ];

        $bold = [
            278, 333, 474, 556, 556, 889, 722, 238, 333, 333, 389, 584, 278, 333, 278, 278,
            556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 333, 333, 584, 584, 584, 611,
            975, 722, 722, 722, 722, 667, 611, 778, 722, 278, 556, 722, 611, 833, 722, 778,
            667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 333, 278, 333, 584, 556,
            333, 556, 611, 556, 611, 556, 333, 611, 611, 278, 278, 556, 278, 889, 611, 611,
            611, 611, 389, 556, 333, 611, 556, 778, 556, 556, 500, 389, 280, 389, 584,
        ];

        foreach ($regular as $i => $width) {
            self::$widthsRegular[32 + $i] = $width;
        }
        foreach ($bold as $i => $width) {
            self::$widthsBold[32 + $i] = $width;
        }
    }
}
