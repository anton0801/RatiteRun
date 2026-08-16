<?php

declare(strict_types=1);

namespace RatiteRun\Api\Core;

final class Request
{
    /** @var array<string,string> */
    private array $headers;
    /** @var array<string,mixed>|null */
    private ?array $json = null;
    private ?string $rawBody = null;

    /** @var array<string,string> заполняется роутером из плейсхолдеров пути */
    public array $params = [];

    public ?string $userId = null;

    private function __construct(
        public readonly string $method,
        public readonly string $path,
        /** @var array<string,mixed> */
        public readonly array $query,
    ) {
        $this->headers = self::collectHeaders();
    }

    public static function fromGlobals(): self
    {
        $method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');

        $uri = $_SERVER['REQUEST_URI'] ?? '/';
        $path = parse_url($uri, PHP_URL_PATH);
        $path = is_string($path) ? $path : '/';

        // отрезаем префикс, если API живёт в подкаталоге
        $base = Config::get('API_BASE_PATH', '');
        if ($base !== null && $base !== '' && str_starts_with($path, $base)) {
            $path = substr($path, strlen($base));
        }
        $path = '/' . trim($path, '/');

        return new self($method, $path, $_GET);
    }

    /** @return array<string,string> */
    private static function collectHeaders(): array
    {
        $headers = [];
        foreach ($_SERVER as $key => $value) {
            if (!is_string($value)) {
                continue;
            }
            if (str_starts_with($key, 'HTTP_')) {
                $name = strtolower(str_replace('_', '-', substr($key, 5)));
                $headers[$name] = $value;
            }
        }
        // CONTENT_TYPE / CONTENT_LENGTH приходят без префикса HTTP_
        if (isset($_SERVER['CONTENT_TYPE']) && is_string($_SERVER['CONTENT_TYPE'])) {
            $headers['content-type'] = $_SERVER['CONTENT_TYPE'];
        }
        if (isset($_SERVER['CONTENT_LENGTH']) && is_string($_SERVER['CONTENT_LENGTH'])) {
            $headers['content-length'] = $_SERVER['CONTENT_LENGTH'];
        }

        return $headers;
    }

    public function header(string $name, ?string $default = null): ?string
    {
        return $this->headers[strtolower($name)] ?? $default;
    }

    public function bearerToken(): ?string
    {
        $auth = $this->header('authorization');
        if ($auth === null || !preg_match('/^Bearer\s+(\S+)$/i', $auth, $m)) {
            return null;
        }

        return $m[1];
    }

    public function rawBody(): string
    {
        return $this->rawBody ??= (file_get_contents('php://input') ?: '');
    }

    /**
     * Тело запроса как JSON-объект. Пустое тело — пустой массив.
     *
     * @return array<string,mixed>
     */
    public function json(): array
    {
        if ($this->json !== null) {
            return $this->json;
        }

        $body = $this->rawBody();
        if (trim($body) === '') {
            return $this->json = [];
        }

        try {
            $decoded = json_decode($body, true, 32, JSON_THROW_ON_ERROR);
        } catch (\JsonException $e) {
            throw ApiException::badRequest('Request body is not valid JSON: ' . $e->getMessage());
        }

        if (!is_array($decoded) || array_is_list($decoded)) {
            throw ApiException::badRequest('Request body must be a JSON object.');
        }

        /** @var array<string,mixed> $decoded */
        return $this->json = $decoded;
    }

    public function queryString(string $key, ?string $default = null): ?string
    {
        $value = $this->query[$key] ?? null;

        return is_string($value) && $value !== '' ? $value : $default;
    }

    public function queryInt(string $key, int $default, int $min, int $max): int
    {
        $value = $this->query[$key] ?? null;
        if (!is_string($value) || !is_numeric($value)) {
            return $default;
        }

        return max($min, min($max, (int) $value));
    }

    public function param(string $key): string
    {
        return $this->params[$key] ?? '';
    }

    /** Значение If-Match без кавычек, либо null. */
    public function ifMatch(): ?string
    {
        $value = $this->header('if-match');
        if ($value === null || $value === '') {
            return null;
        }

        return trim($value, '"Ww/ ');
    }

    public function ifNoneMatch(): ?string
    {
        $value = $this->header('if-none-match');
        if ($value === null || $value === '') {
            return null;
        }

        return trim($value, '"Ww/ ');
    }

    public function clientIp(): ?string
    {
        $ip = $_SERVER['REMOTE_ADDR'] ?? null;

        return is_string($ip) ? $ip : null;
    }

    public function cookie(string $name): ?string
    {
        $value = $_COOKIE[$name] ?? null;

        return is_string($value) ? $value : null;
    }

    /**
     * Данные из application/x-www-form-urlencoded — веб-форма поддержки.
     *
     * @return array<string,mixed>
     */
    public function form(): array
    {
        return $_POST;
    }

    public function userAgent(): ?string
    {
        $agent = $this->header('user-agent');

        return $agent === null ? null : mb_substr($agent, 0, 255);
    }

    /**
     * Запрос пришёл по TLS? Учитывается X-Forwarded-Proto, поэтому доверять
     * можно только за собственным обратным прокси.
     */
    public function isSecure(): bool
    {
        $https = $_SERVER['HTTPS'] ?? '';
        if (is_string($https) && $https !== '' && strtolower($https) !== 'off') {
            return true;
        }

        return strtolower((string) $this->header('x-forwarded-proto', '')) === 'https';
    }

    public function host(): string
    {
        $host = $this->header('host') ?? (string) Config::get('APP_HOST', 'ratiterun.online');

        // отсекаем порт и всё, что не похоже на имя хоста
        $host = preg_replace('/[^a-zA-Z0-9.\-]/', '', explode(':', $host)[0]) ?? '';

        return $host === '' ? 'ratiterun.online' : $host;
    }
}
