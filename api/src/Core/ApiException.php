<?php

declare(strict_types=1);

namespace RatiteRun\Api\Core;

/**
 * Ошибка, которая сериализуется в RFC 9457 application/problem+json.
 */
class ApiException extends \RuntimeException
{
    /**
     * @param array<string,list<string>> $errors  пофайловые ошибки валидации
     * @param array<string,string>       $headers дополнительные заголовки ответа
     */
    public function __construct(
        private readonly int $status,
        private readonly string $type,
        private readonly string $title,
        string $detail = '',
        private readonly array $errors = [],
        private readonly array $headers = [],
    ) {
        parent::__construct($detail === '' ? $title : $detail, $status);
    }

    public function status(): int
    {
        return $this->status;
    }

    public function type(): string
    {
        return $this->type;
    }

    public function title(): string
    {
        return $this->title;
    }

    public function detail(): string
    {
        return $this->getMessage();
    }

    /** @return array<string,list<string>> */
    public function errors(): array
    {
        return $this->errors;
    }

    /** @return array<string,string> */
    public function headers(): array
    {
        return $this->headers;
    }

    // -- фабрики под частые случаи -------------------------------------------

    public static function badRequest(string $detail): self
    {
        return new self(400, 'about:blank', 'Bad Request', $detail);
    }

    /** @param array<string,list<string>> $errors */
    public static function validation(array $errors, string $detail = 'The request body failed validation.'): self
    {
        return new self(422, 'https://api.ratiterun.online/problems/validation', 'Unprocessable Entity', $detail, $errors);
    }

    public static function unauthorized(string $detail = 'Missing or invalid access token.'): self
    {
        return new self(
            401,
            'https://api.ratiterun.online/problems/unauthorized',
            'Unauthorized',
            $detail,
            [],
            ['WWW-Authenticate' => 'Bearer realm="ratiterun"'],
        );
    }

    public static function forbidden(string $detail = 'You do not have access to this resource.'): self
    {
        return new self(403, 'about:blank', 'Forbidden', $detail);
    }

    public static function notFound(string $detail = 'Resource not found.'): self
    {
        return new self(404, 'about:blank', 'Not Found', $detail);
    }

    public static function methodNotAllowed(string $allow): self
    {
        return new self(
            405,
            'about:blank',
            'Method Not Allowed',
            'This method is not supported for the requested resource.',
            [],
            ['Allow' => $allow],
        );
    }

    public static function conflict(string $detail): self
    {
        return new self(409, 'https://api.ratiterun.online/problems/conflict', 'Conflict', $detail);
    }

    /** Клиент прислал устаревший ETag — версия на сервере уже другая. */
    public static function preconditionFailed(int $currentVersion): self
    {
        return new self(
            412,
            'https://api.ratiterun.online/problems/stale-version',
            'Precondition Failed',
            'The resource has been modified. Re-fetch it and retry with the current ETag.',
            [],
            ['ETag' => '"' . $currentVersion . '"'],
        );
    }

    public static function preconditionRequired(string $detail = 'This request requires an If-Match header.'): self
    {
        return new self(428, 'about:blank', 'Precondition Required', $detail);
    }

    public static function payloadTooLarge(string $detail): self
    {
        return new self(413, 'about:blank', 'Payload Too Large', $detail);
    }

    public static function unsupportedMediaType(string $detail): self
    {
        return new self(415, 'about:blank', 'Unsupported Media Type', $detail);
    }

    public static function tooManyRequests(int $retryAfter): self
    {
        return new self(
            429,
            'https://api.ratiterun.online/problems/rate-limit',
            'Too Many Requests',
            'Rate limit exceeded. Retry later.',
            [],
            ['Retry-After' => (string) $retryAfter],
        );
    }

    public static function internal(string $detail = 'An unexpected error occurred.'): self
    {
        return new self(500, 'about:blank', 'Internal Server Error', $detail);
    }
}
