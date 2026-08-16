<?php

declare(strict_types=1);

namespace RatiteRun\Api\Domain;

final readonly class EngineResult
{
    public function __construct(
        public Verdict $verdict,
        public string $headline,
        public string $detail,
        /** 0…1 — вес в общей готовности */
        public float $score,
    ) {
    }

    /** @return array<string,mixed> */
    public function toArray(): array
    {
        return [
            'verdict'  => $this->verdict->value,
            'headline' => $this->headline,
            'detail'   => $this->detail,
            'score'    => round($this->score, 4),
        ];
    }
}
