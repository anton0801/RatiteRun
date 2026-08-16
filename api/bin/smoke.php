<?php

declare(strict_types=1);

/**
 * Сквозная проверка API без веб-сервера: Kernel вызывается напрямую
 * с синтетическим $_SERVER. Запуск: php bin/smoke.php
 */

use RatiteRun\Api\Core\ApiException;
use RatiteRun\Api\Core\Autoloader;
use RatiteRun\Api\Core\Config;
use RatiteRun\Api\Core\Kernel;
use RatiteRun\Api\Core\Request;
use RatiteRun\Api\Core\Response;

require __DIR__ . '/../src/Core/Autoloader.php';

Autoloader::register('RatiteRun\\Api', __DIR__ . '/../src');
Config::load(__DIR__ . '/../.env');

// Вывод буферизуется: без этого echo из проверок «отправляет» тело раньше,
// чем setcookie() в CSRF успевает выставить заголовок, и PHP шумит warning'ами.
// В реальном HTTP такого порядка не бывает.
ob_start();

$passed = 0;
$failed = 0;
$accessToken = null;

// Прогон бьёт по API сотнями запросов с одного адреса. Счётчики от прошлого
// запуска иначе упрутся в лимит и завалят функциональные проверки, поэтому
// окна сбрасываются на старте. Сам лимит проверяется отдельно, ниже.
\RatiteRun\Api\Core\Database::instance()->run('DELETE FROM rate_limits');

/**
 * @param array<string,string> $headers
 * @return array{status:int,body:mixed,headers:array<string,string>}
 */
function call(string $method, string $path, ?array $body = null, array $headers = []): array
{
    global $accessToken;

    $query = [];
    if (str_contains($path, '?')) {
        [$path, $queryString] = explode('?', $path, 2);
        parse_str($queryString, $query);
    }

    $_GET = $query;
    $_SERVER = [
        'REQUEST_METHOD' => $method,
        'REQUEST_URI'    => $path,
        'REMOTE_ADDR'    => '127.0.0.1',
    ];

    if ($accessToken !== null && !isset($headers['Authorization'])) {
        $headers['Authorization'] = 'Bearer ' . $accessToken;
    }
    foreach ($headers as $name => $value) {
        $_SERVER['HTTP_' . strtoupper(str_replace('-', '_', $name))] = $value;
    }

    $raw = $body === null ? '' : json_encode($body, JSON_UNESCAPED_UNICODE);

    // Request читает тело через php://input, которое в CLI не подменить,
    // поэтому собираем объект через рефлексию.
    $request = Request::fromGlobals();
    $reflection = new ReflectionObject($request);
    $rawBody = $reflection->getProperty('rawBody');
    $rawBody->setValue($request, $raw);

    if ($raw !== '') {
        $_SERVER['CONTENT_TYPE'] = 'application/json';
    }

    try {
        $response = (new Kernel())->handle($request);
    } catch (ApiException $e) {
        $response = Response::problem($e, $path);
    }

    $reflectionResponse = new ReflectionObject($response);
    $headersProperty = $reflectionResponse->getProperty('headers');

    return [
        'status'  => $response->status,
        'body'    => $response->body,
        'raw'     => $response->rawBody,
        'headers' => $headersProperty->getValue($response),
    ];
}

/**
 * Отправка HTML-формы: application/x-www-form-urlencoded + куки.
 *
 * @param array<string,string> $fields
 * @param array<string,string> $cookies
 * @return array{status:int,html:string,headers:array<string,string>}
 */
function callForm(string $path, array $fields, array $cookies = []): array
{
    $_GET = [];
    $_POST = $fields;
    $_COOKIE = $cookies;
    $_SERVER = [
        'REQUEST_METHOD' => 'POST',
        'REQUEST_URI'    => $path,
        'REMOTE_ADDR'    => '127.0.0.1',
        'CONTENT_TYPE'   => 'application/x-www-form-urlencoded',
        'HTTP_USER_AGENT' => 'RatiteRun-Smoke/1.0',
    ];

    $request = Request::fromGlobals();

    try {
        $response = (new Kernel())->handle($request);
    } catch (ApiException $e) {
        $response = Response::problem($e, $path);
    }

    $reflection = new ReflectionObject($response);

    $_POST = [];
    $_COOKIE = [];

    return [
        'status'  => $response->status,
        'html'    => (string) $response->rawBody,
        'headers' => $reflection->getProperty('headers')->getValue($response),
    ];
}

