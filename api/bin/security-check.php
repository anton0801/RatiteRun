<?php

declare(strict_types=1);

/**
 * Проверки транспорта и подписи токенов.
 *
 * Вынесены отдельно от smoke.php, потому что требуют боевого режима
 * (FORCE_HTTPS=true), а функциональный прогон гоняется по локальному http.
 *
 * Запуск: php bin/security-check.php
 */

use RatiteRun\Api\Core\ApiException;
use RatiteRun\Api\Core\Autoloader;
use RatiteRun\Api\Core\Config;
use RatiteRun\Api\Core\Jwt;
use RatiteRun\Api\Core\Kernel;
use RatiteRun\Api\Core\Request;
use RatiteRun\Api\Core\Response;

require __DIR__ . '/../src/Core/Autoloader.php';

Autoloader::register('RatiteRun\\Api', __DIR__ . '/../src');
Config::load(__DIR__ . '/../.env');

// Локальный .env держит FORCE_HTTPS=false ради разработки — здесь нужен боевой режим.
putenv('FORCE_HTTPS=true');
putenv('APP_HOST=ratiterun.online');

$passed = 0;
$failed = 0;

function ok(string $label, bool $condition, string $extra = ''): void
{
    global $passed, $failed;

    if ($condition) {
        $passed++;
        echo "  ✓ {$label}\n";
    } else {
        $failed++;
        echo "  ✗ {$label}" . ($extra !== '' ? " — {$extra}" : '') . "\n";
    }
}

/**
 * @param array<string,string> $server
 * @return array{status:int,headers:array<string,string>,body:mixed}
 */
function probe(string $method, string $path, array $server = []): array
{
    $_GET = [];
    $_POST = [];
    $_COOKIE = [];
    $_SERVER = array_merge([
        'REQUEST_METHOD' => $method,
        'REQUEST_URI'    => $path,
        'REMOTE_ADDR'    => '203.0.113.9',
        'HTTP_HOST'      => 'ratiterun.online',
    ], $server);

    $request = Request::fromGlobals();

    try {
        $response = (new Kernel())->handle($request);
    } catch (ApiException $e) {
        $response = Response::problem($e, $path);
    }

    $reflection = new ReflectionObject($response);

    return [
        'status'  => $response->status,
        'headers' => $reflection->getProperty('headers')->getValue($response),
        'body'    => $response->body,
    ];
}

echo "\nОтказ от незашифрованного соединения\n";

$r = probe('GET', '/v1/flocks');
ok('API по HTTP → 403', $r['status'] === 403, (string) $r['status']);
ok('в теле сказано про HTTPS', str_contains((string) json_encode($r['body']), 'HTTPS'));

$r = probe('POST', '/v1/auth/anonymous');
ok('POST по HTTP отвергнут, а не перенаправлен', $r['status'] === 403);

$r = probe('GET', '/privacy-terms');
ok('страница по HTTP → 308', $r['status'] === 308, (string) $r['status']);
ok(
    'редирект ведёт на https',
    str_starts_with($r['headers']['Location'] ?? '', 'https://ratiterun.online'),
    $r['headers']['Location'] ?? '',
);

echo "\nHSTS и заголовки\n";

$r = probe('GET', '/v1/species-presets', ['HTTPS' => 'on']);
ok('по HTTPS запрос проходит', $r['status'] === 200, (string) $r['status']);

$hsts = $r['headers']['Strict-Transport-Security'] ?? '';
ok('HSTS выставлен на год', str_contains($hsts, 'max-age=31536000'), $hsts);
ok('HSTS покрывает поддомены', str_contains($hsts, 'includeSubDomains'));
ok('HSTS помечен preload', str_contains($hsts, 'preload'));

$r = probe('GET', '/v1/species-presets', ['HTTP_X_FORWARDED_PROTO' => 'https']);
ok('за обратным прокси X-Forwarded-Proto учитывается', $r['status'] === 200);

echo "\nПодпись токенов\n";

$token = Jwt::encode(['sub' => 'ABCDEF01-2345-4678-A9AB-CDEF01234567'], 'test-secret-for-checks', 60);
$parts = explode('.', $token);
$forged = $parts[0] . '.' . $parts[1] . '.' . rtrim(strtr(base64_encode('garbage'), '+/', '-_'), '=');

try {
    Jwt::decode($forged, 'test-secret-for-checks');
    ok('подделанная подпись отвергнута', false, 'токен принят!');
} catch (ApiException $e) {
    ok('подделанная подпись отвергнута', $e->status() === 401);
}

try {
    Jwt::decode($token, 'a-different-secret');
    ok('токен, подписанный чужим секретом, отвергнут', false, 'токен принят!');
} catch (ApiException $e) {
    ok('токен, подписанный чужим секретом, отвергнут', $e->status() === 401);
}

try {
    Jwt::decode(Jwt::encode(['sub' => 'x'], 'test-secret-for-checks', -10), 'test-secret-for-checks');
    ok('просроченный токен отвергнут', false, 'токен принят!');
} catch (ApiException $e) {
    ok('просроченный токен отвергнут', str_contains($e->detail(), 'expired'));
}

// alg:none — классическая попытка обойти проверку подписи
$noneHeader = rtrim(strtr(base64_encode('{"alg":"none","typ":"JWT"}'), '+/', '-_'), '=');
$nonePayload = rtrim(strtr(base64_encode('{"sub":"attacker","exp":9999999999}'), '+/', '-_'), '=');

try {
    Jwt::decode($noneHeader . '.' . $nonePayload . '.', 'test-secret-for-checks');
    ok('alg:none отвергнут', false, 'токен принят!');
} catch (ApiException $e) {
    ok('alg:none отвергнут', $e->status() === 401);
}

echo "\n" . str_repeat('─', 46) . "\n";
echo "Пройдено: {$passed}   Провалено: {$failed}\n";

exit($failed === 0 ? 0 : 1);
