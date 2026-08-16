<?php

declare(strict_types=1);

namespace RatiteRun\Api\Domain;

use RatiteRun\Api\Core\Clock;
use RatiteRun\Api\Core\Validator;

/**
 * Декларативная схема секций Flock — зеркало вложенных структур Models.swift.
 *
 * Одна таблица правды: и дефолты при создании стада, и валидация PUT-запросов
 * на /flocks/{id}/{section} берутся отсюда, поэтому разъехаться не могут.
 */
final class FlockSections
{
    public const TERRAIN_TYPES = ['flat', 'sloped', 'sandy', 'grassland', 'mixed'];
    public const DIET_TYPES    = ['grazing', 'formulated', 'mixed'];

    /**
     * Имя секции => имя колонки в MySQL.
     *
     * @var array<string,string>
     */
    public const COLUMNS = [
        'housing'   => 'housing',
        'fencing'   => 'fencing',
        'feed'      => 'feed',
        'waterGrit' => 'water_grit',
        'handling'  => 'handling',
        'breeding'  => 'breeding',
        'rearing'   => 'rearing',
        'health'    => 'health',
        'predator'  => 'predator',
        'terrain'   => 'terrain',
        'kit'       => 'kit',
        'signoff'   => 'signoff',
        'markup'    => 'markup',
    ];

    /** Секции, которые клиент правит напрямую (kit считается сервером). */
    public const WRITABLE = [
        'housing', 'fencing', 'feed', 'waterGrit', 'handling',
        'breeding', 'rearing', 'health', 'predator', 'terrain',
        'signoff', 'markup',
    ];

    /** URL-сегмент => имя секции (water-grit → waterGrit). */
    public const SLUGS = [
        'housing'     => 'housing',
        'fencing'     => 'fencing',
        'feed'        => 'feed',
        'water-grit'  => 'waterGrit',
        'handling'    => 'handling',
        'breeding'    => 'breeding',
        'rearing'     => 'rearing',
        'health'      => 'health',
        'predator'    => 'predator',
        'terrain'     => 'terrain',
        'signoff'     => 'signoff',
        'markup'      => 'markup',
    ];

    /**
     * @return array<string,array<string,array<string,mixed>>>
     */
    public static function schema(): array
    {
        return [
            'housing' => [
                'spacePerBird' => ['type' => 'float', 'default' => 0.0,  'min' => 0, 'max' => 100000],
                'shelterArea'  => ['type' => 'float', 'default' => 0.0,  'min' => 0, 'max' => 100000],
                'paddockSize'  => ['type' => 'float', 'default' => 0.0,  'min' => 0, 'max' => 10000000],
                'terrain'      => ['type' => 'enum',  'default' => 'grassland', 'values' => self::TERRAIN_TYPES],
                'hasShelter'   => ['type' => 'bool',  'default' => false],
            ],
            'fencing' => [
                'height'           => ['type' => 'float',  'default' => 0.0, 'min' => 0, 'max' => 20],
                'strength'         => ['type' => 'int',    'default' => 3,   'min' => 1, 'max' => 5],
                'escapeRiskNote'   => ['type' => 'string', 'default' => '',  'maxLength' => 2000],
                'perimeterSecured' => ['type' => 'bool',   'default' => false],
            ],
            'feed' => [
                'dietType'     => ['type' => 'enum',   'default' => 'mixed', 'values' => self::DIET_TYPES],
                'grazingRatio' => ['type' => 'float',  'default' => 40.0, 'min' => 0, 'max' => 100],
                'proteinPct'   => ['type' => 'float',  'default' => 16.0, 'min' => 0, 'max' => 100],
                'scheduleNote' => ['type' => 'string', 'default' => 'Twice daily', 'maxLength' => 2000],
            ],
            'waterGrit' => [
                'waterProvided'    => ['type' => 'bool',   'default' => true],
                'gritProvided'     => ['type' => 'bool',   'default' => false],
                'gritGramsPerBird' => ['type' => 'float',  'default' => 0.0, 'min' => 0, 'max' => 100000],
                'mineralsProvided' => ['type' => 'bool',   'default' => false],
                'notes'            => ['type' => 'string', 'default' => '', 'maxLength' => 2000],
            ],
            'handling' => [
                'neverCorner'         => ['type' => 'bool',   'default' => true],
                'approachFromSide'    => ['type' => 'bool',   'default' => true],
                'useHood'             => ['type' => 'bool',   'default' => false],
                'trainedHandlersOnly' => ['type' => 'bool',   'default' => false],
                'restraintPlan'       => ['type' => 'string', 'default' => '', 'maxLength' => 4000],
            ],
            'breeding' => [
                'pairs'          => ['type' => 'int',    'default' => 0, 'min' => 0, 'max' => 100000],
                'largeEggs'      => ['type' => 'int',    'default' => 0, 'min' => 0, 'max' => 100000],
                'incubationNote' => ['type' => 'string', 'default' => '', 'maxLength' => 4000],
                'season'         => ['type' => 'string', 'default' => 'Spring', 'maxLength' => 120],
                'startDate'      => ['type' => 'date',   'default' => 'now'],
            ],
            'rearing' => [
                'chicks'           => ['type' => 'int',    'default' => 0, 'min' => 0, 'max' => 100000],
                'brooderReady'     => ['type' => 'bool',   'default' => false],
                'legIssuesFlagged' => ['type' => 'bool',   'default' => false],
                'chickDietNote'    => ['type' => 'string', 'default' => '', 'maxLength' => 4000],
            ],
            'health' => [
                'legJointScore' => ['type' => 'int',    'default' => 4, 'min' => 1, 'max' => 5],
                'ailmentsNote'  => ['type' => 'string', 'default' => '', 'maxLength' => 4000],
                'vetContact'    => ['type' => 'string', 'default' => '', 'maxLength' => 500],
                'lastCheck'     => ['type' => 'date',   'default' => 'now'],
            ],
            'predator' => [
                'fenceIntegrity' => ['type' => 'int',    'default' => 4, 'min' => 1, 'max' => 5],
                'predatorsSeen'  => ['type' => 'string', 'default' => '', 'maxLength' => 2000],
                'securityNote'   => ['type' => 'string', 'default' => '', 'maxLength' => 2000],
                'lastChecked'    => ['type' => 'date',   'default' => 'now'],
            ],
            'terrain' => [
                'dustBathing' => ['type' => 'bool',   'default' => false],
                'roomToRun'   => ['type' => 'bool',   'default' => true],
                'terrainNote' => ['type' => 'string', 'default' => '', 'maxLength' => 2000],
            ],
            'kit' => [
                'fenceMeters'   => ['type' => 'float',  'default' => 0.0, 'min' => 0, 'max' => 1000000],
                'feeders'       => ['type' => 'int',    'default' => 0,   'min' => 0, 'max' => 100000],
                'waterers'      => ['type' => 'int',    'default' => 0,   'min' => 0, 'max' => 100000],
                'gritKg'        => ['type' => 'float',  'default' => 0.0, 'min' => 0, 'max' => 1000000],
                'shelterM2'     => ['type' => 'float',  'default' => 0.0, 'min' => 0, 'max' => 1000000],
                'safetyKitNote' => ['type' => 'string', 'default' => 'Hood, panel board, gloves', 'maxLength' => 500],
            ],
            'signoff' => [
                'reviewer'         => ['type' => 'string',  'default' => '', 'maxLength' => 200],
                'signatureStrokes' => ['type' => 'strokes', 'default' => []],
                'date'             => ['type' => 'date',    'default' => 'now'],
                'approved'         => ['type' => 'bool',    'default' => false],
            ],
            'markup' => [
                'strokes' => ['type' => 'strokes', 'default' => []],
                'caption' => ['type' => 'string',  'default' => '', 'maxLength' => 500],
            ],
        ];
    }