/** @return array{status:int,html:string,headers:array<string,string>} */
function callPage(string $path): array
{
    global $accessToken;

    $saved = $accessToken;
    $accessToken = null;                 // страницы публичные

    $_COOKIE = [];
    $r = call('GET', $path);

    $accessToken = $saved;

    return ['status' => $r['status'], 'html' => (string) ($r['raw'] ?? ''), 'headers' => $r['headers']];
}

function check(string $label, bool $condition, string $extra = ''): void
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

function show(mixed $value): string
{
    return substr((string) json_encode($value, JSON_UNESCAPED_UNICODE), 0, 300);
}

// ---------------------------------------------------------------------------

echo "\nAuth\n";

$r = call('POST', '/v1/auth/anonymous', ['deviceId' => 'SMOKE-DEVICE-' . bin2hex(random_bytes(4)), 'platform' => 'ios']);
check('POST /auth/anonymous → 200', $r['status'] === 200, show($r['body']));
check('выдан accessToken', isset($r['body']['accessToken']));
check('пользователь анонимный', ($r['body']['user']['isAnonymous'] ?? null) === true);
$accessToken = $r['body']['accessToken'] ?? null;
$refreshToken = $r['body']['refreshToken'] ?? null;

$r = call('GET', '/v1/me');
check('GET /me → 200', $r['status'] === 200, show($r['body']));

$r = call('GET', '/v1/flocks', null, ['Authorization' => 'Bearer nonsense.token.here']);
check('битый токен → 401', $r['status'] === 401);

echo "\nСправочники\n";

$r = call('GET', '/v1/species-presets');
check('GET /species-presets → 200', $r['status'] === 200);
check('три вида', count($r['body']['data'] ?? []) === 3);
check('у страуса 300 м²/птица', ($r['body']['data'][0]['spacePerBirdM2'] ?? null) == 300.0, show($r['body']['data'][0] ?? null));
$presetEtag = trim($r['headers']['ETag'] ?? '', '"');

$r = call('GET', '/v1/species-presets', null, ['If-None-Match' => '"' . $presetEtag . '"']);
check('повторный запрос с ETag → 304', $r['status'] === 304);

$r = call('GET', '/v1/content/disclaimer');
check('GET /content/disclaimer → 200', $r['status'] === 200);
check('текст дисклеймера пришёл', str_contains((string) ($r['body']['body'] ?? ''), 'forward kick'));

echo "\nСоздание стада\n";

$r = call('POST', '/v1/flocks', ['title' => 'Savanna Emu Herd', 'species' => 'emu', 'count' => 6, 'age' => '18 months', 'priority' => 'high']);
check('POST /flocks → 201', $r['status'] === 201, show($r['body']));
$flockId = $r['body']['id'] ?? null;
check('вернулся id', is_string($flockId));
check('дефолты из пресета: забор 1.8 м', ($r['body']['fencing']['height'] ?? null) == 1.8, show($r['body']['fencing'] ?? null));
check('дефолты из пресета: белок 17%', ($r['body']['feed']['proteinPct'] ?? null) == 17.0);
check('kit посчитан сервером', ($r['body']['kit']['fenceMeters'] ?? 0) > 0, show($r['body']['kit'] ?? null));
check('ETag = версия 1', ($r['headers']['ETag'] ?? '') === '"1"');

$emptyReadiness = $r['body']['readiness']['percent'] ?? null;

$clientId = strtoupper(sprintf(
    '%s-%s-4%s-A%s-%s',
    bin2hex(random_bytes(4)), bin2hex(random_bytes(2)), substr(bin2hex(random_bytes(2)), 1),
    substr(bin2hex(random_bytes(2)), 1), bin2hex(random_bytes(6))
));
$r = call('POST', '/v1/flocks', ['id' => $clientId, 'title' => 'Client-side id', 'species' => 'rhea']);
check('стадо создаётся с id от клиента', ($r['body']['id'] ?? null) === $clientId, show($r['body']['id'] ?? null));

$r = call('POST', '/v1/flocks', ['id' => $clientId, 'title' => 'Duplicate id']);
check('повтор того же id → 409', $r['status'] === 409, show($r['body']));

echo "\nСекции\n";

