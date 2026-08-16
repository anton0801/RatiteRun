<?php

declare(strict_types=1);

namespace RatiteRun\Api\Core;

/**
 * Роутер по сегментам пути. Плейсхолдеры вида {id} попадают в $request->params.
 */
final class Router
{
    /** @var list<array{method:string,segments:list<string>,handler:callable,auth:bool}> */
    private array $routes = [];

    /** @param string $prefix версия API, попадает в начало каждого маршрута */
    public function __construct(private readonly string $prefix = '')
    {
    }

    public function get(string $path, callable $handler, bool $auth = true): void
    {
        $this->add('GET', $path, $handler, $auth);
    }

    public function post(string $path, callable $handler, bool $auth = true): void
    {
        $this->add('POST', $path, $handler, $auth);
    }

    /**
     * Маршрут вне версионного префикса — для страниц, которые должны жить
     * по красивым адресам: /privacy-terms, /support-form.
     */
    public function page(string $method, string $path, callable $handler): void
    {
        $this->routes[] = [
            'method'   => strtoupper($method),
            'segments' => $this->split($path),
            'handler'  => $handler,
            'auth'     => false,
        ];
    }

    public function put(string $path, callable $handler, bool $auth = true): void
    {
        $this->add('PUT', $path, $handler, $auth);
    }

    public function patch(string $path, callable $handler, bool $auth = true): void
    {
        $this->add('PATCH', $path, $handler, $auth);
    }

    public function delete(string $path, callable $handler, bool $auth = true): void
    {
        $this->add('DELETE', $path, $handler, $auth);
    }

    private function add(string $method, string $path, callable $handler, bool $auth): void
    {
        $this->routes[] = [
            'method'   => $method,
            'segments' => $this->split($this->prefix . '/' . ltrim($path, '/')),
            'handler'  => $handler,
            'auth'     => $auth,
        ];
    }

    /** @return list<string> */
    private function split(string $path): array
    {
        $trimmed = trim($path, '/');

        return $trimmed === '' ? [] : explode('/', $trimmed);
    }

    /**
     * @return array{handler:callable,auth:bool,params:array<string,string>}
     * @throws ApiException 404 если пути нет, 405 если есть но другой метод
     */
    public function match(Request $request): array
    {
        $segments = $this->split($request->path);
        $allowed = [];

        foreach ($this->routes as $route) {
            $params = $this->matchSegments($route['segments'], $segments);
            if ($params === null) {
                continue;
            }

            if ($route['method'] !== $request->method) {
                $allowed[$route['method']] = true;
                continue;
            }

            return ['handler' => $route['handler'], 'auth' => $route['auth'], 'params' => $params];
        }

        if ($allowed !== []) {
            $allowed['OPTIONS'] = true;
            throw ApiException::methodNotAllowed(implode(', ', array_keys($allowed)));
        }

        throw ApiException::notFound('No route matches ' . $request->method . ' ' . $request->path . '.');
    }

    /**
     * @param list<string> $pattern
     * @param list<string> $actual
     * @return array<string,string>|null
     */
    private function matchSegments(array $pattern, array $actual): ?array
    {
        if (count($pattern) !== count($actual)) {
            return null;
        }

        $params = [];
        foreach ($pattern as $i => $segment) {
            if (str_starts_with($segment, '{') && str_ends_with($segment, '}')) {
                $name = substr($segment, 1, -1);
                if ($actual[$i] === '') {
                    return null;
                }
                $params[$name] = rawurldecode($actual[$i]);
                continue;
            }

            if ($segment !== $actual[$i]) {
                return null;
            }
        }

        return $params;
    }
}
