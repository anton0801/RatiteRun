<?php

declare(strict_types=1);

/**
 * Периодическая уборка. Ставить в cron раз в сутки:
 *   0 4 * * * php /var/www/ratiterun/api/bin/cleanup.php
 */

use RatiteRun\Api\Core\Autoloader;
use RatiteRun\Api\Core\Config;
use RatiteRun\Api\Core\Container;

require __DIR__ . '/../src/Core/Autoloader.php';

Autoloader::register('RatiteRun\\Api', __DIR__ . '/../src');
Config::load(__DIR__ . '/../.env');

$c = new Container();

$tokens = $c->tokens()->purgeExpired();
echo "Refresh tokens removed: {$tokens}\n";

$idem = $c->idempotency()->purge();
echo "Idempotency keys removed: {$idem}\n";

$rates = $c->rateLimiter()->purge();
echo "Rate-limit windows removed: {$rates}\n";

$storage = rtrim(Config::get('STORAGE_PATH', dirname(__DIR__) . '/storage') ?? '', '/');
$reportKeys = $c->reports()->purgeExpired();
foreach ($reportKeys as $key) {
    @unlink($storage . '/reports/' . $key);
}
echo 'Expired reports removed: ' . count($reportKeys) . "\n";

// Срок хранения объявлен в политике конфиденциальности — 90 дней.
$anonymised = $c->support()->purgeOldIpAddresses();
echo "Support requests anonymised: {$anonymised}\n";