$r = call('PUT', "/v1/flocks/{$flockId}/housing", [
    'paddockSize' => 1500, 'shelterArea' => 18, 'hasShelter' => true, 'terrain' => 'grassland',
], ['If-Match' => '"1"']);
check('PUT /housing с корректным If-Match → 200', $r['status'] === 200, show($r['body']));
check('paddockSize сохранён', ($r['body']['paddockSize'] ?? null) == 1500.0);
check('spacePerBird не затёрт (частичное слияние)', ($r['body']['spacePerBird'] ?? null) == 200.0, show($r['body']));
check('версия выросла до 2', ($r['headers']['ETag'] ?? '') === '"2"');

$r = call('PUT', "/v1/flocks/{$flockId}/housing", ['paddockSize' => 999], ['If-Match' => '"1"']);
check('устаревший If-Match → 412', $r['status'] === 412, show($r['body']));

$r = call('PUT', "/v1/flocks/{$flockId}/fencing", ['height' => 1.8, 'strength' => 4, 'perimeterSecured' => true]);
check('PUT /fencing без If-Match → 200', $r['status'] === 200);

$r = call('PUT', "/v1/flocks/{$flockId}/water-grit", [
    'waterProvided' => true, 'gritProvided' => true, 'gritGramsPerBird' => 40, 'mineralsProvided' => true,
]);
check('PUT /water-grit (slug → waterGrit) → 200', $r['status'] === 200);

$r = call('PUT', "/v1/flocks/{$flockId}/handling", [
    'neverCorner' => true, 'approachFromSide' => true, 'trainedHandlersOnly' => true, 'useHood' => true,
    'restraintPlan' => 'Two handlers, hood first, back the bird into open pen — never a corner.',
]);
check('PUT /handling → 200', $r['status'] === 200);

$r = call('PUT', "/v1/flocks/{$flockId}/fencing", ['strength' => 99]);
check('strength вне диапазона → 422', $r['status'] === 422, show($r['body']));
check('ошибка адресует поле', isset($r['body']['errors']['strength']));

$r = call('PUT', "/v1/flocks/{$flockId}/nonsense", ['a' => 1]);
check('неизвестная секция → 404', $r['status'] === 404);

echo "\nДвижки\n";

$r = call('GET', "/v1/flocks/{$flockId}/readiness");
check('GET /readiness → 200', $r['status'] === 200, show($r['body']));
$readiness = $r['body']['percent'] ?? 0;
check("готовность выросла с {$emptyReadiness}% до {$readiness}%", $readiness > (int) $emptyReadiness);
check('вернулась разбивка по частям', count($r['body']['parts'] ?? []) === 6);

$r = call('GET', "/v1/flocks/{$flockId}/evaluation");
check('GET /evaluation → 200', $r['status'] === 200);
check('пространство: 250 м²/птица', ($r['body']['space']['perBirdM2'] ?? null) == 250.0, show($r['body']['space'] ?? null));
check('вердикт по пространству good', ($r['body']['space']['verdict'] ?? null) === 'good');
check('правила безопасности пришли', count($r['body']['safety']['rules'] ?? []) >= 4);
check('дата вылупления посчитана', isset($r['body']['breeding']['hatchDate']));

$r = call('POST', '/v1/evaluate', [
    'species' => 'ostrich', 'count' => 10,
    'housing' => ['paddockSize' => 500],
    'fencing' => ['height' => 1.0, 'strength' => 2],
]);
check('POST /evaluate (без сохранения) → 200', $r['status'] === 200);
check('тесный загон → alert', ($r['body']['space']['verdict'] ?? null) === 'alert', show($r['body']['space'] ?? null));
check('низкий забор → alert', ($r['body']['fencing']['verdict'] ?? null) === 'alert');

echo "\nКоллекции\n";

$r = call('POST', "/v1/flocks/{$flockId}/birds", ['birdId' => 'EMU-01', 'weightKg' => 38, 'heightCm' => 165, 'note' => 'Lead female']);
check('POST /birds → 201', $r['status'] === 201, show($r['body']));
$recordId = $r['body']['id'] ?? null;

call('POST', "/v1/flocks/{$flockId}/birds", ['birdId' => 'EMU-02', 'weightKg' => 41, 'heightCm' => 170]);
call('POST', "/v1/flocks/{$flockId}/birds", ['birdId' => 'EMU-01', 'weightKg' => 42, 'heightCm' => 168]);

