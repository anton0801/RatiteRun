<?php

declare(strict_types=1);

namespace RatiteRun\Api\Domain;

enum Priority: string
{
    case Low    = 'low';
    case Medium = 'medium';
    case High   = 'high';

    /** @return list<string> */
    public static function values(): array
    {
        return array_map(static fn (self $c): string => $c->value, self::cases());
    }
}
