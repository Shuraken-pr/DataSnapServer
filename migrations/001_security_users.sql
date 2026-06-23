-- ============================================================
-- Миграция 001: Безопасность пользователей
-- Совместима с существующей схемой из Postgre_Delphi
-- и SQL-скриптами проекта DataSnapServer (папка SQL/)
--
-- Идемпотентная: можно запускать многократно без ошибок.
-- ============================================================

BEGIN;

-- ============================================================
-- ШАГ 1: Создание таблицы users (если её ещё нет)
-- ============================================================
-- Если Postgre_Delphi уже создал таблицу, этот блок будет пропущен.
-- Если таблицы нет — создаём её с полями из Postgre_Delphi.
--
-- Поля, используемые сервером (из ServerMethodsUnitMain.pas):
--   id          — BIGINT (AsLargeInt в Delphi)
--   username    — TEXT (имя пользователя)
--   password_hash — TEXT (bcrypt-хеш через pgcrypto или plain text)
--   is_active   — BOOLEAN (активен ли аккаунт)
--
-- Дополнительные поля для безопасности:
--   role                  — роль пользователя (user/admin/auditor)
--   last_login_at         — время последнего успешного входа
--   failed_login_attempts — счётчик неудачных попыток входа
--   locked_until          — время, до которого аккаунт заблокирован
--   updated_at            — время последнего обновления записи

CREATE TABLE IF NOT EXISTS users (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- ШАГ 2: Расширение таблицы users полями безопасности
-- ============================================================
-- ADD COLUMN IF NOT EXISTS гарантирует идемпотентность:
-- повторный запуск скрипта не вызовет ошибок.

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS password_hash TEXT,
  ADD COLUMN IF NOT EXISTS role VARCHAR(20) DEFAULT 'user',
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS failed_login_attempts INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS locked_until TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- ============================================================
-- ШАГ 3: Ограничения (проверяем существование перед созданием)
-- ============================================================

DO $$
BEGIN
  -- Ограничение на роль
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_users_role'
  ) THEN
    ALTER TABLE users
      ADD CONSTRAINT chk_users_role
      CHECK (role IN ('user', 'admin', 'auditor'));
  END IF;

  -- Ограничение на количество неудачных попыток
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_users_failed_attempts'
  ) THEN
    ALTER TABLE users
      ADD CONSTRAINT chk_users_failed_attempts
      CHECK (failed_login_attempts >= 0);
  END IF;
END $$;

-- ============================================================
-- ШАГ 4: Индексы для производительности
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_users_active ON users(is_active);
CREATE INDEX IF NOT EXISTS idx_users_locked ON users(locked_until);
CREATE INDEX IF NOT EXISTS idx_users_last_login ON users(last_login_at);
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);

-- ============================================================
-- ШАГ 5: Триггер для автоматического обновления updated_at
-- ============================================================

CREATE OR REPLACE FUNCTION trg_users_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Удаляем триггер, если он уже существует (для идемпотентности)
DROP TRIGGER IF EXISTS trg_users_updated_at ON users;

CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW
  EXECUTE FUNCTION trg_users_updated_at();

-- ============================================================
-- ШАГ 6: Вспомогательные таблицы (если их ещё нет)
-- ============================================================
-- Эти таблицы уже определены в папке SQL/, но мы создаём их
-- через IF NOT EXISTS для идемпотентности миграции.

-- Таблица сессий (совместима с SQL/table_user_sessions.sql)
CREATE TABLE IF NOT EXISTS user_sessions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    session_token VARCHAR(64) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_sessions_token ON user_sessions(session_token);
CREATE INDEX IF NOT EXISTS idx_sessions_expires ON user_sessions(expires_at);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON user_sessions(user_id);

-- Таблица событий синхронизации (совместима с SQL/table_events.sql)
CREATE TABLE IF NOT EXISTS events (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    occurred_at TIMESTAMP NOT NULL,
    metadata JSONB
);

CREATE INDEX IF NOT EXISTS idx_events_user ON events(user_id);
CREATE INDEX IF NOT EXISTS idx_events_occurred ON events(occurred_at);
CREATE INDEX IF NOT EXISTS idx_events_type ON events(event_type);