$r = call('GET', "/v1/flocks/{$flockId}/birds");
check('GET /birds → 3 записи', count($r['body']['data'] ?? []) === 3);

$r = call('GET', "/v1/flocks/{$flockId}/growth");
check('GET /growth → 200', $r['status'] === 200, show($r['body']));
check('прирост EMU-01 = 4 кг', ($r['body']['data'][0]['gainKg'] ?? null) == 4.0, show($r['body']['data'] ?? null));

$r = call('PATCH', "/v1/flocks/{$flockId}/birds/{$recordId}", ['weightKg' => 39.5]);
check('PATCH /birds/{id} → 200', $r['status'] === 200 && ($r['body']['weightKg'] ?? null) == 39.5);

$r = call('POST', "/v1/flocks/{$flockId}/birds", ['weightKg' => 10]);
check('запись без birdId → 422', $r['status'] === 422);

$r = call('POST', "/v1/flocks/{$flockId}/reminders", ['kind' => 'feedGrit', 'hour' => 7, 'minute' => 30]);
check('POST /reminders → 201', $r['status'] === 201, show($r['body']));
check('заголовок подставлен по типу', ($r['body']['title'] ?? null) === 'Feed & Grit');
$reminderId = $r['body']['id'] ?? null;

$r = call('POST', "/v1/flocks/{$flockId}/reminders", ['kind' => 'feedGrit', 'hour' => 25]);
check('час 25 → 422', $r['status'] === 422);

$r = call('PATCH', "/v1/flocks/{$flockId}/reminders/{$reminderId}", ['enabled' => false]);
check('PATCH /reminders → выключено', ($r['body']['enabled'] ?? true) === false);

$r = call('PUT', "/v1/flocks/{$flockId}/layout", ['items' => [
    ['kind' => 'paddock', 'x' => 0.5, 'y' => 0.5],
    ['kind' => 'shelter', 'x' => 0.25, 'y' => 0.25],
    ['kind' => 'dustBath', 'x' => 0.72, 'y' => 0.7],
]]);
check('PUT /layout (замена доски) → 3 объекта', count($r['body']['data'] ?? []) === 3, show($r['body']));

$r = call('PUT', "/v1/flocks/{$flockId}/layout", ['items' => [['kind' => 'paddock', 'x' => 5, 'y' => 0.5]]]);
check('координата вне 0…1 → 422', $r['status'] === 422, show($r['body']));

echo "\nОтчёты\n";

$r = call('POST', "/v1/flocks/{$flockId}/reports", ['sections' => ['spaceFence', 'diet', 'safety'], 'notes' => 'Проверка перед инспекцией', 'currency' => '£', 'shareable' => true]);
check('POST /reports → 201', $r['status'] === 201, show($r['body']));
$reportId = $r['body']['id'] ?? null;
$shareUrl = $r['body']['shareUrl'] ?? null;
check('получена ссылка для шаринга', is_string($shareUrl));

$r = call('GET', "/v1/reports/{$reportId}/pdf");
check('GET /reports/{id}/pdf → 200', $r['status'] === 200);

$r = call('GET', $shareUrl !== null ? '/v1' . substr($shareUrl, 3) : '/v1/shared/reports/bad', null, ['Authorization' => 'Bearer invalid']);
check('публичная ссылка работает без авторизации', $r['status'] === 200, show($r['body']));

$r = call('POST', "/v1/flocks/{$flockId}/reports", ['sections' => ['nope']]);
check('неизвестная секция отчёта → 422', $r['status'] === 422);

echo "\nСписки, копирование, удаление\n";

$r = call('GET', '/v1/flocks');
check('GET /flocks → 200', $r['status'] === 200);
check('в списке сводка, а не агрегат', !isset($r['body']['data'][0]['housing']), show($r['body']['data'][0] ?? null));
check('готовность в сводке есть', isset($r['body']['data'][0]['readinessPercent']));

$r = call('POST', "/v1/flocks/{$flockId}/duplicate");
check('POST /duplicate → 201', $r['status'] === 201);
check('в названии (copy)', str_contains((string) ($r['body']['title'] ?? ''), '(copy)'));
check('записи о птицах скопированы', count($r['body']['birds'] ?? []) === 3, show(count($r['body']['birds'] ?? [])));
check('подпись не скопирована', ($r['body']['signoff']['approved'] ?? true) === false);
$copyId = $r['body']['id'] ?? null;

