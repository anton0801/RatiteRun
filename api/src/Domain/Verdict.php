<?php

declare(strict_types=1);

namespace RatiteRun\Api\Domain;

enum Verdict: string
{
    case Good  = 'good';
    case Watch = 'watch';
    case Alert = 'alert';
}
