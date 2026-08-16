-- ---------------------------------------------------------------------------
-- RatiteRun API — полная установка базы одним файлом
--
-- Для случаев, когда `php bin/migrate.php` запустить негде: импорт через
-- phpMyAdmin, adminer или `mysql < install.sql`.
--
-- Таблицы идут в порядке зависимостей: родительские раньше дочерних. Это
-- принципиально — mysqldump выгружает по алфавиту, и тогда внешние ключи
-- ссылаются на ещё не созданные таблицы (ошибка 1005 / errno 150).
-- Здесь такого не будет даже при включённой проверке внешних ключей.
--
-- Файл идемпотентен: повторный импорт не ломает существующие данные.
-- В конце помечены применёнными все миграции, поэтому bin/migrate.php
-- после импорта ничего не продублирует.
--
-- Требуется MySQL 5.7+ / MariaDB 10.2+ (JSON-колонки).
-- На MySQL 8.0.16+ и MariaDB 10.2+ дополнительно работают CHECK-ограничения;
-- на более старых версиях они молча игнорируются — это допустимо, все те же
-- диапазоны проверяются на стороне API.
--
-- Порядок действий:
--   1. Создать базу и пользователя (обычно это делает панель хостинга)
--   2. Импортировать этот файл в созданную базу
--   3. Прописать доступы в api/.env
--   4. Проверить: SELECT COUNT(*) FROM species_presets;  -- должно быть 3
-- ---------------------------------------------------------------------------

SET NAMES utf8mb4;
SET @OLD_SQL_MODE = @@SQL_MODE;
SET SQL_MODE = 'NO_AUTO_VALUE_ON_ZERO';

-- ---------------------------------------------------------------------------
-- Схема
-- ---------------------------------------------------------------------------

