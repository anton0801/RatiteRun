<?php

declare(strict_types=1);

/**
 * Разовая диагностика раскладки файлов на хостинге.
 *
 * Кладётся в public_html/ и открывается напрямую:
 *     https://ВАШ-ДОМЕН/whereami.php
 *
 * Показывает, где что лежит, и подсказывает нужную строку для .htaccess.
 * Содержимое .env не печатает. УДАЛИТЬ СРАЗУ ПОСЛЕ ПРОВЕРКИ.
 */

header('Content-Type: text/plain; charset=utf-8');
header('X-Robots-Tag: noindex, nofollow');

$here = __DIR__;

echo "RatiteRun — где что лежит\n";
echo str_repeat('=', 64), "\n\n";

printf("%-22s %s\n", 'Этот файл:', __FILE__);
printf("%-22s %s\n", 'Каталог:', $here);
printf("%-22s %s\n", 'DOCUMENT_ROOT:', (string) ($_SERVER['DOCUMENT_ROOT'] ?? '(не задан)'));
printf("%-22s %s\n", 'SCRIPT_NAME:', (string) ($_SERVER['SCRIPT_NAME'] ?? '?'));
printf("%-22s %s\n", 'PHP:', PHP_VERSION);
printf("%-22s %s\n", 'Сервер:', (string) ($_SERVER['SERVER_SOFTWARE'] ?? '?'));

$rewrite = function_exists('apache_get_modules')
    ? (in_array('mod_rewrite', apache_get_modules(), true) ? 'включён' : 'ВЫКЛЮЧЕН')
    : 'не определить (LiteSpeed/FastCGI — обычно работает)';
printf("%-22s %s\n", 'mod_rewrite:', $rewrite);

// ---------------------------------------------------------------------------

echo "\n", str_repeat('-', 64), "\n";
echo "ДЕРЕВО КАТАЛОГОВ (3 уровня)\n";
echo str_repeat('-', 64), "\n\n";

function tree(string $dir, string $prefix = '', int $depth = 0): void
{
    if ($depth > 2) {
        return;
    }

    $items = @scandir($dir);
    if ($items === false) {
        echo $prefix, "(нет доступа)\n";
        return;
    }

    $items = array_values(array_filter($items, static fn (string $i): bool => $i !== '.' && $i !== '..'));
    sort($items);

    // не разворачиваем каталоги с тысячами файлов
    $shown = array_slice($items, 0, 40);

    foreach ($shown as $index => $item) {
        $path = $dir . '/' . $item;
        $last = $index === count($shown) - 1;
        $branch = $last ? '└── ' : '├── ';

        if (is_dir($path)) {
            echo $prefix, $branch, $item, "/\n";
            tree($path, $prefix . ($last ? '    ' : '│   '), $depth + 1);
        } else {
            $size = @filesize($path);
            echo $prefix, $branch, $item, $size !== false ? '  (' . $size . ' б)' : '', "\n";
        }
    }

    if (count($items) > 40) {
        echo $prefix, '    … и ещё ', count($items) - 40, " шт.\n";
    }
}

tree($here);

// ---------------------------------------------------------------------------

echo "\n", str_repeat('-', 64), "\n";
echo "ПОИСК ТОЧКИ ВХОДА\n";
echo str_repeat('-', 64), "\n\n";

/** Ищем index.php, рядом с которым лежит ../src/Core/Kernel.php */
function findEntry(string $dir, int $depth = 0): ?string
{
    if ($depth > 3) {
        return null;
    }

    $candidate = $dir . '/index.php';
    if (is_file($candidate) && is_file(dirname($dir) . '/src/Core/Kernel.php')) {
        return $candidate;
    }

    foreach (@scandir($dir) ?: [] as $item) {
        if ($item === '.' || $item === '..' || !is_dir($dir . '/' . $item)) {
            continue;
        }
        $found = findEntry($dir . '/' . $item, $depth + 1);
        if ($found !== null) {
            return $found;
        }
    }

    return null;
}

$entry = findEntry($here);

if ($entry === null) {
    echo "[ !! ]  Точка входа не найдена.\n\n";
    echo "Ищется index.php, рядом с которым (на уровень выше) есть src/Core/Kernel.php.\n";
    echo "Проверьте, что загрузились каталоги public/ и src/, а не только часть файлов.\n";
} else {
    $relative = ltrim(str_replace($here, '', $entry), '/');
    $appDir = dirname(dirname($entry));

    echo "[ OK ]  Точка входа: ", $entry, "\n";
    echo "        Каталог приложения: ", $appDir, "\n\n";

    echo str_repeat('=', 64), "\n";
    echo "СТРОКА ДЛЯ .htaccess\n";
    echo str_repeat('=', 64), "\n\n";
    echo "  RewriteRule ^ ", $relative, " [QSA,L]\n\n";

    $appFolder = trim(str_replace($here, '', $appDir), '/');
    if ($appFolder === '') {
        echo "Каталог приложения совпадает с public_html.\n";
        echo "То есть src/, .env и storage/ лежат прямо в корне сайта —\n";
        echo "в правилах запрета надо указывать их поимённо, а не через 'api/'.\n";
    } else {
        echo "В правилах запрета вместо слова 'api' должно стоять: ", $appFolder, "\n";
    }

    echo "\nСоответствие ожидаемому:\n";
    printf("  %-28s %s\n", 'ожидалось', 'api/public/index.php');
    printf("  %-28s %s\n", 'фактически', $relative);
    echo '  ', $relative === 'api/public/index.php'
        ? "совпадает — дело не в пути\n"
        : "НЕ СОВПАДАЕТ — вот причина 404\n";

    echo "\nПроверка окружения приложения:\n";
    foreach ([
        '.env'                 => $appDir . '/.env',
        'src/Core/Kernel.php'  => $appDir . '/src/Core/Kernel.php',
        'storage/'             => $appDir . '/storage',
        'public/.htaccess'     => dirname($entry) . '/.htaccess',
    ] as $label => $path) {
        printf("  %-22s %s\n", $label, file_exists($path) ? 'есть' : 'НЕТ');
    }

    echo "\n  STORAGE_PATH=", $appDir, "/storage\n";
}

echo "\n", str_repeat('=', 64), "\n";
echo "УДАЛИТЕ ЭТОТ ФАЙЛ (whereami.php) ПОСЛЕ ПРОВЕРКИ.\n";
echo str_repeat('=', 64), "\n";
