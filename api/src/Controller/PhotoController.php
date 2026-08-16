<?php

declare(strict_types=1);

namespace RatiteRun\Api\Controller;

use RatiteRun\Api\Core\ApiException;
use RatiteRun\Api\Core\Request;
use RatiteRun\Api\Core\Response;

/**
 * Фото стада. Отдельный ресурс, а не поле агрегата: сейчас Flock.photo лежит
 * Data-блобом внутри JSON в UserDefaults — это и раздувает состояние,
 * и не годится для передачи по сети.
 */
final class PhotoController extends Controller
{
    /** POST /v1/flocks/{id}/photo (multipart/form-data, поле `photo`) */
    public function upload(Request $request): Response
    {
        $userId = $this->userId($request);
        $flockId = $this->flockId($request);

        $file = $_FILES['photo'] ?? null;
        if (!is_array($file)) {
            throw ApiException::badRequest('Expected a multipart/form-data upload with a `photo` field.');
        }

        $row = $this->c->flocks()->requireRow($userId, $flockId);
        $previousKey = is_string($row['photo_key'] ?? null) ? $row['photo_key'] : null;

        $key = $this->c->photos()->store($flockId, $file);
        $this->c->flocks()->setPhotoKey($userId, $flockId, $key);

        if ($previousKey !== null && $previousKey !== $key) {
            $this->c->photos()->delete($previousKey);
        }

        $this->c->audit()->record($userId, $flockId, 'flock.photo.upload', null, null, $request->clientIp());

        return Response::json([
            'photoUrl'  => "/v1/flocks/{$flockId}/photo",
            'updatedAt' => \RatiteRun\Api\Core\Clock::iso(),
        ]);
    }

    /** GET /v1/flocks/{id}/photo */
    public function show(Request $request): Response
    {
        $row = $this->c->flocks()->requireRow($this->userId($request), $this->flockId($request));

        $key = $row['photo_key'] ?? null;
        if (!is_string($key) || $key === '') {
            throw ApiException::notFound('This flock has no photo.');
        }

        $etag = substr(md5($key), 0, 16);
        if ($request->ifNoneMatch() === $etag) {
            return Response::notModified($etag);
        }

        return Response::binary($this->c->photos()->read($key), 'image/jpeg')
            ->withEtag($etag)
            ->withPrivateCache(86400);
    }

    /** DELETE /v1/flocks/{id}/photo */
    public function destroy(Request $request): Response
    {
        $userId = $this->userId($request);
        $flockId = $this->flockId($request);

        $row = $this->c->flocks()->requireRow($userId, $flockId);
        $key = $row['photo_key'] ?? null;

        $this->c->flocks()->setPhotoKey($userId, $flockId, null);
        $this->c->photos()->delete(is_string($key) ? $key : null);

        return Response::noContent();
    }
}