$r = call('GET', '/v1/flocks?limit=1');
check('пагинация: 1 элемент + курсор', count($r['body']['data'] ?? []) === 1 && $r['body']['nextCursor'] !== null);

$r = call('DELETE', "/v1/flocks/{$copyId}");
check('DELETE /flocks/{id} → 204', $r['status'] === 204);

$r = call('GET', "/v1/flocks/{$copyId}");
check('удалённое стадо → 404', $r['status'] === 404);

echo "\nИзоляция и служебное\n";

$otherToken = $accessToken;
$r = call('POST', '/v1/auth/anonymous', ['deviceId' => 'SMOKE-OTHER-' . bin2hex(random_bytes(4))]);
$accessToken = $r['body']['accessToken'] ?? null;

$r = call('GET', "/v1/flocks/{$flockId}");
check('чужое стадо → 404 (не 403)', $r['status'] === 404);

$r = call('PUT', "/v1/flocks/{$flockId}/housing", ['paddockSize' => 1]);
check('чужая секция недоступна', $r['status'] === 404);

$accessToken = $otherToken;

$idemKey = 'smoke-' . bin2hex(random_bytes(8));
$r1 = call('POST', '/v1/flocks', ['title' => 'Idempotent'], ['Idempotency-Key' => $idemKey]);
$r2 = call('POST', '/v1/flocks', ['title' => 'Idempotent'], ['Idempotency-Key' => $idemKey]);
check('повтор с тем же Idempotency-Key не плодит стадо', ($r1['body']['id'] ?? 'a') === ($r2['body']['id'] ?? 'b'), show($r2['body']['id'] ?? null));
check('ответ помечен как повтор', ($r2['headers']['Idempotency-Replayed'] ?? null) === 'true');

$r = call('POST', '/v1/flocks', ['title' => 'Different body'], ['Idempotency-Key' => $idemKey]);
check('тот же ключ с другим телом → 409', $r['status'] === 409);

$r = call('GET', "/v1/flocks/{$flockId}/history");
check('GET /history → журнал изменений', ($r['status'] === 200) && count($r['body']['data'] ?? []) > 0, show(count($r['body']['data'] ?? [])));

$r = call('GET', '/v1/export');
check('GET /export → 200', $r['status'] === 200);
check('экспорт содержит стада', ($r['body']['flockCount'] ?? 0) > 0);

$r = call('DELETE', '/v1/flocks/' . str_repeat('A', 8) . '-BBBB-CCCC-DDDD-EEEEEEEEEEEE');
check('несуществующий UUID → 404', $r['status'] === 404);

$r = call('GET', '/v1/nope');
check('несуществующий маршрут → 404', $r['status'] === 404);

$r = call('DELETE', '/v1/species-presets');
check('неподдержанный метод → 405', $r['status'] === 405, show($r['body']));
check('заголовок Allow присутствует', isset($r['headers']['Allow']));

$r = call('POST', '/v1/auth/refresh', ['refreshToken' => $refreshToken]);
check('POST /auth/refresh → новая пара', $r['status'] === 200 && isset($r['body']['accessToken']));

$r = call('POST', '/v1/auth/refresh', ['refreshToken' => $refreshToken]);
check('повторное использование refresh → 401', $r['status'] === 401);

echo "\nУдаление аккаунта\n";

$deviceKey = 'SMOKE-DELETE-' . bin2hex(random_bytes(4));
$r = call('POST', '/v1/auth/anonymous', ['deviceId' => $deviceKey], ['Authorization' => '']);
$accessToken = $r['body']['accessToken'] ?? null;
$doomedUser = $r['body']['user']['id'] ?? null;
check('заведён аккаунт под удаление', is_string($accessToken));

$r = call('POST', '/v1/flocks', ['title' => 'Уйдёт вместе с аккаунтом']);
$doomedFlock = $r['body']['id'] ?? null;
check('у него есть стадо', $r['status'] === 201);

$r = call('DELETE', '/v1/me');
check('DELETE /me → 204', $r['status'] === 204, (string) $r['status']);

$r = call('GET', '/v1/me');
check('старый токен больше не работает', $r['status'] === 401, (string) $r['status']);

