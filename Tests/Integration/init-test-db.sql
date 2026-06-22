-- ============================================================
-- Скрипт инициализации тестовой базы данных
-- Структура ДОЛЖНА ТОЧНО СООТВЕТСТВОВАТЬ тому, что использует сервер.
-- Сервер использует следующие таблицы:
--   - events (для updateSyncUpload через qryInsert)
--   - audit_logs (для /upload через WebModuleUploadAction)
--   - audit_files (для /upload через WebModuleUploadAction)
--   - user_sessions (для Login и проверки токена)
--   - pg_user (системная таблица PostgreSQL, для Login)
-- ============================================================

-- 🔑 Таблица событий (используется updateSyncUpload через qryInsert)
-- SQL: INSERT INTO events (user_id, event_type, occurred_at, metadata)
--      VALUES (:uid, :etype, :otime, :meta::jsonb)
CREATE TABLE IF NOT EXISTS events (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    occurred_at TIMESTAMP NOT NULL,
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 🔑 Таблица журналов аудита (используется /upload через WebModuleUploadAction)
-- SQL: INSERT INTO audit_logs (user_id, event_type, occurred_at, location, details, created_at)
--      VALUES (:user_id, :event_type, :occurred_at, point(:lon, :lat), :details, NOW())
--      RETURNING id
CREATE TABLE IF NOT EXISTS audit_logs (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    occurred_at TIMESTAMP NOT NULL,
    location point,
    details JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 🔑 Таблица файлов аудита (используется /upload через WebModuleUploadAction)
-- SQL: INSERT INTO audit_files (log_id, file_uuid, storage_path, original_filename, file_size, checksum_sha256, mime_type)
--      VALUES (:log_id, :uuid::uuid, :path, :orig, :size, :sha, :mime)
CREATE TABLE IF NOT EXISTS audit_files (
    id SERIAL PRIMARY KEY,
    log_id INTEGER REFERENCES audit_logs(id),
    file_uuid UUID NOT NULL,
    storage_path VARCHAR(500) NOT NULL,
    original_filename VARCHAR(255),
    file_size BIGINT NOT NULL,
    checksum_sha256 VARCHAR(64) NOT NULL,
    mime_type VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 🔑 Таблица сессий (используется Login и WebModuleBeforeDispatch)
-- SQL: INSERT INTO user_sessions (user_id, session_token, expires_at)
--      VALUES (:uid, :token, :exp)
-- SQL: SELECT user_id FROM user_sessions
--      WHERE session_token = :token AND expires_at > CURRENT_TIMESTAMP
CREATE TABLE IF NOT EXISTS user_sessions (
    session_id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    session_token VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NOT NULL
);

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

-- Очистка тестовых данных
CREATE OR REPLACE FUNCTION cleanup_test_data() RETURNS void AS $$
BEGIN
    DELETE FROM audit_files;
    DELETE FROM audit_logs;
    DELETE FROM events;
    DELETE FROM user_sessions;
END;
$$ LANGUAGE plpgsql;

-- Создание валидной сессии (принимает INTERVAL)
CREATE OR REPLACE FUNCTION create_test_session(
    p_user_id INTEGER,
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
    p_user_id INTEGER,
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

-- ============================================================
-- Представление для статистики
-- ============================================================

CREATE OR REPLACE VIEW v_test_stats AS
SELECT 'events' as table_name, COUNT(*) as row_count FROM events
UNION ALL
SELECT 'user_sessions', COUNT(*) FROM user_sessions
UNION ALL
SELECT 'audit_logs', COUNT(*) FROM audit_logs
UNION ALL
SELECT 'audit_files', COUNT(*) FROM audit_files;

-- ============================================================
-- Проверка установки
-- ============================================================

DO $$
BEGIN
    RAISE NOTICE '✅ Тестовая база данных успешно инициализирована';
    RAISE NOTICE '📊 Структура таблиц соответствует серверному коду';
    RAISE NOTICE '📊 Таблицы: events, audit_logs, audit_files, user_sessions';
END $$;
