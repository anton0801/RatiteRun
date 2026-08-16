<?php

declare(strict_types=1);

namespace RatiteRun\Api\Core;

use RatiteRun\Api\Repository\AuditRepository;
use RatiteRun\Api\Repository\BirdRecordRepository;
use RatiteRun\Api\Repository\FlockRepository;
use RatiteRun\Api\Repository\IdempotencyStore;
use RatiteRun\Api\Repository\LayoutRepository;
use RatiteRun\Api\Repository\PresetRepository;
use RatiteRun\Api\Repository\RateLimiter;
use RatiteRun\Api\Repository\ReminderRepository;
use RatiteRun\Api\Repository\ReportRepository;
use RatiteRun\Api\Repository\SupportRepository;
use RatiteRun\Api\Repository\TokenRepository;
use RatiteRun\Api\Repository\UserRepository;
use RatiteRun\Api\Service\PhotoStorage;
use RatiteRun\Api\Service\ReportService;

/**
 * Ленивая сборка зависимостей. Полноценный DI-контейнер здесь избыточен.
 */
final class Container
{
    /** @var array<string,object> */
    private array $instances = [];

    public function db(): Database
    {
        return Database::instance();
    }

    public function users(): UserRepository
    {
        return $this->make(UserRepository::class, fn (): UserRepository => new UserRepository($this->db()));
    }

    public function tokens(): TokenRepository
    {
        return $this->make(TokenRepository::class, fn (): TokenRepository => new TokenRepository($this->db()));
    }

    public function presets(): PresetRepository
    {
        return $this->make(PresetRepository::class, fn (): PresetRepository => new PresetRepository($this->db()));
    }

    public function flocks(): FlockRepository
    {
        return $this->make(
            FlockRepository::class,
            fn (): FlockRepository => new FlockRepository($this->db(), $this->presets()),
        );
    }

    public function birds(): BirdRecordRepository
    {
        return $this->make(BirdRecordRepository::class, fn (): BirdRecordRepository => new BirdRecordRepository($this->db()));
    }

    public function reminders(): ReminderRepository
    {
        return $this->make(ReminderRepository::class, fn (): ReminderRepository => new ReminderRepository($this->db()));
    }

    public function layout(): LayoutRepository
    {
        return $this->make(LayoutRepository::class, fn (): LayoutRepository => new LayoutRepository($this->db()));
    }

    public function reports(): ReportRepository
    {
        return $this->make(ReportRepository::class, fn (): ReportRepository => new ReportRepository($this->db()));
    }

    public function support(): SupportRepository
    {
        return $this->make(SupportRepository::class, fn (): SupportRepository => new SupportRepository($this->db()));
    }

    public function audit(): AuditRepository
    {
        return $this->make(AuditRepository::class, fn (): AuditRepository => new AuditRepository($this->db()));
    }

    public function rateLimiter(): RateLimiter
    {
        return $this->make(RateLimiter::class, fn (): RateLimiter => new RateLimiter($this->db()));
    }

    public function idempotency(): IdempotencyStore
    {
        return $this->make(IdempotencyStore::class, fn (): IdempotencyStore => new IdempotencyStore($this->db()));
    }

    public function photos(): PhotoStorage
    {
        return $this->make(PhotoStorage::class, fn (): PhotoStorage => new PhotoStorage());
    }

    public function reportService(): ReportService
    {
        return $this->make(ReportService::class, fn (): ReportService => new ReportService());
    }

    /** @template T of object @param callable():T $factory @return T */
    private function make(string $key, callable $factory): object
    {
        /** @var T */
        return $this->instances[$key] ??= $factory();
    }
}