-- Таблица журналов аудита (совместима с SQL/table_audit_logs.sql)
CREATE TABLE IF NOT EXISTS audit_logs (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL DEFAULT 0,
    event_type VARCHAR(50) NOT NULL DEFAULT 'mobile_audit',
    occurred_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    location POINT,
    details TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_occurred_at ON audit_logs(occurred_at);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs(created_at);
CREATE INDEX IF NOT EXISTS idx_audit_logs_location ON audit_logs USING GIST(location);

-- Таблица загруженных файлов (совместима с SQL/table_audit_files.sql)
CREATE TABLE IF NOT EXISTS audit_files (
    id SERIAL PRIMARY KEY,
    log_id INTEGER NOT NULL REFERENCES audit_logs(id) ON DELETE CASCADE,
    file_uuid UUID NOT NULL UNIQUE,
    storage_path VARCHAR(500) NOT NULL,
    original_filename VARCHAR(255),
    file_size BIGINT NOT NULL DEFAULT 0,
    checksum_sha256 CHAR(64),
    mime_type VARCHAR(50) NOT NULL DEFAULT 'image/jpeg',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_audit_files_log_id ON audit_files(log_id);
CREATE INDEX IF NOT EXISTS idx_audit_files_uuid ON audit_files(file_uuid);
CREATE INDEX IF NOT EXISTS idx_audit_files_created_at ON audit_files(created_at);

-- ============================================================
-- ШАГ 7: Таблица аудита безопасности (НОВАЯ)
-- ============================================================
-- Записывает все события безопасности для расследования инцидентов.

CREATE TABLE IF NOT EXISTS security_events (
    event_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_type TEXT NOT NULL,
    username TEXT,
    ip_address TEXT NOT NULL,
    user_agent TEXT,
    details JSONB,
    severity TEXT NOT NULL DEFAULT 'info',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT chk_security_severity CHECK (severity IN ('info', 'warning', 'critical'))
);

CREATE INDEX IF NOT EXISTS idx_security_events_time ON security_events(created_at);
CREATE INDEX IF NOT EXISTS idx_security_events_type ON security_events(event_type);
CREATE INDEX IF NOT EXISTS idx_security_events_user ON security_events(username);
CREATE INDEX IF NOT EXISTS idx_security_events_ip ON security_events(ip_address);
CREATE INDEX IF NOT EXISTS idx_security_events_severity ON security_events(severity);

-- ============================================================
-- ШАГ 8: Таблица rate limiting (НОВАЯ)
-- ============================================================
-- Хранит счётчики запросов для защиты от DDoS и brute-force.

CREATE TABLE IF NOT EXISTS rate_limits (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ip_address TEXT NOT NULL,
    endpoint TEXT NOT NULL,
    request_count INTEGER NOT NULL DEFAULT 1,
    window_start TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT uq_rate_ip_endpoint UNIQUE (ip_address, endpoint)
);

CREATE INDEX IF NOT EXISTS idx_rate_limits_window ON rate_limits(window_start);
CREATE INDEX IF NOT EXISTS idx_rate_limits_ip ON rate_limits(ip_address);

-- ============================================================
-- ШАГ 9: Вспомогательные функции
-- ============================================================

-- Функция очистки rate_limits (старше 1 часа)
CREATE OR REPLACE FUNCTION cleanup_rate_limits() RETURNS void AS $$
BEGIN
  DELETE FROM rate_limits
  WHERE window_start < CURRENT_TIMESTAMP - INTERVAL '1 hour';
END;
$$ LANGUAGE plpgsql;

-- Функция автоматической разблокировки пользователей
CREATE OR REPLACE FUNCTION unlock_expired_accounts() RETURNS integer AS $$
DECLARE
  unlocked_count integer;
BEGIN
  UPDATE users
  SET locked_until = NULL,
      failed_login_attempts = 0
  WHERE locked_until IS NOT NULL
    AND locked_until < CURRENT_TIMESTAMP;

  GET DIAGNOSTICS unlocked_count = ROW_COUNT;
  RETURN unlocked_count;
END;
$$ LANGUAGE plpgsql;

-- Функция очистки просроченных сессий
CREATE OR REPLACE FUNCTION cleanup_expired_sessions() RETURNS integer AS $$
DECLARE
  deleted_count integer;
BEGIN
  DELETE FROM user_sessions
  WHERE expires_at < CURRENT_TIMESTAMP;

  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Функция очистки старых событий безопасности (старше 90 дней)
CREATE OR REPLACE FUNCTION cleanup_old_security_events(
  p_days integer DEFAULT 90
) RETURNS integer AS $$
DECLARE
  deleted_count integer;
BEGIN
  DELETE FROM security_events
  WHERE created_at < CURRENT_TIMESTAMP - (p_days || ' days')::INTERVAL;

  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

COMMIT;

-- ============================================================
-- Проверка результата
-- ============================================================

DO $$
DECLARE
  users_count integer;
  has_password_hash boolean;
  has_is_active boolean;
  has_failed_attempts boolean;
  has_locked_until boolean;
  has_security_events boolean;
  has_rate_limits boolean;
BEGIN
  SELECT COUNT(*) INTO users_count FROM users;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'users' AND column_name = 'password_hash'
  ) INTO has_password_hash;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'users' AND column_name = 'is_active'
  ) INTO has_is_active;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'users' AND column_name = 'failed_login_attempts'
  ) INTO has_failed_attempts;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'users' AND column_name = 'locked_until'
  ) INTO has_locked_until;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'security_events'
  ) INTO has_security_events;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'rate_limits'
  ) INTO has_rate_limits;

  RAISE NOTICE '============================================================';
  RAISE NOTICE '  Миграция 001 успешно выполнена';
  RAISE NOTICE '============================================================';
  RAISE NOTICE 'Пользователей в таблице users: %', users_count;
  RAISE NOTICE 'Поле password_hash:      %', CASE WHEN has_password_hash THEN 'OK' ELSE 'ОТСУТСТВУЕТ!' END;
  RAISE NOTICE 'Поле is_active:          %', CASE WHEN has_is_active THEN 'OK' ELSE 'ОТСУТСТВУЕТ!' END;
  RAISE NOTICE 'Поле failed_login_attempts: %', CASE WHEN has_failed_attempts THEN 'OK' ELSE 'ОТСУТСТВУЕТ!' END;
  RAISE NOTICE 'Поле locked_until:       %', CASE WHEN has_locked_until THEN 'OK' ELSE 'ОТСУТСТВУЕТ!' END;
  RAISE NOTICE 'Таблица security_events: %', CASE WHEN has_security_events THEN 'OK' ELSE 'ОТСУТСТВУЕТ!' END;
  RAISE NOTICE 'Таблица rate_limits:     %', CASE WHEN has_rate_limits THEN 'OK' ELSE 'ОТСУТСТВУЕТ!' END;
  RAISE NOTICE '============================================================';
END $$;
