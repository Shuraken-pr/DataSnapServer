-- ============================================================
-- Скрипт инициализации тестовой базы данных
-- Структура ДОЛЖНА ТОЧНО СООТВЕТСТВОВАТЬ тому, что использует сервер.
-- Сервер использует следующие таблицы:
--   - users (аутентификация с bcrypt)
--   - events (для updateSyncUpload через qryInsert)
--   - audit_logs (для /upload через WebModuleUploadAction)
--   - audit_files (для /upload через WebModuleUploadAction)
--   - user_sessions (для Login и проверки токена)
--   - security_events (для аудита безопасности)
--   - rate_limits (для rate limiting)
-- ============================================================

-- 🔑 Расширение pgcrypto для bcrypt
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 🔑 Таблица пользователей (аутентификация через bcrypt, не pg_user)
CREATE TABLE IF NOT EXISTS users (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username    TEXT NOT NULL UNIQUE,
    created_at  TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE users 
  ADD COLUMN IF NOT EXISTS password_hash TEXT,
  ADD COLUMN IF NOT EXISTS role VARCHAR(20) DEFAULT 'user',
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS failed_login_attempts INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS locked_until TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP;
  
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_active ON users(is_active) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_users_locked ON users(locked_until);

-- Триггер обновления updated_at
CREATE OR REPLACE FUNCTION trigger_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_users_updated_at ON users;
CREATE TRIGGER tr_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_updated_at();

-- Тестовый пользователь (password = 'test_password')
-- Используем plain text для тестов — сервер Login имеет fallback
INSERT INTO users (username, password_hash, is_active)
VALUES ('test_user', 'test_password', TRUE)
ON CONFLICT (username) DO UPDATE SET
    password_hash = 'test_password',
    is_active = TRUE;

-- Второй тестовый пользователь (для тестов с user_id=2)
INSERT INTO users (username, password_hash, is_active)
VALUES ('test_user_2', 'test_password', TRUE)
ON CONFLICT (username) DO UPDATE SET
    password_hash = 'test_password',
    is_active = TRUE;

-- 🔑 Таблица событий (используется updateSyncUpload через qryInsert)
CREATE TABLE IF NOT EXISTS events (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     BIGINT NOT NULL REFERENCES users(id),
    event_type  VARCHAR(50) NOT NULL,
    occurred_at TIMESTAMP NOT NULL,
    metadata    JSONB,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 🔑 Таблица журналов аудита (используется /upload через WebModuleUploadAction)
CREATE TABLE IF NOT EXISTS audit_logs (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     BIGINT NOT NULL REFERENCES users(id),
    event_type  VARCHAR(50) NOT NULL,
    occurred_at TIMESTAMP NOT NULL,
    location    point,
    details     JSONB,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 🔑 Таблица файлов аудита (используется /upload через WebModuleUploadAction)
CREATE TABLE IF NOT EXISTS audit_files (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    log_id              BIGINT REFERENCES audit_logs(id) ON DELETE CASCADE,
    file_uuid           UUID NOT NULL,
    storage_path        VARCHAR(500) NOT NULL,
    original_filename   VARCHAR(255),
    file_size           BIGINT NOT NULL,
    checksum_sha256     VARCHAR(64) NOT NULL,
    mime_type           VARCHAR(100),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 🔑 Таблица сессий (используется Login и WebModuleBeforeDispatch)
CREATE TABLE IF NOT EXISTS user_sessions (
    session_id      BIGSERIAL PRIMARY KEY,
    user_id         BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_token   VARCHAR(255) UNIQUE NOT NULL,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at      TIMESTAMP NOT NULL
);

-- 🔑 Таблица аудита безопасности (для SecurityAuditor)
CREATE TABLE IF NOT EXISTS security_events (
    event_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_type  TEXT NOT NULL,
    username    TEXT,
    ip_address  TEXT NOT NULL,
    user_agent  TEXT,
    user_id     BIGINT REFERENCES users(id),
    details     TEXT,
    severity    TEXT NOT NULL DEFAULT 'info',
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT chk_security_severity CHECK (severity IN ('info', 'warning', 'critical'))
);

CREATE INDEX IF NOT EXISTS idx_security_events_time ON security_events(created_at);
CREATE INDEX IF NOT EXISTS idx_security_events_type ON security_events(event_type);
CREATE INDEX IF NOT EXISTS idx_security_events_user ON security_events(username);

-- 🔑 Таблица rate limiting (для RateLimiter)
CREATE TABLE IF NOT EXISTS rate_limits (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ip_address      TEXT NOT NULL,
    endpoint        TEXT NOT NULL,
    request_count   INTEGER NOT NULL DEFAULT 1,
    window_start    TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT uq_rate_ip_endpoint UNIQUE (ip_address, endpoint)
);

CREATE INDEX IF NOT EXISTS idx_rate_limits_window ON rate_limits(window_start);

-- ============================================================
-- Индексы для производительности
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_events_user ON events(user_id);
CREATE INDEX IF NOT EXISTS idx_events_occurred ON events(occurred_at);
CREATE INDEX IF NOT EXISTS idx_sessions_token ON user_sessions(session_token);
CREATE INDEX IF NOT EXISTS idx_sessions_expires ON user_sessions(expires_at);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON user_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_user ON audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_occurred ON audit_logs(occurred_at);
CREATE INDEX IF NOT EXISTS idx_audit_files_log ON audit_files(log_id);
CREATE INDEX IF NOT EXISTS idx_audit_files_uuid ON audit_files(file_uuid);

-- ============================================================
-- Вспомогательные функции для тестов
-- ============================================================

-- Очистка тестовых данных (кроме users — пользователь нужен для логина)
CREATE OR REPLACE FUNCTION cleanup_test_data() RETURNS void AS $$
BEGIN
    DELETE FROM audit_files;
    DELETE FROM audit_logs;
    DELETE FROM events;
    DELETE FROM user_sessions;
    DELETE FROM security_events;
    DELETE FROM rate_limits;
END;
$$ LANGUAGE plpgsql;

-- Создание валидной сессии (принимает INTERVAL)
CREATE OR REPLACE FUNCTION create_test_session(
    p_user_id BIGINT,
    p_expires_in INTERVAL DEFAULT INTERVAL '24 hours'
) RETURNS VARCHAR AS $$
DECLARE
    v_token VARCHAR(255);
BEGIN
    v_token := md5(random()::text || clock_timestamp()::text);
    INSERT INTO user_sessions (user_id, session_token, expires_at)
    VALUES (p_user_id, v_token, CURRENT_TIMESTAMP + p_expires_in);
    RETURN v_token;
END;
$$ LANGUAGE plpgsql;

-- 🔑 Создание просроченной сессии (INTERVAL — для совместимости с тестами)
CREATE OR REPLACE FUNCTION create_expired_test_session(
    p_user_id BIGINT,
    p_expired_interval INTERVAL DEFAULT INTERVAL '1 hour'
) RETURNS VARCHAR AS $$
DECLARE
    v_token VARCHAR(255);
BEGIN
    v_token := md5(random()::text || clock_timestamp()::text);
    INSERT INTO user_sessions (user_id, session_token, expires_at)
    VALUES (p_user_id, v_token, CURRENT_TIMESTAMP - p_expired_interval);
    RETURN v_token;
END;
$$ LANGUAGE plpgsql;

-- 🔑 Функция очистки rate_limits (старше 1 часа)
CREATE OR REPLACE FUNCTION cleanup_rate_limits() RETURNS void AS $$
BEGIN
    DELETE FROM rate_limits
    WHERE window_start < CURRENT_TIMESTAMP - INTERVAL '1 hour';
END;
$$ LANGUAGE plpgsql;

-- 🔑 Функция очистки старых событий безопасности
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

-- 🔑 Функция автоматической разблокировки просроченных аккаунтов
CREATE OR REPLACE FUNCTION unlock_expired_accounts() RETURNS integer AS $$
DECLARE
    unlocked_count integer;
BEGIN
    UPDATE users 
    SET locked_until = NULL, failed_login_attempts = 0
    WHERE locked_until IS NOT NULL 
      AND locked_until < CURRENT_TIMESTAMP;
    
    GET DIAGNOSTICS unlocked_count = ROW_COUNT;
    RETURN unlocked_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- Представление для статистики
-- ============================================================

CREATE OR REPLACE VIEW v_test_stats AS
SELECT 'users' as table_name, COUNT(*) as row_count FROM users
UNION ALL
SELECT 'events', COUNT(*) FROM events
UNION ALL
SELECT 'user_sessions', COUNT(*) FROM user_sessions
UNION ALL
SELECT 'audit_logs', COUNT(*) FROM audit_logs
UNION ALL
SELECT 'audit_files', COUNT(*) FROM audit_files
UNION ALL
SELECT 'security_events', COUNT(*) FROM security_events
UNION ALL
SELECT 'rate_limits', COUNT(*) FROM rate_limits;

-- ============================================================
-- Проверка установки
-- ============================================================

-- ============================================================
-- 🔑 Account lockout columns in users
-- ============================================================

ALTER TABLE users ADD COLUMN IF NOT EXISTS failed_login_attempts INTEGER DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS locked_until TIMESTAMP;
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMP;

-- 🔑 Разблокировка просроченных аккаунтов
CREATE OR REPLACE FUNCTION unlock_expired_accounts() RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER;
BEGIN
    UPDATE users
    SET locked_until = NULL, failed_login_attempts = 0
    WHERE locked_until IS NOT NULL AND locked_until < CURRENT_TIMESTAMP;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
    RAISE NOTICE '✅ Тестовая база данных успешно инициализирована';
    RAISE NOTICE '📊 Структура таблиц соответствует серверному коду';
    RAISE NOTICE '📊 Таблицы: users, events, audit_logs, audit_files, user_sessions, security_events, rate_limits';
END $$;