    /**
     * Значения по умолчанию для секции — те же, что у Swift-структур.
     *
     * @return array<string,mixed>
     */
    public static function defaults(string $section): array
    {
        $fields = self::schema()[$section] ?? throw new \InvalidArgumentException("Unknown section: {$section}");

        $result = [];
        foreach ($fields as $name => $spec) {
            $default = $spec['default'];
            $result[$name] = ($spec['type'] === 'date' && $default === 'now')
                ? Clock::iso()
                : $default;
        }

        return $result;
    }

    /**
     * Валидирует и нормализует присланную секцию.
     * Отсутствующие поля берутся из $current (PUT работает как частичное слияние).
     *
     * @param array<string,mixed> $input
     * @param array<string,mixed> $current
     * @return array<string,mixed>
     */
    public static function validate(string $section, array $input, array $current = []): array
    {
        $fields = self::schema()[$section] ?? throw new \InvalidArgumentException("Unknown section: {$section}");

        $v = new Validator($input);
        $base = $current === [] ? self::defaults($section) : $current;
        $result = [];

        foreach ($fields as $name => $spec) {
            $fallback = $base[$name] ?? (($spec['type'] === 'date' && $spec['default'] === 'now')
                ? Clock::iso()
                : $spec['default']);

            if (!$v->has($name)) {
                $result[$name] = $fallback;
                continue;
            }

            $value = match ($spec['type']) {
                'float'   => $v->float($name, (float) $spec['min'], (float) $spec['max']),
                'int'     => $v->int($name, (int) $spec['min'], (int) $spec['max']),
                'bool'    => $v->bool($name),
                'string'  => $v->string($name, (int) ($spec['maxLength'] ?? 255)),
                'enum'    => $v->enum($name, $spec['values']),
                'date'    => ($d = $v->isoDate($name)) === null ? null : Clock::iso($d),
                'strokes' => $v->strokes($name),
                default   => throw new \LogicException("Unhandled field type: {$spec['type']}"),
            };

            $result[$name] = $value ?? $fallback;
        }

        $v->validate();

        return $result;
    }

    /**
     * Полный набор дефолтных секций для нового стада.
     *
     * @return array<string,array<string,mixed>>
     */
    public static function allDefaults(): array
    {
        $result = [];
        foreach (array_keys(self::COLUMNS) as $section) {
            $result[$section] = self::defaults($section);
        }

        return $result;
    }
}
