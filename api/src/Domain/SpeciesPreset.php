<?php

declare(strict_types=1);

namespace RatiteRun\Api\Domain;

/**
 * Справочные нормативы по виду. Зеркало SpeciesPreset из Presets.swift,
 * но источник — таблица species_presets, а не бинарник приложения.
 */
final readonly class SpeciesPreset
{
    public function __construct(
        public Species $species,
        public float $adultMassKg,
        public float $spacePerBirdM2,
        public float $minSpacePerBirdM2,
        public float $recFenceHeightM,
        public float $minFenceHeightM,
        public int $recFenceStrength,
        public int $incubationDays,
        public float $eggMassG,
        public int $kickRiskLevel,
        public float $targetProteinPct,
        public int $gritImportance,
        public int $legIssueRisk,
        public int $hatchWindowDays,
    ) {
    }

    /** @param array<string,mixed> $row */
    public static function fromRow(array $row): self
    {
        return new self(
            species:           Species::from((string) $row['species']),
            adultMassKg:       (float) $row['adult_mass_kg'],
            spacePerBirdM2:    (float) $row['space_per_bird_m2'],
            minSpacePerBirdM2: (float) $row['min_space_per_bird_m2'],
            recFenceHeightM:   (float) $row['rec_fence_height_m'],
            minFenceHeightM:   (float) $row['min_fence_height_m'],
            recFenceStrength:  (int) $row['rec_fence_strength'],
            incubationDays:    (int) $row['incubation_days'],
            eggMassG:          (float) $row['egg_mass_g'],
            kickRiskLevel:     (int) $row['kick_risk_level'],
            targetProteinPct:  (float) $row['target_protein_pct'],
            gritImportance:    (int) $row['grit_importance'],
            legIssueRisk:      (int) $row['leg_issue_risk'],
            hatchWindowDays:   (int) $row['hatch_window_days'],
        );
    }

    public function kickRiskLabel(): string
    {
        return match (true) {
            $this->kickRiskLevel >= 5 => 'Extreme',
            $this->kickRiskLevel === 4 => 'High',
            $this->kickRiskLevel === 3 => 'Moderate',
            default => 'Low',
        };
    }

    /** @return array<string,mixed> */
    public function toArray(): array
    {
        return [
            'species'           => $this->species->value,
            'label'             => $this->species->label(),
            'adultMassKg'       => $this->adultMassKg,
            'spacePerBirdM2'    => $this->spacePerBirdM2,
            'minSpacePerBirdM2' => $this->minSpacePerBirdM2,
            'recFenceHeightM'   => $this->recFenceHeightM,
            'minFenceHeightM'   => $this->minFenceHeightM,
            'recFenceStrength'  => $this->recFenceStrength,
            'incubationDays'    => $this->incubationDays,
            'eggMassG'          => $this->eggMassG,
            'kickRiskLevel'     => $this->kickRiskLevel,
            'kickRiskLabel'     => $this->kickRiskLabel(),
            'targetProteinPct'  => $this->targetProteinPct,
            'gritImportance'    => $this->gritImportance,
            'legIssueRisk'      => $this->legIssueRisk,
            'hatchWindowDays'   => $this->hatchWindowDays,
        ];
    }
}
