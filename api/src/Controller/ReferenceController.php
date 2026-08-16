<?php

declare(strict_types=1);

namespace RatiteRun\Api\Controller;

use RatiteRun\Api\Core\ApiException;
use RatiteRun\Api\Core\Clock;
use RatiteRun\Api\Core\Request;
use RatiteRun\Api\Core\Response;
use RatiteRun\Api\Domain\Species;

/**
 * Справочные данные. Публичные, кэшируемые, с ETag — клиент тянет их редко
 * и хранит локально. Именно это снимает необходимость выпускать релиз
 * ради правки норматива по площади или высоте забора.
 */
final class ReferenceController extends Controller
{
    private const CACHE_SECONDS = 3600;

    /** GET /v1/species-presets?locale=en */
    public function presets(Request $request): Response
    {
        $locale = $this->locale($request);
        $presets = $this->c->presets()->all($locale);

        $etag = $this->etag($locale);
        if ($request->ifNoneMatch() === $etag) {
            return Response::notModified($etag);
        }

        return Response::json([
            'data'    => array_map(static fn ($p): array => $p->toArray(), $presets),
            'locale'  => $locale,
            'version' => $etag,
        ])->withEtag($etag)->withCache(self::CACHE_SECONDS);
    }

    /** GET /v1/species-presets/{species} */
    public function preset(Request $request): Response
    {
        $value = $request->param('species');
        $species = Species::tryFrom($value)
            ?? throw ApiException::notFound('Unknown species. Expected one of: ' . implode(', ', Species::values()) . '.');

        $locale = $this->locale($request);
        $etag = $this->etag($locale);

        if ($request->ifNoneMatch() === $etag) {
            return Response::notModified($etag);
        }

        return Response::json($this->c->presets()->find($species, $locale)->toArray())
            ->withEtag($etag)
            ->withCache(self::CACHE_SECONDS);
    }

    /**
     * GET /v1/content/{slug}
     *
     * Тексты, зашитые сейчас в бинарник (ratiteDisclaimer, правила хендлинга).
     */
    public function content(Request $request): Response
    {
        $slug = $request->param('slug');
        if (preg_match('/^[a-z0-9.\-]{1,80}$/', $slug) !== 1) {
            throw ApiException::notFound('Unknown content block.');
        }

        $locale = $this->locale($request);
        $body = $this->c->presets()->content($slug, $locale)
            ?? throw ApiException::notFound('Unknown content block.');

        return Response::json(['slug' => $slug, 'locale' => $locale, 'body' => $body])
            ->withCache(self::CACHE_SECONDS);
    }

    private function locale(Request $request): string
    {
        $locale = $request->queryString('locale', 'en') ?? 'en';

        return preg_match('/^[a-z]{2}(-[A-Z]{2})?$/', $locale) === 1 ? $locale : 'en';
    }

    /** ETag справочника — время последнего изменения любой строки. */
    private function etag(string $locale): string
    {
        $updated = $this->c->presets()->lastUpdated($locale) ?? Clock::sql();

        return substr(md5($locale . '|' . $updated), 0, 16);
    }
}
