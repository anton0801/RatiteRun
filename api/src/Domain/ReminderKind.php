<?php

declare(strict_types=1);

namespace RatiteRun\Api\Domain;

enum ReminderKind: string
{
    case FeedGrit   = 'feedGrit';
    case Water      = 'water';
    case FenceCheck = 'fenceCheck';
    case LegHealth  = 'legHealth';

    public function label(): string
    {
        return match ($this) {
            self::FeedGrit   => 'Feed & Grit',
            self::Water      => 'Water',
            self::FenceCheck => 'Fence Check',
            self::LegHealth  => 'Leg / Health Inspection',
        };
    }

    /** @return list<string> */
    public static function values(): array
    {
        return array_map(static fn (self $c): string => $c->value, self::cases());
    }
}
