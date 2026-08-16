<?php

declare(strict_types=1);

use RatiteRun\Api\Core\ApiException;
use RatiteRun\Api\Core\Autoloader;
use RatiteRun\Api\Core\Config;
use RatiteRun\Api\Core\Kernel;
use RatiteRun\Api\Core\Request;
use RatiteRun\Api\Core\Response;

require __DIR__ . '/../src/Core/Autoloader.php';

Autoloader::register('RatiteRun\\Api', __DIR__ . '/../src');
Config::load(__DIR__ . '/../.env');

// Ошибки уходят в лог, наружу — только problem+json.
ini_set('display_errors', '0');
ini_set('log_errors', '1');
error_reporting(E_ALL);

// Сессии PHP не используются — токены передаются в заголовке.
ini_set('session.use_cookies', '0');

header_remove('X-Powered-By');

$request = Request::fromGlobals();

try {
    // Слабый или незаданный секрет обесценивает всю подпись токенов,
    // поэтому сервис не должен подниматься с таким конфигом вообще.
    $secret = Config::get('JWT_SECRET', '');
    if ($secret === null || strlen($secret) < 32) {
        error_log('[ratiterun] JWT_SECRET is missing or shorter than 32 characters');
        throw ApiException::internal('The server is not configured correctly.');
    }

    $response = (new Kernel())->handle($request);
} catch (ApiException $e) {
    $response = Response::problem($e, $request->path);
} catch (Throwable $e) {
    error_log(sprintf(
        '[ratiterun] %s: %s in %s:%d',
        $e::class,
        $e->getMessage(),
        $e->getFile(),
        $e->getLine(),
    ));

    $detail = Config::bool('APP_DEBUG', false)
        ? $e->getMessage() . ' @ ' . $e->getFile() . ':' . $e->getLine()
        : 'An unexpected error occurred.';

    $response = Response::problem(ApiException::internal($detail), $request->path);
}

$response->send();
