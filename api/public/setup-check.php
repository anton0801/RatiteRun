<?php

declare(strict_types=1);

/**
 * Разовая диагностика размещения на хостинге.
 *
 * Открыть в браузере, переписать подсказанные значения в .env — и УДАЛИТЬ ФАЙЛ.
 * Секретов не печатает: только длину и факт наличия.
 */

header('Content-Type: text/plain; charset=utf-8');
header('X-Robots-Tag: noindex, nofollow');

$publicDir = __DIR__;
$appDir    = dirname($publicDir);
$docRoot   = rtrim((string) ($_SERVER['DOCUMENT_ROOT'] ?? ''), '/');
$scriptName = (string) ($_SERVER['SCRIPT_NAME'] ?? '');

function line(string $label, string $value): void
{
    printf("%-26s %s\n", $label . ':', $value);
}

function verdict(bool $ok, string $good, string $bad): string
{
    return ($ok ? '[ OK ]  ' : '[ !! ]  ') . ($ok ? $good : $bad);
}

echo "RatiteRun — проверка размещения\n";
echo str_repeat('=', 62), "\n\n";

// -- где мы лежим -----------------------------------------------------------

echo "РАЗМЕЩЕНИЕ\n\n";
line('Каталог public', $publicDir);
line('Каталог приложения', $appDir);
line('DOCUMENT_ROOT', $docRoot === '' ? '(не задан)' : $docRoot);
line('SCRIPT_NAME', $scriptName);

// API_BASE_PATH — префикс, на который смещены все адреса.
// Вычисляется из пути к этому файлу: /setup-check.php -> ''
//                                    /api/setup-check.php -> '/api'
$basePath = rtrim(str_replace('\\', '/', dirname($scriptName)), '/');
if ($basePath === '/' || $basePath === '.') {
    $basePath = '';
}

echo "\n";
echo str_repeat('-', 62), "\n";
echo "ЗНАЧЕНИЯ ДЛЯ .env\n";
echo str_repeat('-', 62), "\n\n";

echo "API_BASE_PATH=", $basePath, "\n";
if ($basePath === '') {
    echo "  (пусто — приложение в корне домена, это правильный вариант)\n";
} else {
    echo "  ВНИМАНИЕ: приложение лежит в подкаталоге '{$basePath}'.\n";
    echo "  Работать будет, но адреса станут вида:\n";
    echo "    https://ВАШ-ДОМЕН{$basePath}/v1/flocks\n";
    echo "    https://ВАШ-ДОМЕН{$basePath}/privacy-terms\n";
    echo "  Тогда RatiteAPIBaseURL в приложении надо править под этот путь.\n";
    echo "  Лучше настроить корень домена прямо на каталог public.\n";
}

// STORAGE_PATH — вне docroot, иначе фото и PDF станут публичными
$suggestedStorage = $appDir . '/storage';
$storageOutsideDocroot = $docRoot === '' || !str_starts_with($suggestedStorage, $docRoot . '/');

echo "\nSTORAGE_PATH=", $suggestedStorage, "\n";
if ($storageOutsideDocroot) {
    echo "  (вне корня сайта — правильно)\n";
} else {
    echo "  ВНИМАНИЕ: этот каталог внутри корня сайта.\n";
    echo "  Фото стад и PDF-отчёты станут доступны по прямой ссылке без авторизации.\n";
    echo "  Перенесите каталог приложения выше корня либо закройте storage через .htaccess.\n";
}

echo "\nAPP_HOST=", (string) ($_SERVER['HTTP_HOST'] ?? 'ВАШ-ДОМЕН'), "\n";

echo "\n";
echo str_repeat('-', 62), "\n";
echo "ПРОВЕРКИ\n";
echo str_repeat('-', 62), "\n\n";

// -- .env не должен читаться из браузера ------------------------------------

$envPath = $appDir . '/.env';
$envInDocroot = $docRoot !== '' && str_starts_with($envPath, $docRoot . '/');

echo verdict(
    !$envInDocroot,
    ".env лежит вне корня сайта",
    ".env ВНУТРИ корня сайта — вероятно, читается по HTTP. Это доступ ко всей базе."
), "\n";

if ($envInDocroot) {
    $guess = str_replace($docRoot, '', $envPath);
    echo "        Проверьте вручную: https://ВАШ-ДОМЕН{$guess}\n";
    echo "        Если открылся текст — немедленно перенесите приложение выше корня.\n";
}

echo verdict(is_file($envPath), '.env найден', ".env не найден по пути {$envPath}"), "\n";

// -- каталоги хранения -------------------------------------------------------

