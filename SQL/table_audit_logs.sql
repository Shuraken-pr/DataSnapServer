-- Таблица событий аудита (родительская для audit_files)
CREATE TABLE IF NOT EXISTS audit_logs (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL DEFAULT 0,
    event_type VARCHAR(50) NOT NULL DEFAULT 'mobile_audit',
    occurred_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    location POINT,                          -- PostgreSQL native point (lon, lat)
    details TEXT,                            -- JSON-строка с дополнительными данными
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Индексы для производительности
CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_occurred_at ON audit_logs(occurred_at);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs(created_at);

-- Индекс для поиска по геолокации (GiST для point)
CREATE INDEX IF NOT EXISTS idx_audit_logs_location ON audit_logs USING GIST(location);

-- Комментарии (опционально, для документирования)
COMMENT ON TABLE audit_logs IS 'Основные события мобильного аудита';
COMMENT ON COLUMN audit_logs.location IS 'Координаты как PostgreSQL point(x=lon, y=lat)';
COMMENT ON COLUMN audit_logs.details IS 'JSON с метаданными события (устройство, исходный путь и т.д.)';