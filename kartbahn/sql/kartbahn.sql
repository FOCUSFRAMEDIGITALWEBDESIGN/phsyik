-- Kartbahn: Tabellen (werden beim Start auch automatisch angelegt)

CREATE TABLE IF NOT EXISTS `kart_profiles` (
    `identifier`  VARCHAR(64) NOT NULL PRIMARY KEY,
    `name`        VARCHAR(64) NOT NULL DEFAULT '',
    `rating`      INT NOT NULL DEFAULT 1000,
    `peak_rating` INT NOT NULL DEFAULT 1000,
    `races`       INT NOT NULL DEFAULT 0,
    `wins`        INT NOT NULL DEFAULT 0,
    `podiums`     INT NOT NULL DEFAULT 0,
    `dnfs`        INT NOT NULL DEFAULT 0,
    `laps`        INT NOT NULL DEFAULT 0,
    `prize_money` INT NOT NULL DEFAULT 0,
    `updated_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_rating` (`rating`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `kart_laps` (
    `id`         INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `identifier` VARCHAR(64) NOT NULL,
    `name`       VARCHAR(64) NOT NULL DEFAULT '',
    `track`      VARCHAR(64) NOT NULL,
    `lap_time`   INT NOT NULL,
    `mode`       VARCHAR(8) NOT NULL DEFAULT 'tt',
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_track_time` (`track`, `lap_time`),
    INDEX `idx_ident_track` (`identifier`, `track`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `kart_races` (
    `id`         INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `track`      VARCHAR(64) NOT NULL,
    `laps`       INT NOT NULL DEFAULT 0,
    `results`    LONGTEXT NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ===== Feature-Tabellen =====
CREATE TABLE IF NOT EXISTS `kart_season` (
    `season` VARCHAR(16) NOT NULL, `identifier` VARCHAR(64) NOT NULL, `name` VARCHAR(64) NOT NULL DEFAULT '',
    `points` INT NOT NULL DEFAULT 0, `races` INT NOT NULL DEFAULT 0, `wins` INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`season`, `identifier`), INDEX `idx_points` (`season`, `points`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `kart_season_winners` (
    `season` VARCHAR(16) NOT NULL PRIMARY KEY, `results` LONGTEXT NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `kart_payouts` (
    `id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY, `identifier` VARCHAR(64) NOT NULL,
    `amount` INT NOT NULL, `reason` VARCHAR(64) NOT NULL DEFAULT '', INDEX `idx_ident` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `kart_achievements` (
    `identifier` VARCHAR(64) NOT NULL, `code` VARCHAR(32) NOT NULL,
    `unlocked_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (`identifier`, `code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `kart_custom` (
    `identifier` VARCHAR(64) NOT NULL PRIMARY KEY, `paint` VARCHAR(16) NOT NULL DEFAULT 'yellow',
    `number` INT NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `kart_ghosts` (
    `identifier` VARCHAR(64) NOT NULL, `track` VARCHAR(64) NOT NULL, `name` VARCHAR(64) NOT NULL DEFAULT '',
    `lap_time` INT NOT NULL, `data` LONGTEXT NOT NULL,
    PRIMARY KEY (`identifier`, `track`), INDEX `idx_track_time` (`track`, `lap_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