foreach (['photos', 'reports'] as $sub) {
    $dir = $suggestedStorage . '/' . $sub;
    if (!is_dir($dir)) {
        @mkdir($dir, 0775, true);
    }
    echo verdict(
        is_dir($dir) && is_writable($dir),
        "storage/{$sub} существует и доступен на запись",
        "storage/{$sub} недоступен на запись — chmod 775 на каталог storage"
    ), "\n";
}

// -- PHP ---------------------------------------------------------------------

echo "\n";
line('PHP', PHP_VERSION);
echo verdict(PHP_VERSION_ID >= 80100, 'версия подходит (нужен 8.1+)', 'НУЖЕН PHP 8.1 или новее'), "\n";

foreach (['pdo_mysql', 'json', 'mbstring', 'openssl', 'gd'] as $ext) {
    echo verdict(extension_loaded($ext), "расширение {$ext}", "НЕТ расширения {$ext}"), "\n";
}

// -- база --------------------------------------------------------------------

echo "\n";

$env = [];
if (is_file($envPath)) {
    foreach (file($envPath, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $l) {
        $l = trim($l);
        if ($l === '' || str_starts_with($l, '#') || !str_contains($l, '=')) {
            continue;
        }
        [$k, $v] = explode('=', $l, 2);
        $env[trim($k)] = trim($v);
    }
}

try {
    $pdo = new PDO(
        sprintf(
            'mysql:host=%s;port=%s;dbname=%s;charset=utf8mb4',
            $env['DB_HOST'] ?? '127.0.0.1',
            $env['DB_PORT'] ?? '3306',
            $env['DB_NAME'] ?? ''
        ),
        $env['DB_USER'] ?? '',
        $env['DB_PASS'] ?? '',
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );

    echo verdict(true, 'подключение к базе есть', ''), "\n";
    line('  СУБД', (string) $pdo->query('SELECT VERSION()')->fetchColumn());

    $tables = (int) $pdo->query(
        'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE()'
    )->fetchColumn();
    echo verdict($tables === 15, "таблиц: {$tables}", "таблиц: {$tables}, ожидалось 15 — импортируйте install.sql"), "\n";

    if ($tables > 0) {
        $species = (int) $pdo->query('SELECT COUNT(*) FROM species_presets')->fetchColumn();
        echo verdict($species === 3, "нормативы по видам загружены ({$species})", "нормативов {$species}, ожидалось 3 — движки оценки не заработают"), "\n";

        $fk = (int) $pdo->query(
            'SELECT COUNT(*) FROM information_schema.referential_constraints WHERE constraint_schema = DATABASE()'
        )->fetchColumn();
        echo verdict($fk === 10, "внешних ключей: {$fk}", "внешних ключей {$fk}, ожидалось 10 — импорт прошёл не полностью"), "\n";
    }
} catch (Throwable $e) {
    echo verdict(false, '', 'нет подключения к базе: ' . $e->getMessage()), "\n";
}

// -- боевые настройки --------------------------------------------------------

echo "\n";
echo str_repeat('-', 62), "\n";
echo "БОЕВЫЕ НАСТРОЙКИ\n";
echo str_repeat('-', 62), "\n\n";

$secret = $env['JWT_SECRET'] ?? '';
$secretOk = strlen($secret) >= 32 && !str_contains($secret, 'dev_only');
echo verdict(
    $secretOk,
    'JWT_SECRET задан (' . strlen($secret) . ' символов)',
    strlen($secret) < 32
        ? 'JWT_SECRET короче 32 символов — сервис не запустится'
        : 'JWT_SECRET всё ещё отладочный — ЗАМЕНИТЕ, иначе токены подделываются'
), "\n";

foreach ([
    'APP_DEBUG'              => ['false', 'выключён', 'ВКЛЮЧЁН — тексты ошибок и пути уедут клиенту'],
    'FORCE_HTTPS'            => ['true',  'включён',  'ВЫКЛЮЧЕН — приложение примет незашифрованные соединения'],
    'ALLOW_INSECURE_COOKIES' => ['false', 'выключены', 'ВКЛЮЧЕНЫ — CSRF-кука уйдёт без флага Secure'],
] as $key => [$expected, $good, $bad]) {
    $actual = strtolower($env[$key] ?? '');
    echo verdict($actual === $expected, "{$key} {$good}", "{$key}: {$bad}"), "\n";
}

echo "\nЕсли нужен новый JWT_SECRET, вот готовый:\n";
echo '  JWT_SECRET=', bin2hex(random_bytes(32)), "\n";

echo "\n", str_repeat('=', 62), "\n";
echo "УДАЛИТЕ ЭТОТ ФАЙЛ (public/setup-check.php) СРАЗУ ПОСЛЕ ПРОВЕРКИ.\n";
echo str_repeat('=', 62), "\n";
