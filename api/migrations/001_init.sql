-- RatiteRun API — начальная схема
-- MySQL 8.0+ (нужны JSON-колонки и оконные функции)

SET NAMES utf8mb4;
SET time_zone = '+00:00';

-- ---------------------------------------------------------------------------
-- Пользователи и аутентификация
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS users (
    id            CHAR(36)     NOT NULL,
    apple_sub     VARCHAR(255) NULL,
    email         VARCHAR(255) NULL,
    display_name  VARCHAR(120) NULL,
    is_anonymous  TINYINT(1)   NOT NULL DEFAULT 1,
    created_at    DATETIME(3)  NOT NULL,
    updated_at    DATETIME(3)  NOT NULL,
    deleted_at    DATETIME(3)  NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_users_apple_sub (apple_sub),
    KEY idx_users_deleted (deleted_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Устройство = анонимная идентичность. identifierForVendor с iOS.
CREATE TABLE IF NOT EXISTS devices (
    id           CHAR(36)     NOT NULL,
    user_id      CHAR(36)     NOT NULL,
    device_key   VARCHAR(191) NOT NULL,
    platform     VARCHAR(20)  NOT NULL DEFAULT 'ios',
    apns_token   VARCHAR(255) NULL,
    timezone     VARCHAR(64)  NULL,
    app_version  VARCHAR(32)  NULL,
    created_at   DATETIME(3)  NOT NULL,
    updated_at   DATETIME(3)  NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_devices_key (device_key),
    KEY idx_devices_user (user_id),
    CONSTRAINT fk_devices_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Хранится только SHA-256 хэш refresh-токена, не сам токен.
CREATE TABLE IF NOT EXISTS refresh_tokens (
    id          CHAR(36)    NOT NULL,
    user_id     CHAR(36)    NOT NULL,
    token_hash  CHAR(64)    NOT NULL,
    expires_at  DATETIME(3) NOT NULL,
    revoked_at  DATETIME(3) NULL,
    created_at  DATETIME(3) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_refresh_hash (token_hash),
    KEY idx_refresh_user (user_id, revoked_at),
    CONSTRAINT fk_refresh_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Стада
--
-- Секции Flock (housing/fencing/feed/…) — Codable-структуры без собственного
-- жизненного цикла, поэтому лежат JSON-колонками 1:1 со Swift-моделью.
-- Нормализованы только коллекции с собственным id.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS flocks (
    id                 CHAR(36)     NOT NULL,
    user_id            CHAR(36)     NOT NULL,
    title              VARCHAR(160) NOT NULL,
    species            ENUM('ostrich','emu','rhea')            NOT NULL DEFAULT 'emu',
    bird_count         INT UNSIGNED NOT NULL DEFAULT 1,
    age                VARCHAR(80)  NOT NULL DEFAULT 'Adult',
    notes              TEXT         NULL,
    priority           ENUM('low','medium','high')             NOT NULL DEFAULT 'medium',
    status             ENUM('setup','active','attention','danger') NOT NULL DEFAULT 'setup',

    housing            JSON NOT NULL,
    fencing            JSON NOT NULL,
    feed               JSON NOT NULL,
    water_grit         JSON NOT NULL,
    handling           JSON NOT NULL,
    breeding           JSON NOT NULL,
    rearing            JSON NOT NULL,
    health             JSON NOT NULL,
    predator           JSON NOT NULL,
    terrain            JSON NOT NULL,
    kit                JSON NOT NULL,
    signoff            JSON NOT NULL,
    markup             JSON NOT NULL,

    photo_key          VARCHAR(255) NULL,
    -- денормализовано, чтобы список стад не считал движки на каждый запрос
    readiness_percent  TINYINT UNSIGNED NOT NULL DEFAULT 0,
    -- оптимистичная блокировка, отдаётся как ETag
    version            INT UNSIGNED NOT NULL DEFAULT 1,

    created_at         DATETIME(3) NOT NULL,
    updated_at         DATETIME(3) NOT NULL,
    deleted_at         DATETIME(3) NULL,

    PRIMARY KEY (id),
    KEY idx_flocks_user (user_id, deleted_at, updated_at),
    KEY idx_flocks_user_status (user_id, status, deleted_at),
    CONSTRAINT fk_flocks_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS bird_records (
    id           CHAR(36)     NOT NULL,
    flock_id     CHAR(36)     NOT NULL,
    bird_id      VARCHAR(80)  NOT NULL,
    weight_kg    DECIMAL(8,2) NOT NULL DEFAULT 0,
    height_cm    DECIMAL(8,2) NOT NULL DEFAULT 0,
    note         TEXT         NULL,
    recorded_at  DATETIME(3)  NOT NULL,
    created_at   DATETIME(3)  NOT NULL,
    updated_at   DATETIME(3)  NOT NULL,
    PRIMARY KEY (id),
    KEY idx_bird_records_flock (flock_id, recorded_at),
    KEY idx_bird_records_birdid (flock_id, bird_id, recorded_at),
    CONSTRAINT fk_bird_records_flock FOREIGN KEY (flock_id) REFERENCES flocks (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS reminders (
    id          CHAR(36)     NOT NULL,
    flock_id    CHAR(36)     NOT NULL,
    kind        ENUM('feedGrit','water','fenceCheck','legHealth') NOT NULL,
    title       VARCHAR(160) NOT NULL,
    hour        TINYINT UNSIGNED NOT NULL DEFAULT 8,
    minute      TINYINT UNSIGNED NOT NULL DEFAULT 0,
    enabled     TINYINT(1)   NOT NULL DEFAULT 1,
    created_at  DATETIME(3)  NOT NULL,
    updated_at  DATETIME(3)  NOT NULL,
    PRIMARY KEY (id),
    KEY idx_reminders_flock (flock_id),
    CONSTRAINT fk_reminders_flock FOREIGN KEY (flock_id) REFERENCES flocks (id) ON DELETE CASCADE,
    CONSTRAINT ck_reminders_hour   CHECK (hour BETWEEN 0 AND 23),
    CONSTRAINT ck_reminders_minute CHECK (minute BETWEEN 0 AND 59)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS layout_items (
    id          CHAR(36)     NOT NULL,
    flock_id    CHAR(36)     NOT NULL,
    kind        ENUM('paddock','shelter','feeder','waterer','gate','dustBath') NOT NULL,
    x           DECIMAL(6,5) NOT NULL DEFAULT 0.5,
    y           DECIMAL(6,5) NOT NULL DEFAULT 0.5,
    created_at  DATETIME(3)  NOT NULL,
    updated_at  DATETIME(3)  NOT NULL,
    PRIMARY KEY (id),
    KEY idx_layout_flock (flock_id),
    CONSTRAINT fk_layout_flock FOREIGN KEY (flock_id) REFERENCES flocks (id) ON DELETE CASCADE,
    CONSTRAINT ck_layout_x CHECK (x BETWEEN 0 AND 1),
    CONSTRAINT ck_layout_y CHECK (y BETWEEN 0 AND 1)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Справочник по видам — снимает необходимость релиза ради правки норматива
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS species_presets (
    species                 ENUM('ostrich','emu','rhea') NOT NULL,
    locale                  VARCHAR(10)  NOT NULL DEFAULT 'en',
    adult_mass_kg           DECIMAL(8,2) NOT NULL,
    space_per_bird_m2       DECIMAL(8,2) NOT NULL,
    min_space_per_bird_m2   DECIMAL(8,2) NOT NULL,
    rec_fence_height_m      DECIMAL(4,2) NOT NULL,
    min_fence_height_m      DECIMAL(4,2) NOT NULL,
    rec_fence_strength      TINYINT UNSIGNED NOT NULL,
    incubation_days         SMALLINT UNSIGNED NOT NULL,
    egg_mass_g              DECIMAL(8,2) NOT NULL,
    kick_risk_level         TINYINT UNSIGNED NOT NULL,
    target_protein_pct      DECIMAL(5,2) NOT NULL,
    grit_importance         TINYINT UNSIGNED NOT NULL,
    leg_issue_risk          TINYINT UNSIGNED NOT NULL,
    hatch_window_days       SMALLINT UNSIGNED NOT NULL,
    updated_at              DATETIME(3) NOT NULL,
    PRIMARY KEY (species, locale)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Тексты, которые сейчас зашиты в бинарник (ratiteDisclaimer и т.п.)
CREATE TABLE IF NOT EXISTS content_blocks (
    slug        VARCHAR(80) NOT NULL,
    locale      VARCHAR(10) NOT NULL DEFAULT 'en',
    body        TEXT        NOT NULL,
    updated_at  DATETIME(3) NOT NULL,
    PRIMARY KEY (slug, locale)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Отчёты
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS reports (
    id           CHAR(36)    NOT NULL,
    flock_id     CHAR(36)    NOT NULL,
    user_id      CHAR(36)    NOT NULL,
    status       ENUM('pending','ready','failed') NOT NULL DEFAULT 'pending',
    sections     JSON        NOT NULL,
    notes        TEXT        NULL,
    currency     VARCHAR(8)  NOT NULL DEFAULT 'GBP',
    snapshot     JSON        NULL,
    share_token  CHAR(32)    NULL,
    pdf_key      VARCHAR(255) NULL,
    error        VARCHAR(500) NULL,
    created_at   DATETIME(3) NOT NULL,
    expires_at   DATETIME(3) NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_reports_share (share_token),
    KEY idx_reports_flock (flock_id, created_at),
    CONSTRAINT fk_reports_flock FOREIGN KEY (flock_id) REFERENCES flocks (id) ON DELETE CASCADE,
    CONSTRAINT fk_reports_user  FOREIGN KEY (user_id)  REFERENCES users (id)  ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Идемпотентность и rate limit (без Redis — фиксированное окно в MySQL)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS idempotency_keys (
    id             CHAR(36)     NOT NULL,
    user_id        CHAR(36)     NOT NULL,
    idem_key       VARCHAR(191) NOT NULL,
    method         VARCHAR(10)  NOT NULL,
    path           VARCHAR(255) NOT NULL,
    request_hash   CHAR(64)     NOT NULL,
    status_code    SMALLINT UNSIGNED NULL,
    response_body  MEDIUMTEXT   NULL,
    created_at     DATETIME(3)  NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_idem (user_id, idem_key),
    KEY idx_idem_created (created_at),
    CONSTRAINT fk_idem_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS rate_limits (
    bucket      VARCHAR(191) NOT NULL,
    window_at   DATETIME     NOT NULL,
    hits        INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (bucket, window_at),
    KEY idx_rate_window (window_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Аудит изменений — «кто и когда поменял высоту забора»
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS audit_log (
    id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id     CHAR(36)     NOT NULL,
    flock_id    CHAR(36)     NULL,
    action      VARCHAR(60)  NOT NULL,
    path        VARCHAR(160) NULL,
    payload     JSON         NULL,
    ip          VARBINARY(16) NULL,
    created_at  DATETIME(3)  NOT NULL,
    PRIMARY KEY (id),
    KEY idx_audit_flock (flock_id, created_at),
    KEY idx_audit_user (user_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
