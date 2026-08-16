<?php

declare(strict_types=1);

/**
 * Сквозная проверка развёрнутого API по HTTP.
 *
 * В отличие от bin/smoke.php, который дёргает ядро напрямую, этот скрипт
 * ходит на сервер по-настоящему — через веб-сервер, .htaccess, PHP-FPM и TLS.
 * То есть проверяет ровно то, что увидит приложение.
 *
 * Кладётся в public_html/ и открывается:
 *     https://ВАШ-ДОМЕН/api-check.php
 *
 * Создаёт временный анонимный аккаунт с тестовым стадом и удаляет их в конце.
 * Боевые данные не трогает.
 *
 * Требует нормальный веб-сервер: скрипт обращается к своему же серверу, а
 * встроенный `php -S` однопоточный и такой запрос обслужить не может.
 *
 * УДАЛИТЬ СРАЗУ ПОСЛЕ ПРОВЕРКИ.
 */

header('Content-Type: text/plain; charset=utf-8');
header('X-Robots-Tag: noindex, nofollow');
set_time_limit(120);

$scheme = (($_SERVER['HTTPS'] ?? '') !== '' && strtolower((string) $_SERVER['HTTPS']) !== 'off')
    || strtolower((string) ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '')) === 'https'
        ? 'https' : 'http';

$host = (string) ($_SERVER['HTTP_HOST'] ?? 'localhost');
$origin = $scheme . '://' . $host;

// Префикс, если приложение смонтировано в подкаталог
$basePath = rtrim(str_replace('\\', '/', dirname((string) ($_SERVER['SCRIPT_NAME'] ?? '/'))), '/');
if ($basePath === '/' || $basePath === '.') {
    $basePath = '';
}
$base = $origin . $basePath;

$passed = 0;
$failed = 0;
$notes = [];

function ok(string $label, bool $cond, string $extra = ''): bool
{
    global $passed, $failed;

    if ($cond) {
        $passed++;
        printf("  [OK]  %s\n", $label);
    } else {
        $failed++;
        printf("  [!!]  %s%s\n", $label, $extra !== '' ? '  — ' . $extra : '');
    }

    return $cond;
}

function note(string $text): void
{
    global $notes;
    $notes[] = $text;
}

/**
 * @param array<string,mixed>|null $body
 * @param array<string,string>     $headers
 * @return array{status:int,body:mixed,raw:string,headers:string}
 */
function req(string $method, string $path, ?array $body = null, ?string $token = null, array $headers = []): array
{
    global $base;

    $url = str_starts_with($path, 'http') ? $path : $base . $path;
    $raw = $body === null ? null : json_encode($body, JSON_UNESCAPED_UNICODE);

    $lines = ['Accept: application/json'];
    if ($raw !== null) {
        $lines[] = 'Content-Type: application/json';
    }
    if ($token !== null) {
        $lines[] = 'Authorization: Bearer ' . $token;
    }
    foreach ($headers as $name => $value) {
        $lines[] = $name . ': ' . $value;
    }

    if (function_exists('curl_init')) {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_CUSTOMREQUEST  => $method,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HEADER         => true,
            CURLOPT_TIMEOUT        => 20,
            CURLOPT_FOLLOWLOCATION => false,
            CURLOPT_HTTPHEADER     => $lines,
        ]);
        if ($raw !== null) {
            curl_setopt($ch, CURLOPT_POSTFIELDS, $raw);
        }

        $response = curl_exec($ch);
        $status = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        $headerSize = (int) curl_getinfo($ch, CURLINFO_HEADER_SIZE);
        // curl_close() с PHP 8.0 ничего не делает, а с 8.5 выдаёт Deprecated —
        // дескриптор освобождается сборщиком мусора сам.
        unset($ch);

        if ($response === false) {
            return ['status' => 0, 'body' => null, 'raw' => '', 'headers' => ''];
        }

        $headerBlob = substr((string) $response, 0, $headerSize);
        $payload = substr((string) $response, $headerSize);
    } else {
        $context = stream_context_create(['http' => [
            'method'        => $method,
            'header'        => implode("\r\n", $lines),
            'content'       => $raw,
            'timeout'       => 20,
            'ignore_errors' => true,
        ]]);
        $payload = @file_get_contents($url, false, $context);
        $headerBlob = implode("\n", $http_response_header ?? []);
        $status = 0;
        if (preg_match('#HTTP/\S+\s+(\d{3})#', $headerBlob, $m)) {
            $status = (int) $m[1];
        }
        $payload = $payload === false ? '' : $payload;
    }

    return [
        'status'  => $status,
        'body'    => json_decode((string) $payload, true),
        'raw'     => (string) $payload,
        'headers' => $headerBlob,
    ];
}

// ---------------------------------------------------------------------------

