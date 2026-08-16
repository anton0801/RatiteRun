<?php

declare(strict_types=1);

namespace RatiteRun\Api\Domain;

use RatiteRun\Api\Core\Clock;

/**
 * Порт Engines.swift. Держать синхронно с клиентом — расхождение вердиктов
 * между приложением и отчётом пользователь заметит сразу.
 *
 * Все методы чистые: на вход — массив стада (camelCase, как в JSON API)
 * и норматив по виду, на выход — результат. Никаких обращений к БД.
 */
final class Engines
{
    // -- доступ к полям с безопасными значениями по умолчанию ----------------

    /** @param array<string,mixed> $flock */
    private static function section(array $flock, string $name): array
    {
        $value = $flock[$name] ?? null;

        return is_array($value) ? $value : [];
    }

    /** @param array<string,mixed> $section */
    private static function num(array $section, string $key, float $default = 0.0): float
    {
        $value = $section[$key] ?? null;

        return is_numeric($value) ? (float) $value : $default;
    }

    /** @param array<string,mixed> $section */
    private static function int(array $section, string $key, int $default = 0): int
    {
        $value = $section[$key] ?? null;

        return is_numeric($value) ? (int) $value : $default;
    }

    /** @param array<string,mixed> $section */
    private static function flag(array $section, string $key, bool $default = false): bool
    {
        $value = $section[$key] ?? null;

        return is_bool($value) ? $value : (is_numeric($value) ? (bool) (int) $value : $default);
    }

    /** @param array<string,mixed> $section */
    private static function str(array $section, string $key, string $default = ''): string
    {
        $value = $section[$key] ?? null;

        return is_string($value) ? $value : $default;
    }

    // -- Пространство ---------------------------------------------------------

    /**
     * @param array<string,mixed> $flock
     * @return array{perBird:float,requiredTotal:float,ratio:float,result:EngineResult}
     */
    public static function space(array $flock, SpeciesPreset $p): array
    {
        $count = max(1, self::int($flock, 'count', 1));
        $housing = self::section($flock, 'housing');
        $paddock = self::num($housing, 'paddockSize');

        $requiredTotal = $p->spacePerBirdM2 * $count;
        $perBird = $paddock / $count;
        $ratio = $requiredTotal > 0 ? $paddock / $requiredTotal : 0.0;

        if ($perBird >= $p->spacePerBirdM2) {
            $verdict = Verdict::Good;
            $headline = 'Ample space';
        } elseif ($perBird >= $p->minSpacePerBirdM2) {
            $verdict = Verdict::Watch;
            $headline = 'Adequate — near minimum';
        } else {
            $verdict = Verdict::Alert;
            $headline = 'Cramped for ratites';
        }

        $detail = sprintf(
            '%.0f m²/bird provided vs %.0f m² recommended (%.0f m² floor). Ratites run — big space matters.',
            $perBird,
            $p->spacePerBirdM2,
            $p->minSpacePerBirdM2,
        );

        $score = $p->spacePerBirdM2 > 0 ? min(1.0, max(0.0, $perBird / $p->spacePerBirdM2)) : 0.0;

        return [
            'perBird'       => $perBird,
            'requiredTotal' => $requiredTotal,
            'ratio'         => $ratio,
            'result'        => new EngineResult($verdict, $headline, $detail, $score),
        ];
    }

    // -- Ограждение -----------------------------------------------------------

    /** @param array<string,mixed> $flock */
    public static function fencing(array $flock, SpeciesPreset $p): EngineResult
    {
        $fencing = self::section($flock, 'fencing');
        $height = self::num($fencing, 'height');
        $strength = self::int($fencing, 'strength', 3);

        $verdict = Verdict::Good;
        $issues = [];

        if ($height < $p->minFenceHeightM) {
            $verdict = Verdict::Alert;
            $issues[] = sprintf('Too low — needs ≥ %.1f m', $p->recFenceHeightM);
        } elseif ($height < $p->recFenceHeightM) {
            $verdict = Verdict::Watch;
            $issues[] = sprintf('Below recommended %.1f m', $p->recFenceHeightM);
        }

        if ($strength < $p->recFenceStrength - 1) {
            $verdict = $verdict === Verdict::Alert ? Verdict::Alert : Verdict::Watch;
            $issues[] = 'Strengthen posts/mesh for this species';
        }

        if (!self::flag($fencing, 'perimeterSecured')) {
            $issues[] = 'Perimeter not confirmed secured';
            if ($verdict === Verdict::Good) {
                $verdict = Verdict::Watch;
            }
        }

        $headline = match ($verdict) {
            Verdict::Good  => 'Fence fit for species',
            Verdict::Watch => 'Fence needs attention',
            Verdict::Alert => 'Escape / injury risk',
        };

        $detail = $issues === []
            ? sprintf('%.1f m high, strength %d/5 — meets %s guidance.', $height, $strength, $p->species->label())
            : implode(' · ', $issues);

        $heightScore = $p->recFenceHeightM > 0 ? min(1.0, $height / $p->recFenceHeightM) : 0.0;
        $strengthScore = $strength / 5.0;
        $score = $heightScore * 0.65 + $strengthScore * 0.35;

        return new EngineResult($verdict, $headline, $detail, $score);
    }

