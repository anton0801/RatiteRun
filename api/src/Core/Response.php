<?php

declare(strict_types=1);

namespace RatiteRun\Api\Core;

final class Response
{
    /** @param array<string,string> $headers */
    private function __construct(
        public readonly int $status,
        public readonly mixed $body,
        private array $headers = [],
        public readonly ?string $rawBody = null,
    ) {
    }

    public static function json(mixed $body, int $status = 200): self
    {
        return new self($status, $body, ['Content-Type' => 'application/json; charset=utf-8']);
    }

    public static function created(mixed $body, string $location): self
    {
        return new self(201, $body, [
            'Content-Type' => 'application/json; charset=utf-8',
            'Location'     => $location,
        ]);
    }

    public static function accepted(mixed $body, string $location): self
    {
        return new self(202, $body, [
            'Content-Type' => 'application/json; charset=utf-8',
            'Location'     => $location,
        ]);
    }

    public static function noContent(): self
    {
        return new self(204, null);
    }

    public static function notModified(string $etag): self
    {
        return new self(304, null, ['ETag' => '"' . $etag . '"']);
    }

    /** @param array<string,string> $headers */
    public static function binary(string $data, string $contentType, array $headers = []): self
    {
        return new self(200, null, array_merge(['Content-Type' => $contentType], $headers), $data);
    }

    /** HTML-страница: политика конфиденциальности, форма поддержки. */
    public static function html(string $markup, int $status = 200): self
    {
        return new self($status, null, ['Content-Type' => 'text/html; charset=utf-8'], $markup);
    }

    public static function redirect(string $location, int $status = 303): self
    {
        return new self($status, null, ['Location' => $location]);
    }

    public static function problem(ApiException $e, string $instance): self
    {
        $body = [
            'type'     => $e->type(),
            'title'    => $e->title(),
            'status'   => $e->status(),
            'detail'   => $e->detail(),
            'instance' => $instance,
        ];
        if ($e->errors() !== []) {
            $body['errors'] = $e->errors();
        }

        return new self(
            $e->status(),
            $body,
            array_merge(['Content-Type' => 'application/problem+json; charset=utf-8'], $e->headers()),
        );
    }

    public function withHeader(string $name, string $value): self
    {
        $this->headers[$name] = $value;

        return $this;
    }

    public function contentType(): ?string
    {
        return $this->headers['Content-Type'] ?? null;
    }

    public function withEtag(int|string $version): self
    {
        return $this->withHeader('ETag', '"' . $version . '"');
    }

    /** Кэш на чтение — справочники меняются редко. */
    public function withCache(int $maxAgeSeconds): self
    {
        return $this->withHeader('Cache-Control', 'public, max-age=' . $maxAgeSeconds);
    }

    public function withPrivateCache(int $maxAgeSeconds): self
    {
        return $this->withHeader('Cache-Control', 'private, max-age=' . $maxAgeSeconds);
    }

    public function send(): void
    {
        http_response_code($this->status);

        foreach ($this->headers as $name => $value) {
            header($name . ': ' . $value);
        }

        if ($this->status === 204 || $this->status === 304) {
            return;
        }

        if ($this->rawBody !== null) {
            header('Content-Length: ' . strlen($this->rawBody));
            echo $this->rawBody;

            return;
        }

        if ($this->body === null) {
            return;
        }

        echo json_encode(
            $this->body,
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRESERVE_ZERO_FRACTION,
        );
    }
}
