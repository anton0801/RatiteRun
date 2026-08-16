<?php

declare(strict_types=1);

namespace RatiteRun\Api\Domain;

enum FlockStatus: string
{
    case Setup     = 'setup';
    case Active    = 'active';
    case Attention = 'attention';
    case Danger    = 'danger';

    /** @return list<string> */
    public static function values(): array
    {
        return array_map(static fn (self $c): string => $c->value, self::cases());
    }
}