    // -- Рацион ---------------------------------------------------------------

    /** @param array<string,mixed> $flock */
    public static function diet(array $flock, SpeciesPreset $p): EngineResult
    {
        $feed = self::section($flock, 'feed');
        $protein = self::num($feed, 'proteinPct', 16.0);
        $type = self::str($feed, 'dietType', 'mixed');
        $grazingRatio = self::num($feed, 'grazingRatio', 40.0);

        $verdict = Verdict::Good;
        $notes = [];

        $lower = $p->targetProteinPct - 4;
        $upper = $p->targetProteinPct + 6;

        if ($protein < $lower) {
            $verdict = Verdict::Alert;
            $notes[] = sprintf('Protein low (%.0f%% vs ~%.0f%% target)', $protein, $p->targetProteinPct);
        } elseif ($protein > $upper) {
            $verdict = Verdict::Watch;
            $notes[] = 'Protein high — risk of leg/growth issues';
        }

        if ($type === 'grazing' && $protein < $p->targetProteinPct) {
            $verdict = $verdict === Verdict::Alert ? Verdict::Alert : Verdict::Watch;
            $notes[] = 'Grazing alone rarely meets ratite protein — supplement';
        }

        $headline = match ($verdict) {
            Verdict::Good  => 'Ratite-appropriate diet',
            Verdict::Watch => 'Diet needs tuning',
            Verdict::Alert => 'Diet not meeting needs',
        };

        $detail = $notes === []
            ? sprintf(
                '%s diet at %.0f%% protein, %.0f%% grazing — suited to %s.',
                ucfirst($type),
                $protein,
                $grazingRatio,
                $p->species->label(),
            )
            : implode(' · ', $notes);

        $score = max(0.0, 1 - abs($protein - $p->targetProteinPct) / 12);

        return new EngineResult($verdict, $headline, $detail, $score);
    }

    // -- Вода и гравий --------------------------------------------------------

    /** @param array<string,mixed> $flock */
    public static function gritWater(array $flock, SpeciesPreset $p): EngineResult
    {
        $g = self::section($flock, 'waterGrit');
        $verdict = Verdict::Good;
        $notes = [];
        $score = 1.0;

        if (!self::flag($g, 'waterProvided', true)) {
            $verdict = Verdict::Alert;
            $notes[] = 'No clean water source set';
            $score -= 0.5;
        }

        $gritGrams = self::num($g, 'gritGramsPerBird');
        if (!self::flag($g, 'gritProvided')) {
            $verdict = $verdict === Verdict::Alert ? Verdict::Alert : Verdict::Watch;
            $notes[] = "No grit — gizzard can't grind feed";
            $score -= 0.35;
        } elseif ($gritGrams <= 0) {
            $verdict = $verdict === Verdict::Alert ? Verdict::Alert : Verdict::Watch;
            $notes[] = 'Grit amount not logged';
            $score -= 0.1;
        }

        if (!self::flag($g, 'mineralsProvided')) {
            if ($verdict === Verdict::Good) {
                $verdict = Verdict::Watch;
            }
            $notes[] = 'Minerals not supplied';
            $score -= 0.15;
        }

        $headline = match ($verdict) {
            Verdict::Good  => 'Water, grit & minerals set',
            Verdict::Watch => 'Digestion support incomplete',
            Verdict::Alert => 'Missing water or grit',
        };

        $detail = $notes === []
            ? sprintf('Grit %.0f g/bird provided — stones grind coarse feed in the gizzard.', $gritGrams)
            : implode(' · ', $notes);

        return new EngineResult($verdict, $headline, $detail, max(0.0, $score));
    }

    // -- Безопасность обращения ----------------------------------------------

