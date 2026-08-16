-- Обращения в поддержку: и с веб-формы, и из приложения.

CREATE TABLE IF NOT EXISTS support_requests (
    id           CHAR(36)     NOT NULL,
    -- NULL для веб-формы и для удалённых аккаунтов: обращение переживает аккаунт
    user_id      CHAR(36)     NULL,
    name         VARCHAR(120) NOT NULL,
    email        VARCHAR(255) NOT NULL,
    subject      VARCHAR(200) NOT NULL,
    message      TEXT         NOT NULL,
    source       ENUM('web','app')                             NOT NULL DEFAULT 'web',
    status       ENUM('new','in_progress','resolved','spam')   NOT NULL DEFAULT 'new',
    app_version  VARCHAR(32)  NULL,
    device_info  VARCHAR(191) NULL,
    -- хранится 90 дней, чистится cleanup.php — см. политику конфиденциальности
    ip           VARBINARY(16) NULL,
    user_agent   VARCHAR(255) NULL,
    created_at   DATETIME(3)  NOT NULL,
    handled_at   DATETIME(3)  NULL,
    PRIMARY KEY (id),
    KEY idx_support_status (status, created_at),
    KEY idx_support_email (email),
    CONSTRAINT fk_support_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Версионирование юридических текстов: пользователь должен видеть,
-- когда политика менялась в последний раз.
INSERT INTO content_blocks (slug, locale, body, updated_at)
VALUES
    ('privacy.version', 'en', '2026-08-16', UTC_TIMESTAMP(3)),
    ('support.email',   'en', 'support@ratiterun.online', UTC_TIMESTAMP(3))
AS new
ON DUPLICATE KEY UPDATE body = new.body, updated_at = UTC_TIMESTAMP(3);