$stillThere = \RatiteRun\Api\Core\Database::instance()->fetchValue(
    'SELECT COUNT(*) FROM flocks WHERE id = ? AND deleted_at IS NULL',
    [$doomedFlock],
);
check('стада удалённого аккаунта скрыты', (int) $stillThere === 0);

$devicesLeft = \RatiteRun\Api\Core\Database::instance()->fetchValue(
    'SELECT COUNT(*) FROM devices WHERE device_key = ?',
    [$deviceKey],
);
check('привязка устройства удалена (с ней и APNs-токен)', (int) $devicesLeft === 0, 'осталось: ' . $devicesLeft);

// Ключевое: приложение должно уметь войти заново с того же устройства
$accessToken = null;
$r = call('POST', '/v1/auth/anonymous', ['deviceId' => $deviceKey]);
$accessToken = $r['body']['accessToken'] ?? null;
check('повторный вход с того же устройства работает', $r['status'] === 200 && is_string($accessToken), show($r['body']));
check('это НОВЫЙ аккаунт, а не воскресший старый', ($r['body']['user']['id'] ?? '') !== $doomedUser);

$r = call('GET', '/v1/flocks');
check('новый аккаунт не видит стада старого', count($r['body']['data'] ?? []) === 0);

echo "\nЗаголовки безопасности\n";

$r = call('GET', '/v1/species-presets');
$h = $r['headers'];
check('X-Content-Type-Options: nosniff', ($h['X-Content-Type-Options'] ?? '') === 'nosniff');
check('X-Frame-Options: DENY', ($h['X-Frame-Options'] ?? '') === 'DENY');
check('CSP запрещает всё по умолчанию', str_contains($h['Content-Security-Policy'] ?? '', "default-src 'none'"));
check('CSP запрещает встраивание в iframe', str_contains($h['Content-Security-Policy'] ?? '', "frame-ancestors 'none'"));
check('Referrer-Policy для API: no-referrer', ($h['Referrer-Policy'] ?? '') === 'no-referrer');
check('Permissions-Policy отключает геолокацию', str_contains($h['Permissions-Policy'] ?? '', 'geolocation=()'));

echo "\nСтраницы\n";

$r = callPage('/');
check('GET / → 200', $r['status'] === 200, show(substr($r['html'], 0, 120)));
check('главная — это HTML', str_contains($r['headers']['Content-Type'] ?? '', 'text/html'));

$r = callPage('/privacy-terms');
check('GET /privacy-terms → 200', $r['status'] === 200);
check('политика упоминает анонимный аккаунт', str_contains($r['html'], 'anonymous account'));
check('политика описывает удаление данных', str_contains($r['html'], 'Delete All Flocks'));
check('политика содержит предупреждение о безопасности', str_contains($r['html'], 'kicks forwards'));
check('политика перечисляет сроки хранения', str_contains($r['html'], 'How long we keep it'));
check('CSP для HTML разрешает инлайновые стили', str_contains($r['headers']['Content-Security-Policy'] ?? '', "style-src 'unsafe-inline'"));
check('CSP для HTML ограничивает form-action', str_contains($r['headers']['Content-Security-Policy'] ?? '', "form-action 'self'"));

$r = callPage('/support-form');
check('GET /support-form → 200', $r['status'] === 200);
check('форма не кэшируется (выдаёт CSRF)', ($r['headers']['Cache-Control'] ?? '') === 'no-store');
check('в форме есть скрытое поле токена', str_contains($r['html'], 'name="_token"'));
check('в форме есть ловушка для ботов', str_contains($r['html'], 'name="website"'));

preg_match('/name="_token" value="([^"]+)"/', $r['html'], $m);
$csrf = $m[1] ?? '';
check('токен извлечён из формы', $csrf !== '');

echo "\nФорма поддержки\n";

$db = \RatiteRun\Api\Core\Database::instance();

// Записи прошлых прогонов иначе упираются в антиспам-потолок «5 обращений
// с адреса за час», и тест валит сам себя.
$db->run("DELETE FROM support_requests WHERE email LIKE '%@example.com'");

$c_db_count = static fn (): int => (int) $db->fetchValue('SELECT COUNT(*) FROM support_requests');
$c_db_last = static fn (): array => $db->fetchOne(
    'SELECT email, source, ip, user_id, app_version FROM support_requests ORDER BY created_at DESC, id DESC LIMIT 1',
) ?? [];

