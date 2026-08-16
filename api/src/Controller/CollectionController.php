<?php

declare(strict_types=1);

namespace RatiteRun\Api\Controller;

use RatiteRun\Api\Core\ApiException;
use RatiteRun\Api\Core\Request;
use RatiteRun\Api\Core\Response;
use RatiteRun\Api\Core\Uuid;
use RatiteRun\Api\Core\Validator;

/**
 * Коллекции внутри стада: записи о птицах, напоминания, объекты на плане.
 * У каждой есть собственный id и жизненный цикл, поэтому это отдельные ресурсы,
 * а не части агрегата.
 */
final class CollectionController extends Controller
{
    // -- записи о птицах ------------------------------------------------------

    /** GET /v1/flocks/{id}/birds */
    public function birds(Request $request): Response
    {
        $flockId = $this->flockId($request);

        return Response::json([
            'data' => $this->c->birds()->listForFlock($flockId, $request->queryString('birdId')),
        ]);
    }

    /** POST /v1/flocks/{id}/birds */
    public function createBird(Request $request): Response
    {
        $flockId = $this->flockId($request);
        $record = $this->c->birds()->create($flockId, $request->json());
        $this->c->flocks()->touch($flockId);

        return Response::created($record, "/v1/flocks/{$flockId}/birds/{$record['id']}");
    }

    /** GET /v1/flocks/{id}/birds/{recordId} */
    public function showBird(Request $request): Response
    {
        return Response::json(
            $this->c->birds()->find($this->flockId($request), $this->subId($request, 'recordId')),
        );
    }

    /** PATCH /v1/flocks/{id}/birds/{recordId} */
    public function updateBird(Request $request): Response
    {
        $flockId = $this->flockId($request);
        $record = $this->c->birds()->update($flockId, $this->subId($request, 'recordId'), $request->json());
        $this->c->flocks()->touch($flockId);

        return Response::json($record);
    }

    /** DELETE /v1/flocks/{id}/birds/{recordId} */
    public function deleteBird(Request $request): Response
    {
        $flockId = $this->flockId($request);
        $this->c->birds()->delete($flockId, $this->subId($request, 'recordId'));
        $this->c->flocks()->touch($flockId);

        return Response::noContent();
    }

    /**
     * GET /v1/flocks/{id}/growth
     *
     * Сводка по весу и приросту на каждую птицу. Данные для графиков, которые
     * приложение собирает в RecordsIDView, но нигде не показывает.
     */
    public function growth(Request $request): Response
    {
        return Response::json(['data' => $this->c->birds()->growthSeries($this->flockId($request))]);
    }

    // -- напоминания ----------------------------------------------------------

    /** GET /v1/flocks/{id}/reminders */
    public function reminders(Request $request): Response
    {
        return Response::json(['data' => $this->c->reminders()->listForFlock($this->flockId($request))]);
    }

    /** POST /v1/flocks/{id}/reminders */
    public function createReminder(Request $request): Response
    {
        $flockId = $this->flockId($request);
        $reminder = $this->c->reminders()->create($flockId, $request->json());
        $this->c->flocks()->touch($flockId);

        return Response::created($reminder, "/v1/flocks/{$flockId}/reminders/{$reminder['id']}");
    }

    /** PATCH /v1/flocks/{id}/reminders/{reminderId} */
    public function updateReminder(Request $request): Response
    {
        $flockId = $this->flockId($request);
        $reminder = $this->c->reminders()->update($flockId, $this->subId($request, 'reminderId'), $request->json());
        $this->c->flocks()->touch($flockId);

        return Response::json($reminder);
    }

    /** DELETE /v1/flocks/{id}/reminders/{reminderId} */
    public function deleteReminder(Request $request): Response
    {
        $flockId = $this->flockId($request);
        $this->c->reminders()->delete($flockId, $this->subId($request, 'reminderId'));
        $this->c->flocks()->touch($flockId);

        return Response::noContent();
    }

    // -- план загона ----------------------------------------------------------

    /** GET /v1/flocks/{id}/layout */
    public function layout(Request $request): Response
    {
        return Response::json(['data' => $this->c->layout()->listForFlock($this->flockId($request))]);
    }

    /**
     * PUT /v1/flocks/{id}/layout — замена доски целиком.
     * Перетаскивание объектов не должно порождать PATCH на каждый кадр.
     */
    public function replaceLayout(Request $request): Response
    {
        $flockId = $this->flockId($request);

        $v = new Validator($request->json());
        $items = $v->list('items', 200);
        if ($items === null) {
            $v->addError('items', 'Is required.');
        }
        $v->validate();

        $result = $this->c->layout()->replaceAll($flockId, $items ?? []);
        $this->c->flocks()->touch($flockId);

        return Response::json(['data' => $result]);
    }

    /** POST /v1/flocks/{id}/layout */
    public function createLayoutItem(Request $request): Response
    {
        $flockId = $this->flockId($request);
        $item = $this->c->layout()->create($flockId, $request->json());
        $this->c->flocks()->touch($flockId);

        return Response::created($item, "/v1/flocks/{$flockId}/layout/{$item['id']}");
    }

    /** PATCH /v1/flocks/{id}/layout/{itemId} */
    public function updateLayoutItem(Request $request): Response
    {
        $flockId = $this->flockId($request);
        $item = $this->c->layout()->update($flockId, $this->subId($request, 'itemId'), $request->json());
        $this->c->flocks()->touch($flockId);

        return Response::json($item);
    }

    /** DELETE /v1/flocks/{id}/layout/{itemId} */
    public function deleteLayoutItem(Request $request): Response
    {
        $flockId = $this->flockId($request);
        $this->c->layout()->delete($flockId, $this->subId($request, 'itemId'));
        $this->c->flocks()->touch($flockId);

        return Response::noContent();
    }

    // -- аудит ----------------------------------------------------------------

    /** GET /v1/flocks/{id}/history */
    public function history(Request $request): Response
    {
        return Response::json([
            'data' => $this->c->audit()->listForFlock(
                $this->flockId($request),
                $request->queryInt('limit', 100, 1, 500),
            ),
        ]);
    }

    private function subId(Request $request, string $name): string
    {
        $value = $request->param($name);
        if ($value === '') {
            throw ApiException::notFound('Resource not found.');
        }

        return Uuid::requireValid($value, 'resource');
    }
}