    /**
     * @param array<string,mixed> $flock
     * @return array{score:int,result:EngineResult,rules:list<string>}
     */
    public static function handlingSafety(array $flock, SpeciesPreset $p): array
    {
        $h = self::section($flock, 'handling');
        $score = 100;

        // базовый риск от силы удара у вида
        $score -= ($p->kickRiskLevel - 1) * 6;

        if (!self::flag($h, 'neverCorner', true)) {
            $score -= 30;
        }
        if (!self::flag($h, 'approachFromSide', true)) {
            $score -= 15;
        }
        if (!self::flag($h, 'trainedHandlersOnly')) {
            $score -= 12;
        }
        if ($p->kickRiskLevel >= 4 && !self::flag($h, 'useHood')) {
            $score -= 8;
        }
        if (trim(self::str($h, 'restraintPlan')) === '') {
            $score -= 8;
        }

        $score = max(5, min(100, $score));

        $verdict = match (true) {
            $score >= 75 => Verdict::Good,
            $score >= 50 => Verdict::Watch,
            default      => Verdict::Alert,
        };

        $headline = match ($verdict) {
            Verdict::Good  => 'Handling protocols solid',
            Verdict::Watch => 'Tighten handling safety',
            Verdict::Alert => 'High handling risk',
        };

        $rules = [
            sprintf(
                'Kick risk for %s: %s — the forward kick is the danger.',
                $p->species->label(),
                $p->kickRiskLabel(),
            ),
            'Never corner the bird — always leave an escape route.',
            'Approach from the side, not head-on.',
        ];
        if ($p->kickRiskLevel >= 4) {
            $rules[] = 'Use a hood to calm before restraint.';
        }
        $rules[] = 'Only trained handlers should restrain.';

        $detail = sprintf(
            'Safety score %d/100 for %s. %s',
            $score,
            $p->species->label(),
            $verdict === Verdict::Good ? 'Protocols in place.' : 'Enable the safety rules below.',
        );

        return [
            'score'  => $score,
            'result' => new EngineResult($verdict, $headline, $detail, $score / 100),
            'rules'  => $rules,
        ];
    }

    // -- Разведение -----------------------------------------------------------

    /**
     * @param array<string,mixed> $flock
     * @return array{hatchDate:string,window:string,result:EngineResult}
     */
    public static function breeding(array $flock, SpeciesPreset $p): array
    {
        $b = self::section($flock, 'breeding');

        $startRaw = self::str($b, 'startDate');
        try {
            $start = $startRaw === ''
                ? Clock::now()
                : (new \DateTimeImmutable($startRaw))->setTimezone(new \DateTimeZone('UTC'));
        } catch (\Exception) {
            $start = Clock::now();
        }

        $hatch = $start->add(new \DateInterval('P' . $p->incubationDays . 'D'));
        $window = '±' . $p->hatchWindowDays . ' days';

        $pairs = self::int($b, 'pairs');
        $largeEggs = self::int($b, 'largeEggs');

        $verdict = $pairs > 0 ? Verdict::Good : Verdict::Watch;
        $headline = $pairs > 0 ? 'Breeding tracked' : 'No breeding pairs yet';
        $detail = sprintf(
            '%s eggs incubate ~%d days (egg ≈ %.0f g). %d pair(s), %d large egg(s) logged.',
            $p->species->label(),
            $p->incubationDays,
            $p->eggMassG,
            $pairs,
            $largeEggs,
        );

        return [
            'hatchDate' => Clock::iso($hatch),
            'window'    => $window,
            'result'    => new EngineResult($verdict, $headline, $detail, $pairs > 0 ? 1.0 : 0.5),
        ];
    }

    // -- Здоровье и ноги ------------------------------------------------------

    /** @param array<string,mixed> $flock */
    public static function healthLegs(array $flock, SpeciesPreset $p): EngineResult
    {
        $health = self::section($flock, 'health');
        $s = self::int($health, 'legJointScore', 4);

        $verdict = match (true) {
            $s >= 4 => Verdict::Good,
            $s >= 3 => Verdict::Watch,
            default => Verdict::Alert,
        };

        $notes = [];
        if ($p->legIssueRisk >= 4) {
            $notes[] = sprintf(
                '%s chicks are prone to leg/joint problems — watch footing & protein.',
                $p->species->label(),
            );
            if ($verdict === Verdict::Good) {
                $verdict = Verdict::Watch;
            }
        }

        $ailments = self::str($health, 'ailmentsNote');
        if ($ailments !== '') {
            $notes[] = 'Logged: ' . $ailments;
        }

        $headline = match ($verdict) {
            Verdict::Good  => 'Legs & joints healthy',
            Verdict::Watch => 'Monitor legs closely',
            Verdict::Alert => 'Leg/health concern — call vet',
        };

        $detail = $notes === []
            ? "Leg/joint score {$s}/5. Keep footing firm and diet balanced."
            : implode(' · ', $notes);

        return new EngineResult($verdict, $headline, $detail, $s / 5.0);
    }

    // -- Материалы ------------------------------------------------------------

