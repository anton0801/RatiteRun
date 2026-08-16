<?php

declare(strict_types=1);

namespace RatiteRun\Api\Core;

/**
 * Минимальный PSR-4 автозагрузчик — composer не требуется.
 */
final class Autoloader
{
    public function __construct(
        private readonly string $prefix,
        private readonly string $baseDir,
    ) {
    }

    public static function register(string $prefix, string $baseDir): void
    {
        $loader = new self(rtrim($prefix, '\\') . '\\', rtrim($baseDir, '/') . '/');
        spl_autoload_register([$loader, 'load']);
    }

    public function load(string $class): void
    {
        if (!str_starts_with($class, $this->prefix)) {
            return;
        }

        $relative = substr($class, strlen($this->prefix));
        $file = $this->baseDir . str_replace('\\', '/', $relative) . '.php';

        if (is_file($file)) {
            require $file;
        }
    }
}
