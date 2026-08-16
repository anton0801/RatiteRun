<?php

declare(strict_types=1);

namespace RatiteRun\Api\Core;

/**
 * Собирает все ошибки валидации разом, а не падает на первой.
 *
 * Отсутствующее поле не ошибка — это нужно для PATCH/частичных апдейтов.
 * Обязательность задаётся явно через required*().
 */
final class Validator
{
    /** @var array<string,list<string>> */
    private array $errors = [];

    /** @param array<string,mixed> $input */
    public function __construct(private readonly array $input)
    {
    }

    public function has(string $key): bool
    {
        return array_key_exists($key, $this->input);
    }

    public function raw(string $key): mixed
    {
        return $this->input[$key] ?? null;
    }

    private function fail(string $key, string $message): void
    {
        $this->errors[$key][] = $message;
    }

    // -- строки ---------------------------------------------------------------

    public function string(string $key, int $maxLength = 255, bool $allowEmpty = true): ?string
    {
        if (!$this->has($key)) {
            return null;
        }

        $value = $this->input[$key];
        if ($value === null) {
            return $allowEmpty ? '' : null;
        }
        if (!is_string($value)) {
            $this->fail($key, 'Must be a string.');

            return null;
        }

        $value = trim($value);
        if (!$allowEmpty && $value === '') {
            $this->fail($key, 'Must not be empty.');

            return null;
        }
        if (mb_strlen($value) > $maxLength) {
            $this->fail($key, "Must be at most {$maxLength} characters.");

            return null;
        }

        return $value;
    }

    public function requiredString(string $key, int $maxLength = 255): ?string
    {
        if (!$this->has($key)) {
            $this->fail($key, 'Is required.');

            return null;
        }

        return $this->string($key, $maxLength, allowEmpty: false);
    }

    // -- числа ----------------------------------------------------------------

    public function int(string $key, int $min, int $max): ?int
    {
        if (!$this->has($key)) {
            return null;
        }

        $value = $this->input[$key];
        if (is_bool($value) || !is_numeric($value)) {
            $this->fail($key, 'Must be an integer.');

            return null;
        }

        $int = (int) $value;
        if ($int < $min || $int > $max) {
            $this->fail($key, "Must be between {$min} and {$max}.");

            return null;
        }

        return $int;
    }

    public function requiredInt(string $key, int $min, int $max): ?int
    {
        if (!$this->has($key)) {
            $this->fail($key, 'Is required.');

            return null;
        }

        return $this->int($key, $min, $max);
    }

    public function float(string $key, float $min, float $max): ?float
    {
        if (!$this->has($key)) {
            return null;
        }

        $value = $this->input[$key];
        if (is_bool($value) || !is_numeric($value)) {
            $this->fail($key, 'Must be a number.');

            return null;
        }

        $float = (float) $value;
        if (is_nan($float) || is_infinite($float)) {
            $this->fail($key, 'Must be a finite number.');

            return null;
        }
        if ($float < $min || $float > $max) {
            $this->fail($key, "Must be between {$min} and {$max}.");

            return null;
        }

        return $float;
    }

    public function bool(string $key): ?bool
    {
        if (!$this->has($key)) {
            return null;
        }

        $value = $this->input[$key];
        if (is_bool($value)) {
            return $value;
        }
        if ($value === 0 || $value === 1 || $value === '0' || $value === '1') {
            return (bool) (int) $value;
        }

        $this->fail($key, 'Must be a boolean.');

        return null;
    }

    // -- перечисления и составные типы ---------------------------------------

    /** @param list<string> $allowed */
    public function enum(string $key, array $allowed): ?string
    {
        if (!$this->has($key)) {
            return null;
        }

        $value = $this->input[$key];
        if (!is_string($value) || !in_array($value, $allowed, true)) {
            $this->fail($key, 'Must be one of: ' . implode(', ', $allowed) . '.');

            return null;
        }

        return $value;
    }

    /** @param list<string> $allowed */
    public function requiredEnum(string $key, array $allowed): ?string
    {
        if (!$this->has($key)) {
            $this->fail($key, 'Is required.');

            return null;
        }

        return $this->enum($key, $allowed);
    }

    public function isoDate(string $key): ?\DateTimeImmutable
    {
        if (!$this->has($key)) {
            return null;
        }

        $value = $this->input[$key];
        if (!is_string($value) || $value === '') {
            $this->fail($key, 'Must be an ISO-8601 date-time string.');

            return null;
        }

        try {
            return (new \DateTimeImmutable($value))->setTimezone(new \DateTimeZone('UTC'));
        } catch (\Exception) {
            $this->fail($key, 'Must be an ISO-8601 date-time string.');

            return null;
        }
    }

    public function uuid(string $key): ?string
    {
        if (!$this->has($key)) {
            return null;
        }

        $value = $this->input[$key];
        if (!is_string($value) || !Uuid::isValid($value)) {
            $this->fail($key, 'Must be a UUID.');

            return null;
        }

        return Uuid::normalize($value);
    }

    /** @return array<string,mixed>|null */
    public function object(string $key): ?array
    {
        if (!$this->has($key)) {
            return null;
        }

        $value = $this->input[$key];
        if (!is_array($value) || array_is_list($value)) {
            $this->fail($key, 'Must be an object.');

            return null;
        }

        /** @var array<string,mixed> $value */
        return $value;
    }

    /** @return list<mixed>|null */
    public function list(string $key, int $maxItems = 1000): ?array
    {
        if (!$this->has($key)) {
            return null;
        }

        $value = $this->input[$key];
        if (!is_array($value) || !array_is_list($value)) {
            $this->fail($key, 'Must be an array.');

            return null;
        }
        if (count($value) > $maxItems) {
            $this->fail($key, "Must contain at most {$maxItems} items.");

            return null;
        }

        return $value;
    }

    /**
     * Массив штрихов: [[{x,y}, …], …] — для разметки фото и подписи.
     *
     * @return list<list<array{x:float,y:float}>>|null
     */
    public function strokes(string $key, int $maxStrokes = 500, int $maxPoints = 2000): ?array
    {
        $raw = $this->list($key, $maxStrokes);
        if ($raw === null) {
            return null;
        }

        $result = [];
        foreach ($raw as $strokeIndex => $stroke) {
            if (!is_array($stroke) || !array_is_list($stroke)) {
                $this->fail($key, "Stroke {$strokeIndex} must be an array of points.");

                return null;
            }
            if (count($stroke) > $maxPoints) {
                $this->fail($key, "Stroke {$strokeIndex} has too many points (max {$maxPoints}).");

                return null;
            }

            $points = [];
            foreach ($stroke as $point) {
                if (!is_array($point) || !isset($point['x'], $point['y'])
                    || !is_numeric($point['x']) || !is_numeric($point['y'])
                ) {
                    $this->fail($key, "Stroke {$strokeIndex} contains a point without numeric x/y.");

                    return null;
                }
                $points[] = ['x' => (float) $point['x'], 'y' => (float) $point['y']];
            }
            $result[] = $points;
        }

        return $result;
    }

    public function addError(string $key, string $message): void
    {
        $this->fail($key, $message);
    }

    public function fails(): bool
    {
        return $this->errors !== [];
    }

    /** @return array<string,list<string>> */
    public function errors(): array
    {
        return $this->errors;
    }

    /** @throws ApiException 422 если что-то не прошло */
    public function validate(): void
    {
        if ($this->fails()) {
            throw ApiException::validation($this->errors);
        }
    }
}