    /**
     * @param array<string,mixed> $flock
     * @return array<string,mixed>
     */
    public static function materials(array $flock, SpeciesPreset $p): array
    {
        $count = max(1, self::int($flock, 'count', 1));
        $housing = self::section($flock, 'housing');

        $area = max(self::num($housing, 'paddockSize'), $p->spacePerBirdM2 * $count);
        $perimeter = 4 * sqrt($area);

        $feeders = max(1, (int) ceil($count / 4));
        $waterers = max(1, (int) ceil($count / 5));
        $gritKg = $count * 0.5;

        $shelterArea = self::num($housing, 'shelterArea');
        $shelter = $shelterArea > 0
            ? $shelterArea
            : $count * ($p->adultMassKg > 80 ? 4.0 : 2.5);

        return [
            'fenceMeters'   => round($perimeter),
            'feeders'       => $feeders,
            'waterers'      => $waterers,
            'gritKg'        => round($gritKg * 10) / 10,
            'shelterM2'     => round($shelter),
            'safetyKitNote' => $p->kickRiskLevel >= 4
                ? 'Hood, panel board, gloves, first-aid'
                : 'Panel board, gloves, first-aid',
        ];
    }

    // -- Смета ----------------------------------------------------------------

    /**
     * @param array<string,mixed> $kit
     * @return array<string,float>
     */
    public static function cost(
        array $kit,
        float $fenceRate = 35,
        float $shelterRate = 60,
        float $feederRate = 45,
        float $gritRate = 3,
        float $labourRate = 120,
    ): array {
        $fence = self::num($kit, 'fenceMeters') * $fenceRate;
        $shelter = self::num($kit, 'shelterM2') * $shelterRate;
        $feeders = (self::num($kit, 'feeders') + self::num($kit, 'waterers')) * $feederRate;
        $grit = self::num($kit, 'gritKg') * $gritRate;
        $labour = $labourRate * 2;

        return [
            'fence'   => round($fence, 2),
            'shelter' => round($shelter, 2),
            'feeders' => round($feeders, 2),
            'grit'    => round($grit, 2),
            'labour'  => round($labour, 2),
            'total'   => round($fence + $shelter + $feeders + $grit + $labour, 2),
        ];
    }

    // -- Итоговая готовность --------------------------------------------------

    /**
     * @param array<string,mixed> $flock
     * @return array{percent:int,band:string,parts:array<string,float>}
     */
    public static function readiness(array $flock, SpeciesPreset $p): array
    {
        $space     = self::space($flock, $p)['result']->score;
        $fence     = self::fencing($flock, $p)->score;
        $diet      = self::diet($flock, $p)->score;
        $gritWater = self::gritWater($flock, $p)->score;
        $safety    = self::handlingSafety($flock, $p)['result']->score;
        $health    = self::healthLegs($flock, $p)->score;

        $weighted = $space * 0.25
            + $fence * 0.20
            + $diet * 0.20
            + $gritWater * 0.10
            + $safety * 0.15
            + $health * 0.10;

        $percent = (int) round($weighted * 100);

        $band = match (true) {
            $percent >= 80 => 'Ready',
            $percent >= 55 => 'Getting there',
            $percent >= 35 => 'Needs work',
            default        => 'Not ready',
        };

        return [
            'percent' => $percent,
            'band'    => $band,
            'parts'   => [
                'space'     => round($space, 4),
                'fencing'   => round($fence, 4),
                'diet'      => round($diet, 4),
                'gritWater' => round($gritWater, 4),
                'safety'    => round($safety, 4),
                'health'    => round($health, 4),
            ],
        ];
    }

    /**
     * Полный набор вердиктов — используется в /evaluate и при генерации отчёта.
     *
     * @param array<string,mixed> $flock
     * @return array<string,mixed>
     */
    public static function evaluateAll(array $flock, SpeciesPreset $p): array
    {
        $space = self::space($flock, $p);
        $safety = self::handlingSafety($flock, $p);
        $breeding = self::breeding($flock, $p);
        $kit = self::materials($flock, $p);

        return [
            'readiness' => self::readiness($flock, $p),
            'space'     => $space['result']->toArray() + [
                'perBirdM2'       => round($space['perBird'], 2),
                'requiredTotalM2' => round($space['requiredTotal'], 2),
                'ratio'           => round($space['ratio'], 4),
            ],
            'fencing'   => self::fencing($flock, $p)->toArray(),
            'diet'      => self::diet($flock, $p)->toArray(),
            'gritWater' => self::gritWater($flock, $p)->toArray(),
            'safety'    => $safety['result']->toArray() + [
                'safetyScore' => $safety['score'],
                'rules'       => $safety['rules'],
            ],
            'health'    => self::healthLegs($flock, $p)->toArray(),
            'breeding'  => $breeding['result']->toArray() + [
                'hatchDate' => $breeding['hatchDate'],
                'window'    => $breeding['window'],
            ],
            'kit'       => $kit,
            'cost'      => self::cost($kit),
        ];
    }
}
