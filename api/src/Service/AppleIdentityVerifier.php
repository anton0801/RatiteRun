<?php

declare(strict_types=1);

namespace RatiteRun\Api\Service;

use RatiteRun\Api\Core\ApiException;
use RatiteRun\Api\Core\Config;

/**
 * Проверка identityToken из Sign in with Apple.
 *
 * Токен подписан RS256 ключами Apple; JWKS кэшируется на диск, чтобы
 * не ходить наружу на каждый вход.
 */
final class AppleIdentityVerifier
{
    private const JWKS_URL = 'https://appleid.apple.com/auth/keys';
    private const ISSUER   = 'https://appleid.apple.com';
    private const CACHE_TTL = 86400;

    /**
     * @return array<string,mixed> claims
     * @throws ApiException 401 если токен не проходит проверку
     */
    public function verify(string $token): array
    {
        $parts = explode('.', $token);
        if (count($parts) !== 3) {
            throw ApiException::unauthorized('Apple identity token is malformed.');
        }

        [$header64, $payload64, $signature64] = $parts;

        $header = $this->decodeSegment($header64, 'header');
        $claims = $this->decodeSegment($payload64, 'payload');

        if (($header['alg'] ?? null) !== 'RS256') {
            throw ApiException::unauthorized('Unexpected Apple token algorithm.');
        }

        $kid = $header['kid'] ?? null;
        if (!is_string($kid)) {
            throw ApiException::unauthorized('Apple token has no key id.');
        }

        $publicKey = $this->publicKeyFor($kid);
        $signature = $this->base64UrlDecode($signature64);

        if ($signature === null
            || openssl_verify($header64 . '.' . $payload64, $signature, $publicKey, OPENSSL_ALGO_SHA256) !== 1
        ) {
            throw ApiException::unauthorized('Apple token signature is invalid.');
        }

        if (($claims['iss'] ?? null) !== self::ISSUER) {
            throw ApiException::unauthorized('Apple token issuer mismatch.');
        }

        $expectedAudience = Config::get('APPLE_BUNDLE_ID', 'com.runnedratite.RatiteRun');
        $audience = $claims['aud'] ?? null;
        $audienceOk = is_array($audience)
            ? in_array($expectedAudience, $audience, true)
            : $audience === $expectedAudience;

        if (!$audienceOk) {
            throw ApiException::unauthorized('Apple token audience mismatch.');
        }

        $exp = $claims['exp'] ?? null;
        if (!is_int($exp) || time() >= $exp) {
            throw ApiException::unauthorized('Apple token has expired.');
        }

        return $claims;
    }

    /** @return array<string,mixed> */
    private function decodeSegment(string $segment, string $what): array
    {
        $json = $this->base64UrlDecode($segment);
        $decoded = $json === null ? null : json_decode($json, true);

        if (!is_array($decoded)) {
            throw ApiException::unauthorized("Apple token {$what} is not valid JSON.");
        }

        /** @var array<string,mixed> $decoded */
        return $decoded;
    }

    /** @return \OpenSSLAsymmetricKey */
    private function publicKeyFor(string $kid): \OpenSSLAsymmetricKey
    {
        foreach ([false, true] as $forceRefresh) {
            foreach ($this->jwks($forceRefresh) as $key) {
                if (($key['kid'] ?? null) !== $kid) {
                    continue;
                }

                $pem = $this->jwkToPem($key);
                $resource = openssl_pkey_get_public($pem);

                if ($resource === false) {
                    throw ApiException::unauthorized('Apple public key could not be parsed.');
                }

                return $resource;
            }
            // ключа нет в кэше — Apple мог его провернуть, пробуем ещё раз без кэша
        }

        throw ApiException::unauthorized('Apple signing key not found.');
    }

    /** @return list<array<string,mixed>> */
    private function jwks(bool $forceRefresh): array
    {
        $cachePath = rtrim(Config::get('STORAGE_PATH', dirname(__DIR__, 2) . '/storage') ?? '', '/') . '/apple-jwks.json';

        if (!$forceRefresh && is_file($cachePath) && (time() - filemtime($cachePath)) < self::CACHE_TTL) {
            $cached = json_decode((string) file_get_contents($cachePath), true);
            if (is_array($cached) && isset($cached['keys']) && is_array($cached['keys'])) {
                /** @var list<array<string,mixed>> */
                return $cached['keys'];
            }
        }

        $context = stream_context_create(['http' => ['timeout' => 5, 'ignore_errors' => true]]);
        $body = @file_get_contents(self::JWKS_URL, false, $context);

        if ($body === false) {
            throw ApiException::internal('Could not reach Apple to verify the identity token.');
        }

        $decoded = json_decode($body, true);
        if (!is_array($decoded) || !isset($decoded['keys']) || !is_array($decoded['keys'])) {
            throw ApiException::internal('Apple returned an unexpected key set.');
        }

        $dir = dirname($cachePath);
        if (is_dir($dir) || mkdir($dir, 0775, true) || is_dir($dir)) {
            @file_put_contents($cachePath, $body);
        }

        /** @var list<array<string,mixed>> */
        return $decoded['keys'];
    }

    /**
     * JWK (n, e) → PEM. Собираем DER RSAPublicKey вручную, чтобы не тянуть библиотеку.
     *
     * @param array<string,mixed> $jwk
     */
    private function jwkToPem(array $jwk): string
    {
        $modulus = $this->base64UrlDecode((string) ($jwk['n'] ?? ''));
        $exponent = $this->base64UrlDecode((string) ($jwk['e'] ?? ''));

        if ($modulus === null || $exponent === null) {
            throw ApiException::unauthorized('Apple public key is malformed.');
        }

        $components = $this->derSequence(
            $this->derInteger($modulus) . $this->derInteger($exponent),
        );

        // AlgorithmIdentifier для rsaEncryption + BIT STRING с ключом
        $rsaOid = "\x30\x0d\x06\x09\x2a\x86\x48\x86\xf7\x0d\x01\x01\x01\x05\x00";
        $bitString = "\x03" . $this->derLength(strlen($components) + 1) . "\x00" . $components;
        $der = $this->derSequence($rsaOid . $bitString);

        return "-----BEGIN PUBLIC KEY-----\n"
            . chunk_split(base64_encode($der), 64, "\n")
            . "-----END PUBLIC KEY-----\n";
    }

    private function derSequence(string $contents): string
    {
        return "\x30" . $this->derLength(strlen($contents)) . $contents;
    }

    private function derInteger(string $value): string
    {
        // ведущий 0x00, если старший бит установлен — иначе число прочтётся отрицательным
        if (ord($value[0]) > 0x7f) {
            $value = "\x00" . $value;
        }

        return "\x02" . $this->derLength(strlen($value)) . $value;
    }

    private function derLength(int $length): string
    {
        if ($length < 0x80) {
            return chr($length);
        }

        $bytes = '';
        while ($length > 0) {
            $bytes = chr($length & 0xff) . $bytes;
            $length >>= 8;
        }

        return chr(0x80 | strlen($bytes)) . $bytes;
    }

    private function base64UrlDecode(string $data): ?string
    {
        $padded = strtr($data, '-_', '+/');
        $remainder = strlen($padded) % 4;
        if ($remainder !== 0) {
            $padded .= str_repeat('=', 4 - $remainder);
        }

        $decoded = base64_decode($padded, true);

        return $decoded === false ? null : $decoded;
    }
}
