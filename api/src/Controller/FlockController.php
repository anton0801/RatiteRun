<?php

declare(strict_types=1);

namespace RatiteRun\Api\Controller;

use RatiteRun\Api\Core\ApiException;
use RatiteRun\Api\Core\Request;
use RatiteRun\Api\Core\Response;
use RatiteRun\Api\Core\Validator;
use RatiteRun\Api\Domain\Engines;
use RatiteRun\Api\Domain\FlockSections;
use RatiteRun\Api\Domain\FlockStatus;
use RatiteRun\Api\Domain\Priority;
use RatiteRun\Api\Domain\Species;

final class FlockController extends Controller
{
    /** GET /v1/flocks */
    public function index(Request $request): Response
    {
        $userId = $this->userId($request);

        $status = $request->queryString('status');
        if ($status !== null && !in_array($status, FlockStatus::values(), true)) {
            throw ApiException::validation(['status' => ['Must be one of: ' . implode(', ', FlockStatus::values()) . '.']]);
        }

        $species = $request->queryString('species');
        if ($species !== null && !in_array($species, Species::values(), true)) {
            throw ApiException::validation(['species' => ['Must be one of: ' . implode(', ', Species::values()) . '.']]);
        }

        $result = $this->c->flocks()->list(
            $userId,
            $status,
            $species,
            $request->queryInt('limit', 50, 1, 200),
            $request->queryString('cursor'),
        );

        return Response::json([
            'data'       => $result['items'],
            'nextCursor' => $result['nextCursor'],
        ])->withPrivateCache(0);
    }

    /** POST /v1/flocks */
    public function store(Request $request): Response
    {
        $userId = $this->userId($request);

        $v = new Validator($request->json());
        $id = $v->uuid('id');
        $title = $v->string('title', 160);
        $species = $v->enum('species', Species::values());
        $count = $v->int('count', 1, 100000);
        $age = $v->string('age', 80);
        $notes = $v->string('notes', 4000);
        $priority = $v->enum('priority', Priority::values());
        $status = $v->enum('status', FlockStatus::values());
        $v->validate();

        $flock = $this->c->flocks()->create($userId, array_filter([
            'id'       => $id,
            'title'    => ($title === null || $title === '') ? null : $title,
            'species'  => $species,
            'count'    => $count,
            'age'      => ($age === null || $age === '') ? null : $age,
            'notes'    => $notes,
            'priority' => $priority,
            'status'   => $status,
        ], static fn (mixed $value): bool => $value !== null));

        $this->c->audit()->record($userId, (string) $flock['id'], 'flock.create', null, null, $request->clientIp());

        return Response::created($flock, '/v1/flocks/' . $flock['id'])
            ->withEtag((int) $flock['version']);
    }

    /** GET /v1/flocks/{id} */
    public function show(Request $request): Response
    {
        $userId = $this->userId($request);
        $row = $this->c->flocks()->requireRow($userId, $this->flockId($request));

        $version = (string) $row['version'];
        if ($request->ifNoneMatch() === $version) {
            return Response::notModified($version);
        }

        return Response::json($this->c->flocks()->presentFull($row))
            ->withEtag($version)
            ->withPrivateCache(0);
    }

    /** PATCH /v1/flocks/{id} */
    public function update(Request $request): Response
    {
        $userId = $this->userId($request);
        $flockId = $this->flockId($request);

        $body = $request->json();
        $v = new Validator($body);

        $changes = [];
        if ($v->has('title')) {
            $changes['title'] = $v->requiredString('title', 160);
        }
        if ($v->has('species')) {
            $changes['species'] = $v->requiredEnum('species', Species::values());
        }
        if ($v->has('count')) {
            $changes['count'] = $v->requiredInt('count', 1, 100000);
        }
        if ($v->has('age')) {
            $changes['age'] = $v->string('age', 80);
        }
        if ($v->has('notes')) {
            $changes['notes'] = $v->string('notes', 4000);
        }
        if ($v->has('priority')) {
            $changes['priority'] = $v->requiredEnum('priority', Priority::values());
        }
        if ($v->has('status')) {
            $changes['status'] = $v->requiredEnum('status', FlockStatus::values());
        }
        $v->validate();

        if ($changes === []) {
            throw ApiException::badRequest('No updatable fields in request body.');
        }

        $flock = $this->c->flocks()->updateCore($userId, $flockId, $changes, $request->ifMatch());

        $this->c->audit()->record(
            $userId,
            $flockId,
            'flock.update',
            implode(',', array_keys($changes)),
            $changes,
            $request->clientIp(),
        );

        return Response::json($flock)->withEtag((int) $flock['version']);
    }

    /** DELETE /v1/flocks/{id} */
    public function destroy(Request $request): Response
    {
        $userId = $this->userId($request);
        $flockId = $this->flockId($request);

        $this->c->flocks()->softDelete($userId, $flockId);
        $this->c->audit()->record($userId, $flockId, 'flock.delete', null, null, $request->clientIp());

        return Response::noContent();
    }