$valid = [
    '_token'  => $csrf,
    'name'    => 'Anna Keeper',
    'email'   => 'anna@example.com',
    'subject' => 'Something is broken',
    'message' => 'The fence check reminder fires at the wrong hour after I travel.',
];

$r = callForm('/support-form', $valid);                        // куки нет
check('отправка без куки CSRF → 403-экран', $r['status'] === 422 && str_contains($r['html'], 'session expired'), (string) $r['status']);

$r = callForm('/support-form', array_merge($valid, ['_token' => 'wrong']), ['rr_csrf' => $csrf]);
check('несовпадающий токен отвергнут', str_contains($r['html'], 'session expired'));

$r = callForm('/support-form', array_merge($valid, ['email' => 'not-an-email']), ['rr_csrf' => $csrf]);
check('кривой email → 422 с ошибкой у поля', $r['status'] === 422 && str_contains($r['html'], 'valid email'));
check('введённые данные не потеряны', str_contains($r['html'], 'Anna Keeper'));

$r = callForm('/support-form', array_merge($valid, ['message' => 'short']), ['rr_csrf' => $csrf]);
check('слишком короткое сообщение → 422', $r['status'] === 422 && str_contains($r['html'], 'at least 10 characters'));

$r = callForm('/support-form', array_merge($valid, ['website' => 'http://spam.example']), ['rr_csrf' => $csrf]);
check('ловушка: боту показан успех', $r['status'] === 200 && str_contains($r['html'], 'Message received'));

$before = (int) $c_db_count();
$r = callForm('/support-form', $valid, ['rr_csrf' => $csrf]);
check('валидная отправка → 200 с подтверждением', $r['status'] === 200 && str_contains($r['html'], 'Message received'), (string) $r['status']);
check('обращение записано в БД', $c_db_count() === $before + 1, 'до: ' . $before . ', после: ' . $c_db_count());
check('ловушка ничего не записала', $before === (int) $c_db_count() - 1);

$stored = $c_db_last();
check('поля сохранены верно', ($stored['email'] ?? '') === 'anna@example.com' && ($stored['source'] ?? '') === 'web', show($stored));
check('IP сохранён для антиспама', ($stored['ip'] ?? null) !== null);

echo "\nЛимиты\n";

// Потолок веб-формы — 10 отправок с адреса в час. Добиваем и проверяем отказ.
$tripped = false;
for ($i = 0; $i < 12; $i++) {
    $attempt = callForm('/support-form', array_merge($valid, [
        'message' => "Rate limit probe number {$i}, padded to pass validation.",
    ]), ['rr_csrf' => $csrf]);

    if (str_contains($attempt['html'], 'wait an hour') || $attempt['status'] === 429) {
        $tripped = true;
        break;
    }
}
check('форма упирается в лимит и отказывает', $tripped);

$db->run('DELETE FROM rate_limits');
$db->run("DELETE FROM support_requests WHERE email LIKE '%@example.com'");

echo "\nПоддержка из приложения\n";

$r = call('POST', '/v1/support', [
    'name'       => 'Anton',
    'email'      => 'anton@example.com',
    'subject'    => 'Feature request',
    'message'    => 'Please add weight charts for individual birds over time.',
    'appVersion' => '1.0',
    'deviceInfo' => 'iPhone15,2 / iOS 17.4',
]);
check('POST /v1/support → 201', $r['status'] === 201, show($r['body']));
check('вернулся id обращения', isset($r['body']['id']));

$stored = $c_db_last();
check('источник помечен как app', ($stored['source'] ?? '') === 'app');
check('обращение связано с пользователем', ($stored['user_id'] ?? null) !== null);
check('версия приложения сохранена', ($stored['app_version'] ?? '') === '1.0');

$r = call('POST', '/v1/support', ['message' => 'hi']);
check('пустая тема → 422', $r['status'] === 422, show($r['body']));

$saved = $accessToken;
$accessToken = null;
$r = call('POST', '/v1/support', $valid);
check('без токена /v1/support → 401', $r['status'] === 401);
$accessToken = $saved;

// ---------------------------------------------------------------------------

echo "\n" . str_repeat('─', 46) . "\n";
echo "Пройдено: {$passed}   Провалено: {$failed}\n";

exit($failed === 0 ? 0 : 1);
