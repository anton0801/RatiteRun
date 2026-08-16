<?php

declare(strict_types=1);

namespace RatiteRun\Api\Repository;

use RatiteRun\Api\Core\ApiException;
use RatiteRun\Api\Core\Database;
use RatiteRun\Api\Domain\Species;
use RatiteRun\Api\Domain\SpeciesPreset;

final class PresetRepository
{
    /** @var array<string,SpeciesPreset> кэш в пределах запроса */
    private array $cache = [];

    public function __construct(private readonly Database $db)
    {
    }

    public function find(Species $species, string $locale = 'en'): SpeciesPreset
    {
        $key = $species->value . '|' . $locale;
        if (isset($this->cache[$key])) {
            return $this->cache[$key];
        }

        $row = $this->db->fetchOne(
            'SELECT * FROM species_presets WHERE species = ? AND locale = ?',
            [$species->value, $locale],
        );

        // локаль без своей строки падает на английскую
        if ($row === null && $locale !== 'en') {
            return $this->cache[$key] = $this->find($species, 'en');
        }

        if ($row === null) {
            throw ApiException::internal("No preset configured for species {$species->value}.");
        }

        return $this->cache[$key] = SpeciesPreset::fromRow($row);
    }

    /** @return list<SpeciesPreset> */
    public function all(string $locale = 'en'): array
    {
        return array_map(
            fn (Species $species): SpeciesPreset => $this->find($species, $locale),
            Species::cases(),
        );
    }

    public function lastUpdated(string $locale = 'en'): ?string
    {
        $value = $this->db->fetchValue(
            'SELECT MAX(updated_at) FROM species_presets WHERE locale IN (?, ?)',
            [$locale, 'en'],
        );

        return is_string($value) ? $value : null;
    }

    public function content(string $slug, string $locale = 'en'): ?string
    {
        $value = $this->db->fetchValue(
            'SELECT body FROM content_blocks WHERE slug = ? AND locale = ?',
            [$slug, $locale],
        );

        if ($value === null && $locale !== 'en') {
            return $this->content($slug, 'en');
        }

        return is_string($value) ? $value : null;
    }
}