    /** POST /v1/flocks/{id}/duplicate */
    public function duplicate(Request $request): Response
    {
        $userId = $this->userId($request);
        $flock = $this->c->flocks()->duplicate($userId, $this->flockId($request));

        return Response::created($flock, '/v1/flocks/' . $flock['id'])
            ->withEtag((int) $flock['version']);
    }

    // -- секции ---------------------------------------------------------------

    /** GET /v1/flocks/{id}/{section} */
    public function showSection(Request $request): Response
    {
        $section = $this->sectionName($request->param('section'));
        $row = $this->c->flocks()->requireRow($this->userId($request), $this->flockId($request));

        $column = FlockSections::COLUMNS[$section];
        $raw = $row[$column] ?? null;
        $value = is_string($raw) ? json_decode($raw, true) : null;

        return Response::json(is_array($value) ? $value : FlockSections::defaults($section))
            ->withEtag((int) $row['version']);
    }

    /** PUT /v1/flocks/{id}/{section} */
    public function updateSection(Request $request): Response
    {
        $userId = $this->userId($request);
        $flockId = $this->flockId($request);
        $section = $this->sectionName($request->param('section'));

        $result = $this->c->flocks()->updateSection(
            $userId,
            $flockId,
            $section,
            $request->json(),
            $request->ifMatch(),
        );

        $this->c->audit()->record(
            $userId,
            $flockId,
            'flock.section.update',
            $section,
            $result['section'],
            $request->clientIp(),
        );

        return Response::json($result['section'])->withEtag($result['version']);
    }

    private function sectionName(string $slug): string
    {
        return FlockSections::SLUGS[$slug] ?? throw ApiException::notFound('Unknown flock section.');
    }

    // -- производные ресурсы --------------------------------------------------

    /** GET /v1/flocks/{id}/readiness */
    public function readiness(Request $request): Response
    {
        $row = $this->c->flocks()->requireRow($this->userId($request), $this->flockId($request));
        $preset = $this->c->presets()->find(Species::from((string) $row['species']));

        return Response::json(
            Engines::readiness($this->c->flocks()->toEngineInput($row), $preset),
        )->withEtag((int) $row['version']);
    }

    /** GET /v1/flocks/{id}/evaluation — все вердикты движков разом. */
    public function evaluation(Request $request): Response
    {
        $row = $this->c->flocks()->requireRow($this->userId($request), $this->flockId($request));
        $preset = $this->c->presets()->find(Species::from((string) $row['species']));

        return Response::json(
            Engines::evaluateAll($this->c->flocks()->toEngineInput($row), $preset),
        )->withEtag((int) $row['version']);
    }

    /** GET /v1/flocks/{id}/kit */
    public function kit(Request $request): Response
    {
        $row = $this->c->flocks()->requireRow($this->userId($request), $this->flockId($request));
        $preset = $this->c->presets()->find(Species::from((string) $row['species']));

        return Response::json(Engines::materials($this->c->flocks()->toEngineInput($row), $preset))
            ->withEtag((int) $row['version']);
    }

    /** GET /v1/flocks/{id}/cost?fenceRate=&shelterRate=&feederRate=&gritRate=&labourRate= */
    public function cost(Request $request): Response
    {
        $row = $this->c->flocks()->requireRow($this->userId($request), $this->flockId($request));
        $preset = $this->c->presets()->find(Species::from((string) $row['species']));
        $kit = Engines::materials($this->c->flocks()->toEngineInput($row), $preset);

        $rate = static function (Request $r, string $key, float $default): float {
            $value = $r->queryString($key);

            return $value !== null && is_numeric($value) ? max(0.0, (float) $value) : $default;
        };

        $breakdown = Engines::cost(
            $kit,
            $rate($request, 'fenceRate', 35),
            $rate($request, 'shelterRate', 60),
            $rate($request, 'feederRate', 45),
            $rate($request, 'gritRate', 3),
            $rate($request, 'labourRate', 120),
        );

        return Response::json(['kit' => $kit, 'cost' => $breakdown]);
    }

    /**
     * POST /v1/evaluate
     *
     * Считает вердикты по черновику без сохранения — для «что если»
     * и для экранов, где пользователь ещё крутит ползунки.
     */
    public function evaluateDraft(Request $request): Response
    {
        $body = $request->json();

        $v = new Validator($body);
        $speciesValue = $v->requiredEnum('species', Species::values());
        $count = $v->requiredInt('count', 1, 100000);
        $v->validate();

        $preset = $this->c->presets()->find(Species::from((string) $speciesValue));

        $flock = ['species' => $speciesValue, 'count' => $count];
        foreach (FlockSections::WRITABLE as $section) {
            $input = $body[$section] ?? null;
            $flock[$section] = FlockSections::validate(
                $section,
                is_array($input) ? $input : [],
            );
        }
        $flock['kit'] = Engines::materials($flock, $preset);

        return Response::json(Engines::evaluateAll($flock, $preset));
    }
}
