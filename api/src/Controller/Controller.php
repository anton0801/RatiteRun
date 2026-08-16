<?php

declare(strict_types=1);

namespace RatiteRun\Api\Controller;

use RatiteRun\Api\Core\ApiException;
use RatiteRun\Api\Core\Container;
use RatiteRun\Api\Core\Request;
use RatiteRun\Api\Core\Uuid;

abstract class Controller
{
    public function __construct(protected readonly Container $c)
    {
    }

    protected function userId(Request $request): string
    {
        return $request->userId ?? throw ApiException::unauthorized();
    }

    /** Валидирует {id} из пути и проверяет, что стадо принадлежит пользователю. */
    protected function flockId(Request $request): string
    {
        $flockId = Uuid::requireValid($request->param('id'), 'flock');

        // 404 вместо 403: чужое стадо не должно быть отличимо от несуществующего
        $this->c->flocks()->requireRow($this->userId($request), $flockId);

        return $flockId;
    }
}
