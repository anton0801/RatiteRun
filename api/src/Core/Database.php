<?php

declare(strict_types=1);

namespace RatiteRun\Api\Core;

use PDO;
use PDOStatement;

/**
 * Тонкая обёртка над PDO/MySQL. Только подготовленные выражения.
 */
final class Database
{
    private static ?self $instance = null;
    private PDO $pdo;

    private function __construct()
    {
        $host = Config::get('DB_HOST', '127.0.0.1');
        $port = Config::int('DB_PORT', 3306);
        $name = Config::get('DB_NAME', 'ratiterun');
        $user = Config::get('DB_USER', 'root');
        $pass = Config::get('DB_PASS', '');

        $dsn = sprintf('mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4', $host, $port, $name);

        $this->pdo = new PDO($dsn, $user, $pass, [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
            PDO::ATTR_STRINGIFY_FETCHES  => false,
        ]);

        // Сервер работает в UTC, все DATETIME(3) — UTC.
        $this->pdo->exec("SET time_zone = '+00:00'");
    }

    public static function instance(): self
    {
        return self::$instance ??= new self();
    }

    public function pdo(): PDO
    {
        return $this->pdo;
    }

    /** @param array<string|int,mixed> $params */
    public function run(string $sql, array $params = []): PDOStatement
    {
        $stmt = $this->pdo->prepare($sql);
        $stmt->execute($params);

        return $stmt;
    }

    /**
     * @param array<string|int,mixed> $params
     * @return array<string,mixed>|null
     */
    public function fetchOne(string $sql, array $params = []): ?array
    {
        $row = $this->run($sql, $params)->fetch();

        return $row === false ? null : $row;
    }

    /**
     * @param array<string|int,mixed> $params
     * @return list<array<string,mixed>>
     */
    public function fetchAll(string $sql, array $params = []): array
    {
        /** @var list<array<string,mixed>> */
        return $this->run($sql, $params)->fetchAll();
    }

    /** @param array<string|int,mixed> $params */
    public function fetchValue(string $sql, array $params = []): mixed
    {
        $value = $this->run($sql, $params)->fetchColumn();

        return $value === false ? null : $value;
    }

    public function transaction(callable $fn): mixed
    {
        // вложенные транзакции не нужны — контроллер владеет одной
        if ($this->pdo->inTransaction()) {
            return $fn($this);
        }

        $this->pdo->beginTransaction();
        try {
            $result = $fn($this);
            $this->pdo->commit();

            return $result;
        } catch (\Throwable $e) {
            if ($this->pdo->inTransaction()) {
                $this->pdo->rollBack();
            }
            throw $e;
        }
    }
}
