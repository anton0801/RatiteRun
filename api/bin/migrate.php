<?php

declare(strict_types=1);

use RatiteRun\Api\Core\Autoloader;
use RatiteRun\Api\Core\Config;
use RatiteRun\Api\Core\Database;

require __DIR__ . '/../src/Core/Autoloader.php';

Autoloader::register('RatiteRun\\Api', __DIR__ . '/../src');
Config::load(__DIR__ . '/../.env');

$db = Database::instance();

$db->run(
    'CREATE TABLE IF NOT EXISTS schema_migrations (
        filename   VARCHAR(191) NOT NULL,
        applied_at DATETIME(3)  NOT NULL,
        PRIMARY KEY (filename)
     ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4',
);

$applied = array_column(
    $db->fetchAll('SELECT filename FROM schema_migrations'),
    'filename',
);

$files = glob(__DIR__ . '/../migrations/*.sql') ?: [];
sort($files);

$ran = 0;

foreach ($files as $file) {
    $name = basename($file);
    if (in_array($name, $applied, true)) {
        continue;
    }

    echo "→ {$name}\n";

    $sql = file_get_contents($file);
    if ($sql === false) {
        fwrite(STDERR, "Could not read {$name}\n");
        exit(1);
    }

    try {
        // выражения разделены точкой с запятой в конце строки;
        // строки-комментарии вырезаются, иначе они «съедают» следующий за ними DDL
        foreach (preg_split('/;\s*\n/', $sql) ?: [] as $chunk) {
            $lines = array_filter(
                explode("\n", $chunk),
                static fn (string $line): bool => !str_starts_with(ltrim($line), '--'),
            );

            $statement = trim(implode("\n", $lines));
            if ($statement === '') {
                continue;
            }

            $db->pdo()->exec($statement);
        }

        $db->run(
            'INSERT INTO schema_migrations (filename, applied_at) VALUES (?, UTC_TIMESTAMP(3))',
            [$name],
        );
        $ran++;
    } catch (Throwable $e) {
        fwrite(STDERR, "✗ {$name}: {$e->getMessage()}\n");
        exit(1);
    }
}

echo $ran === 0 ? "Nothing to migrate.\n" : "Applied {$ran} migration(s).\n";
