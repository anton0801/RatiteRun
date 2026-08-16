<?php

declare(strict_types=1);

namespace RatiteRun\Api\Service;

use RatiteRun\Api\Core\ApiException;
use RatiteRun\Api\Core\Config;
use RatiteRun\Api\Core\Uuid;

/**
 * Хранение фото стада на диске.
 *
 * Загруженный файл всегда пересобирается через GD: это отбрасывает EXIF
 * и любую полезную нагрузку, спрятанную в картинке, и заодно ограничивает
 * размер. В БД хранится только ключ.
 */
final class PhotoStorage
{
    private const MAX_BYTES     = 12 * 1024 * 1024;
    private const MAX_DIMENSION = 1600;
    private const JPEG_QUALITY  = 82;

    private readonly string $root;

    public function __construct()
    {
        $this->root = rtrim(Config::get('STORAGE_PATH', dirname(__DIR__, 2) . '/storage') ?? '', '/');
    }

    /**
     * @param array<string,mixed> $file элемент $_FILES
     * @return string ключ для колонки photo_key
     */
    public function store(string $flockId, array $file): string
    {
        $error = $file['error'] ?? UPLOAD_ERR_NO_FILE;
        if ($error === UPLOAD_ERR_INI_SIZE || $error === UPLOAD_ERR_FORM_SIZE) {
            throw ApiException::payloadTooLarge('Photo exceeds the maximum upload size.');
        }
        if ($error !== UPLOAD_ERR_OK) {
            throw ApiException::badRequest('Photo upload failed (code ' . $error . ').');
        }

        $tmpPath = $file['tmp_name'] ?? null;
        if (!is_string($tmpPath) || !is_uploaded_file($tmpPath)) {
            throw ApiException::badRequest('No uploaded photo found in the request.');
        }

        $size = (int) ($file['size'] ?? 0);
        if ($size > self::MAX_BYTES) {
            throw ApiException::payloadTooLarge(
                'Photo must be at most ' . (int) (self::MAX_BYTES / 1024 / 1024) . ' MB.',
            );
        }

        $info = @getimagesize($tmpPath);
        if ($info === false) {
            throw ApiException::unsupportedMediaType('Uploaded file is not a readable image.');
        }

        [$width, $height, $type] = $info;

        $image = match ($type) {
            IMAGETYPE_JPEG => @imagecreatefromjpeg($tmpPath),
            IMAGETYPE_PNG  => @imagecreatefrompng($tmpPath),
            IMAGETYPE_WEBP => @imagecreatefromwebp($tmpPath),
            default        => throw ApiException::unsupportedMediaType('Photo must be JPEG, PNG or WebP.'),
        };

        if ($image === false) {
            throw ApiException::unsupportedMediaType('Photo could not be decoded.');
        }

        try {
            $scale = min(1.0, self::MAX_DIMENSION / max($width, $height));
            if ($scale < 1.0) {
                $resized = imagescale($image, (int) round($width * $scale), (int) round($height * $scale));
                if ($resized !== false) {
                    imagedestroy($image);
                    $image = $resized;
                }
            }

            $dir = $this->directory($flockId);
            if (!is_dir($dir) && !mkdir($dir, 0775, true) && !is_dir($dir)) {
                throw ApiException::internal('Could not create photo storage directory.');
            }

            $key = $flockId . '/' . Uuid::v4() . '.jpg';
            $path = $this->root . '/photos/' . $key;

            if (!imagejpeg($image, $path, self::JPEG_QUALITY)) {
                throw ApiException::internal('Could not write photo to storage.');
            }

            // старые версии фото этого стада больше не нужны
            $this->pruneExcept($flockId, basename($key));

            return $key;
        } finally {
            if ($image instanceof \GdImage) {
                imagedestroy($image);
            }
        }
    }

    public function read(string $key): string
    {
        $path = $this->pathFor($key);

        $data = @file_get_contents($path);
        if ($data === false) {
            throw ApiException::notFound('Photo not found.');
        }

        return $data;
    }

    public function delete(?string $key): void
    {
        if ($key === null || $key === '') {
            return;
        }

        @unlink($this->pathFor($key));
    }

    /** Защита от выхода за пределы каталога хранения. */
    private function pathFor(string $key): string
    {
        if (str_contains($key, '..') || str_starts_with($key, '/')) {
            throw ApiException::notFound('Photo not found.');
        }

        return $this->root . '/photos/' . $key;
    }

    private function directory(string $flockId): string
    {
        return $this->root . '/photos/' . $flockId;
    }

    private function pruneExcept(string $flockId, string $keepFilename): void
    {
        $dir = $this->directory($flockId);
        foreach (glob($dir . '/*.jpg') ?: [] as $file) {
            if (basename($file) !== $keepFilename) {
                @unlink($file);
            }
        }
    }
}
