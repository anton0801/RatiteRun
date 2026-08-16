<?php

declare(strict_types=1);

namespace RatiteRun\Api\Domain;

enum LayoutKind: string
{
    case Paddock  = 'paddock';
    case Shelter  = 'shelter';
    case Feeder   = 'feeder';
    case Waterer  = 'waterer';
    case Gate     = 'gate';
    case DustBath = 'dustBath';

    /** @return list<string> */
    public static function values(): array
    {
        return array_map(static fn (self $c): string => $c->value, self::cases());
    }
}
