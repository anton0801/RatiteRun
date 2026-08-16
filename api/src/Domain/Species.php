<?php

declare(strict_types=1);

namespace RatiteRun\Api\Domain;

enum Species: string
{
    case Ostrich = 'ostrich';
    case Emu     = 'emu';
    case Rhea    = 'rhea';

    public function label(): string
    {
        return match ($this) {
            self::Ostrich => 'Ostrich',
            self::Emu     => 'Emu',
            self::Rhea    => 'Rhea',
        };
    }

    /** @return list<string> */
    public static function values(): array
    {
        return array_map(static fn (self $c): string => $c->value, self::cases());
    }
}