/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `users` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `apple_sub` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `email` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `display_name` varchar(120) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `is_anonymous` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` datetime(3) NOT NULL,
  `updated_at` datetime(3) NOT NULL,
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_users_apple_sub` (`apple_sub`),
  KEY `idx_users_deleted` (`deleted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `species_presets` (
  `species` enum('ostrich','emu','rhea') COLLATE utf8mb4_unicode_ci NOT NULL,
  `locale` varchar(10) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'en',
  `adult_mass_kg` decimal(8,2) NOT NULL,
  `space_per_bird_m2` decimal(8,2) NOT NULL,
  `min_space_per_bird_m2` decimal(8,2) NOT NULL,
  `rec_fence_height_m` decimal(4,2) NOT NULL,
  `min_fence_height_m` decimal(4,2) NOT NULL,
  `rec_fence_strength` tinyint unsigned NOT NULL,
  `incubation_days` smallint unsigned NOT NULL,
  `egg_mass_g` decimal(8,2) NOT NULL,
  `kick_risk_level` tinyint unsigned NOT NULL,
  `target_protein_pct` decimal(5,2) NOT NULL,
  `grit_importance` tinyint unsigned NOT NULL,
  `leg_issue_risk` tinyint unsigned NOT NULL,
  `hatch_window_days` smallint unsigned NOT NULL,
  `updated_at` datetime(3) NOT NULL,
  PRIMARY KEY (`species`,`locale`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `content_blocks` (
  `slug` varchar(80) COLLATE utf8mb4_unicode_ci NOT NULL,
  `locale` varchar(10) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'en',
  `body` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `updated_at` datetime(3) NOT NULL,
  PRIMARY KEY (`slug`,`locale`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `rate_limits` (
  `bucket` varchar(191) COLLATE utf8mb4_unicode_ci NOT NULL,
  `window_at` datetime NOT NULL,
  `hits` int unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`bucket`,`window_at`),
  KEY `idx_rate_window` (`window_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `schema_migrations` (
  `filename` varchar(191) NOT NULL,
  `applied_at` datetime(3) NOT NULL,
  PRIMARY KEY (`filename`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `audit_log` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `flock_id` char(36) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `action` varchar(60) COLLATE utf8mb4_unicode_ci NOT NULL,
  `path` varchar(160) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `payload` json DEFAULT NULL,
  `ip` varbinary(16) DEFAULT NULL,
  `created_at` datetime(3) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_audit_flock` (`flock_id`,`created_at`),
  KEY `idx_audit_user` (`user_id`,`created_at`)
) ENGINE=InnoDB AUTO_INCREMENT=180 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `devices` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `user_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `device_key` varchar(191) COLLATE utf8mb4_unicode_ci NOT NULL,
  `platform` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'ios',
  `apns_token` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `timezone` varchar(64) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `app_version` varchar(32) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` datetime(3) NOT NULL,
  `updated_at` datetime(3) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_devices_key` (`device_key`),
  KEY `idx_devices_user` (`user_id`),
  CONSTRAINT `fk_devices_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `refresh_tokens` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `user_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `token_hash` char(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `expires_at` datetime(3) NOT NULL,
  `revoked_at` datetime(3) DEFAULT NULL,
  `created_at` datetime(3) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_refresh_hash` (`token_hash`),
  KEY `idx_refresh_user` (`user_id`,`revoked_at`),
  CONSTRAINT `fk_refresh_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `idempotency_keys` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `user_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `idem_key` varchar(191) COLLATE utf8mb4_unicode_ci NOT NULL,
  `method` varchar(10) COLLATE utf8mb4_unicode_ci NOT NULL,
  `path` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `request_hash` char(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `status_code` smallint unsigned DEFAULT NULL,
  `response_body` mediumtext COLLATE utf8mb4_unicode_ci,
  `created_at` datetime(3) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_idem` (`user_id`,`idem_key`),
  KEY `idx_idem_created` (`created_at`),
  CONSTRAINT `fk_idem_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `support_requests` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `user_id` char(36) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `name` varchar(120) COLLATE utf8mb4_unicode_ci NOT NULL,
  `email` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `subject` varchar(200) COLLATE utf8mb4_unicode_ci NOT NULL,
  `message` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `source` enum('web','app') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'web',
  `status` enum('new','in_progress','resolved','spam') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'new',
  `app_version` varchar(32) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `device_info` varchar(191) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `ip` varbinary(16) DEFAULT NULL,
  `user_agent` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` datetime(3) NOT NULL,
  `handled_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_support_status` (`status`,`created_at`),
  KEY `idx_support_email` (`email`),
  KEY `fk_support_user` (`user_id`),
  CONSTRAINT `fk_support_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `flocks` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `user_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `title` varchar(160) COLLATE utf8mb4_unicode_ci NOT NULL,
  `species` enum('ostrich','emu','rhea') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'emu',
  `bird_count` int unsigned NOT NULL DEFAULT '1',
  `age` varchar(80) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'Adult',
  `notes` text COLLATE utf8mb4_unicode_ci,
  `priority` enum('low','medium','high') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'medium',
  `status` enum('setup','active','attention','danger') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'setup',
  `housing` json NOT NULL,
  `fencing` json NOT NULL,
  `feed` json NOT NULL,
  `water_grit` json NOT NULL,
  `handling` json NOT NULL,
  `breeding` json NOT NULL,
  `rearing` json NOT NULL,
  `health` json NOT NULL,
  `predator` json NOT NULL,
  `terrain` json NOT NULL,
  `kit` json NOT NULL,
  `signoff` json NOT NULL,
  `markup` json NOT NULL,
  `photo_key` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `readiness_percent` tinyint unsigned NOT NULL DEFAULT '0',
  `version` int unsigned NOT NULL DEFAULT '1',
  `created_at` datetime(3) NOT NULL,
  `updated_at` datetime(3) NOT NULL,
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_flocks_user` (`user_id`,`deleted_at`,`updated_at`),
  KEY `idx_flocks_user_status` (`user_id`,`status`,`deleted_at`),
  CONSTRAINT `fk_flocks_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `bird_records` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `flock_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `bird_id` varchar(80) COLLATE utf8mb4_unicode_ci NOT NULL,
  `weight_kg` decimal(8,2) NOT NULL DEFAULT '0.00',
  `height_cm` decimal(8,2) NOT NULL DEFAULT '0.00',
  `note` text COLLATE utf8mb4_unicode_ci,
  `recorded_at` datetime(3) NOT NULL,
  `created_at` datetime(3) NOT NULL,
  `updated_at` datetime(3) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_bird_records_flock` (`flock_id`,`recorded_at`),
  KEY `idx_bird_records_birdid` (`flock_id`,`bird_id`,`recorded_at`),
  CONSTRAINT `fk_bird_records_flock` FOREIGN KEY (`flock_id`) REFERENCES `flocks` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `reminders` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `flock_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `kind` enum('feedGrit','water','fenceCheck','legHealth') COLLATE utf8mb4_unicode_ci NOT NULL,
  `title` varchar(160) COLLATE utf8mb4_unicode_ci NOT NULL,
  `hour` tinyint unsigned NOT NULL DEFAULT '8',
  `minute` tinyint unsigned NOT NULL DEFAULT '0',
  `enabled` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` datetime(3) NOT NULL,
  `updated_at` datetime(3) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_reminders_flock` (`flock_id`),
  CONSTRAINT `fk_reminders_flock` FOREIGN KEY (`flock_id`) REFERENCES `flocks` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_reminders_hour` CHECK ((`hour` between 0 and 23)),
  CONSTRAINT `ck_reminders_minute` CHECK ((`minute` between 0 and 59))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `layout_items` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `flock_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `kind` enum('paddock','shelter','feeder','waterer','gate','dustBath') COLLATE utf8mb4_unicode_ci NOT NULL,
  `x` decimal(6,5) NOT NULL DEFAULT '0.50000',
  `y` decimal(6,5) NOT NULL DEFAULT '0.50000',
  `created_at` datetime(3) NOT NULL,
  `updated_at` datetime(3) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_layout_flock` (`flock_id`),
  CONSTRAINT `fk_layout_flock` FOREIGN KEY (`flock_id`) REFERENCES `flocks` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_layout_x` CHECK ((`x` between 0 and 1)),
  CONSTRAINT `ck_layout_y` CHECK ((`y` between 0 and 1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `reports` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `flock_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `user_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `status` enum('pending','ready','failed') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'pending',
  `sections` json NOT NULL,
  `notes` text COLLATE utf8mb4_unicode_ci,
  `currency` varchar(8) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'GBP',
  `snapshot` json DEFAULT NULL,
  `share_token` char(32) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `pdf_key` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `error` varchar(500) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` datetime(3) NOT NULL,
  `expires_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_reports_share` (`share_token`),
  KEY `idx_reports_flock` (`flock_id`,`created_at`),
  KEY `fk_reports_user` (`user_id`),
  CONSTRAINT `fk_reports_flock` FOREIGN KEY (`flock_id`) REFERENCES `flocks` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_reports_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Справочные данные
--
-- Нормативы по видам и юридические тексты. Правятся прямо в базе без релиза
-- приложения — клиент тянет их по GET /v1/species-presets и /v1/content/{slug}.
-- Без этих строк движки оценки работать не смогут.
-- ---------------------------------------------------------------------------

INSERT IGNORE INTO `species_presets` (`species`, `locale`, `adult_mass_kg`, `space_per_bird_m2`, `min_space_per_bird_m2`, `rec_fence_height_m`, `min_fence_height_m`, `rec_fence_strength`, `incubation_days`, `egg_mass_g`, `kick_risk_level`, `target_protein_pct`, `grit_importance`, `leg_issue_risk`, `hatch_window_days`, `updated_at`) VALUES ('ostrich','en',115.00,300.00,250.00,2.00,1.80,5,42,1500.00,5,16.00,5,5,4,'2026-08-16 12:34:04.382'),('emu','en',40.00,200.00,150.00,1.80,1.50,4,52,600.00,4,17.00,4,3,6,'2026-08-16 12:34:04.382'),('rhea','en',25.00,130.00,100.00,1.50,1.20,3,38,600.00,4,18.00,4,3,5,'2026-08-16 12:34:04.382');
INSERT IGNORE INTO `content_blocks` (`slug`, `locale`, `body`, `updated_at`) VALUES ('disclaimer','en','Ratites are large, powerful birds and can be dangerous — a forward kick can cause serious injury. Follow safe handling and never corner a bird. Figures are estimates for planning only; consult a specialist ratite vet for health decisions.','2026-08-16 12:34:04.411'),('handling-rules.emu','en','Kick risk for Emu: High — the forward kick is the danger.\nNever corner the bird — always leave an escape route.\nApproach from the side, not head-on.\nUse a hood to calm before restraint.\nOnly trained handlers should restrain.','2026-08-16 12:34:04.411'),('handling-rules.ostrich','en','Kick risk for Ostrich: Extreme — the forward kick is the danger.\nNever corner the bird — always leave an escape route.\nApproach from the side, not head-on.\nUse a hood to calm before restraint.\nOnly trained handlers should restrain.','2026-08-16 12:34:04.411'),('handling-rules.rhea','en','Kick risk for Rhea: High — the forward kick is the danger.\nNever corner the bird — always leave an escape route.\nApproach from the side, not head-on.\nUse a hood to calm before restraint.\nOnly trained handlers should restrain.','2026-08-16 12:34:04.411'),('privacy.version','en','2026-08-16','2026-08-16 13:00:00.293'),('support.email','en','support@ratiterun.online','2026-08-16 13:00:00.293');

-- ---------------------------------------------------------------------------
-- Отметка о применённых миграциях
-- ---------------------------------------------------------------------------

INSERT IGNORE INTO `schema_migrations` (`filename`, `applied_at`) VALUES
  ('001_init.sql',           UTC_TIMESTAMP(3)),
  ('002_seed_reference.sql', UTC_TIMESTAMP(3)),
  ('003_support.sql',        UTC_TIMESTAMP(3));

SET SQL_MODE = @OLD_SQL_MODE;