echo "RatiteRun — проверка развёрнутого API\n";
echo str_repeat('=', 64), "\n";
echo "Адрес: ", $base, "\n";
echo "Схема: ", $scheme, ($scheme === 'http' ? "  <- открыто по HTTP, см. замечания ниже" : ''), "\n";
echo str_repeat('=', 64), "\n\n";

// -- 1. Доступность ---------------------------------------------------------

echo "ДОСТУПНОСТЬ\n";

$r = req('GET', '/v1/health');
$healthOk = ok('GET /v1/health отвечает', $r['status'] === 200, 'код ' . $r['status']);

if (!$healthOk) {
    echo "\n";
    echo "Дальше проверять нечего — приложение не отвечает.\n";
    echo "Ответ сервера:\n", substr($r['raw'], 0, 500), "\n";
    exit(1);
}

ok('база данных подключена', ($r['body']['database'] ?? false) === true, 'проверьте DB_* в .env');

// -- 2. Справочники ---------------------------------------------------------

echo "\nСПРАВОЧНИКИ\n";

$r = req('GET', '/v1/species-presets');
$presets = $r['body']['data'] ?? [];
ok('GET /v1/species-presets', $r['status'] === 200, 'код ' . $r['status']);
ok('загружены все три вида', count($presets) === 3, 'найдено ' . count($presets) . ' — импортируйте install.sql');

$ostrich = null;
foreach ($presets as $p) {
    if (($p['species'] ?? '') === 'ostrich') {
        $ostrich = $p;
    }
}
ok('нормативы осмысленные (страус: 300 м²/птица)', ($ostrich['spacePerBirdM2'] ?? 0) == 300.0);

$r = req('GET', '/v1/content/disclaimer');
ok('GET /v1/content/disclaimer', $r['status'] === 200 && str_contains((string) ($r['body']['body'] ?? ''), 'kick'));

// -- 3. Страницы ------------------------------------------------------------

echo "\nСТРАНИЦЫ\n";

foreach ([['/', 'главная'], ['/privacy-terms', 'политика'], ['/support-form', 'форма поддержки']] as [$path, $label]) {
    $r = req('GET', $path);
    ok("{$label} ({$path})", $r['status'] === 200 && str_contains($r['raw'], '<html'), 'код ' . $r['status']);
}

// -- 4. Защита файлов -------------------------------------------------------

echo "\nЗАЩИТА ФАЙЛОВ\n";

foreach ([
    '/.env'          => '.env',
    '/install.sql'   => 'дамп базы',
    '/src/Core/Kernel.php' => 'исходники',
    '/storage/'      => 'каталог storage',
] as $path => $label) {
    $r = req('GET', $path);
    $blocked = in_array($r['status'], [403, 404], true);
    ok("{$label} закрыт ({$path})", $blocked, 'код ' . $r['status'] . ' — ФАЙЛ ОТДАЁТСЯ!');

    if (!$blocked && str_contains($r['raw'], 'DB_PASS')) {
        note('КРИТИЧНО: ' . $path . ' отдаёт пароль от базы. Проверьте .htaccess немедленно.');
    }
}

// -- 5. Авторизация ---------------------------------------------------------

echo "\nАВТОРИЗАЦИЯ\n";

$r = req('GET', '/v1/flocks');
ok('без токена /v1/flocks отдаёт 401', $r['status'] === 401, 'код ' . $r['status']);

$deviceId = 'CHECK-' . bin2hex(random_bytes(8));
$r = req('POST', '/v1/auth/anonymous', ['deviceId' => $deviceId, 'platform' => 'ios']);
$token = $r['body']['accessToken'] ?? null;
$authOk = ok('анонимный вход выдал токен', is_string($token), 'код ' . $r['status'] . ' ' . substr($r['raw'], 0, 200));

if (!$authOk) {
    echo "\nБез токена остальное не проверить.\n";
    echo "Чаще всего причина — JWT_SECRET короче 32 символов или не задан.\n";
    exit(1);
}

$r = req('GET', '/v1/me', null, $token);
ok('GET /v1/me с токеном', $r['status'] === 200);

$r = req('GET', '/v1/flocks', null, 'явно.негодный.токен');
ok('негодный токен отвергнут', $r['status'] === 401);

// -- 6. Запись и движки -----------------------------------------------------

echo "\nЗАПИСЬ И РАСЧЁТЫ\n";

$flockId = null;

$r = req('POST', '/v1/flocks', [
    'title' => 'Проверка развёртывания', 'species' => 'emu', 'count' => 6, 'priority' => 'low',
], $token);
$flockId = $r['body']['id'] ?? null;
ok('создание стада', $r['status'] === 201 && is_string($flockId), 'код ' . $r['status'] . ' ' . substr($r['raw'], 0, 200));

