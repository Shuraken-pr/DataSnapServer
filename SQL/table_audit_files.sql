-- Таблица загруженных файлов (дочерняя для audit_logs)
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

-- Индексы
CREATE INDEX IF NOT EXISTS idx_audit_files_log_id ON audit_files(log_id);
CREATE INDEX IF NOT EXISTS idx_audit_files_uuid ON audit_files(file_uuid);
CREATE INDEX IF NOT EXISTS idx_audit_files_created_at ON audit_files(created_at);