if (is_string($flockId)) {
    $r = req('PUT', "/v1/flocks/{$flockId}/housing", ['paddockSize' => 1500, 'hasShelter' => true], $token);
    ok('запись секции housing', $r['status'] === 200, 'код ' . $r['status']);

    $r = req('PUT', "/v1/flocks/{$flockId}/fencing", ['height' => 1.8, 'strength' => 4, 'perimeterSecured' => true], $token);
    ok('запись секции fencing', $r['status'] === 200);

    $r = req('PUT', "/v1/flocks/{$flockId}/fencing", ['strength' => 99], $token);
    ok('неверное значение отвергнуто (422)', $r['status'] === 422, 'код ' . $r['status']);

    $r = req('GET', "/v1/flocks/{$flockId}/readiness", null, $token);
    $percent = $r['body']['percent'] ?? -1;
    ok('движок готовности посчитал', $r['status'] === 200 && $percent > 0, 'получено ' . $percent);
    ok('расчёт правдоподобный (250 м²/птица → высокий процент)', $percent >= 60, 'получено ' . $percent . '%');

    $r = req('POST', "/v1/flocks/{$flockId}/birds", ['birdId' => 'CHK-01', 'weightKg' => 38, 'heightCm' => 165], $token);
    ok('добавление записи о птице', $r['status'] === 201);

    // Отчёт заодно проверяет, что STORAGE_PATH доступен на запись
    $r = req('POST', "/v1/flocks/{$flockId}/reports", ['sections' => ['spaceFence', 'safety'], 'notes' => 'проверка'], $token);
    $reportId = $r['body']['id'] ?? null;
    $reportOk = ok('генерация PDF-отчёта', $r['status'] === 201 && is_string($reportId), 'код ' . $r['status'] . ' ' . substr($r['raw'], 0, 200));

    if (!$reportOk) {
        note('Отчёт не собрался — чаще всего STORAGE_PATH указывает не туда или каталог недоступен на запись (chmod 775).');
    }

    if (is_string($reportId)) {
        $r = req('GET', "/v1/reports/{$reportId}/pdf", null, $token);
        ok('PDF скачивается и это настоящий PDF', $r['status'] === 200 && str_starts_with($r['raw'], '%PDF'));
    }

    $r = req('GET', "/v1/flocks/{$flockId}", null, $token);
    ok('чтение стада целиком', $r['status'] === 200 && ($r['body']['housing']['paddockSize'] ?? 0) == 1500);
    ok('ETag выдаётся (нужен для блокировок)', str_contains(strtolower($r['headers']), 'etag:'));
}

// -- 7. Безопасность транспорта ---------------------------------------------

echo "\nБЕЗОПАСНОСТЬ\n";

$r = req('GET', '/v1/health');
$h = strtolower($r['headers']);
ok('заголовок X-Content-Type-Options', str_contains($h, 'x-content-type-options'));
ok('заголовок Content-Security-Policy', str_contains($h, 'content-security-policy'));

if ($scheme === 'https') {
    ok('HSTS включён', str_contains($h, 'strict-transport-security'), 'нет заголовка — проверьте FORCE_HTTPS=true');

    $r = req('GET', 'http://' . $host . $basePath . '/v1/health');
    $refused = $r['status'] === 0 || $r['status'] === 403 || ($r['status'] >= 300 && $r['status'] < 400);
    ok('незашифрованный HTTP отвергается', $refused, 'код ' . $r['status'] . ' — FORCE_HTTPS выключен!');
} else {
    note('Скрипт открыт по HTTP, поэтому TLS проверить нельзя. Откройте его по https://');
}

// -- 8. Уборка --------------------------------------------------------------

echo "\nУБОРКА\n";

if (is_string($flockId)) {
    $r = req('DELETE', "/v1/flocks/{$flockId}", null, $token);
    ok('тестовое стадо удалено', $r['status'] === 204, 'код ' . $r['status']);
}

$r = req('DELETE', '/v1/me', null, $token);
ok('тестовый аккаунт удалён', $r['status'] === 204, 'код ' . $r['status']);

// ---------------------------------------------------------------------------

echo "\n", str_repeat('=', 64), "\n";
printf("Пройдено: %d   Провалено: %d\n", $passed, $failed);

if ($notes !== []) {
    echo "\nЗАМЕЧАНИЯ\n";
    foreach ($notes as $n) {
        echo "  * ", $n, "\n";
    }
}

echo "\n";
echo $failed === 0
    ? "API развёрнут и работает. Можно подключать приложение.\n"
    : "Есть проблемы — см. строки с [!!] выше.\n";

echo "\n", str_repeat('=', 64), "\n";
echo "УДАЛИТЕ ЭТОТ ФАЙЛ (api-check.php) ПОСЛЕ ПРОВЕРКИ.\n";
echo str_repeat('=', 64), "\n";
