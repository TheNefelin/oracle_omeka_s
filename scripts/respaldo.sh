#!/usr/bin/env bash
# Respaldo de Omeka S — base de datos + archivos subidos
# Uso:   ./respaldo.sh          (desde cualquier ubicación)
# Cron:  ver sección "Copias de seguridad" del README.md
set -euo pipefail

# --- Configuración ---
BACKUP_DIR="$HOME/omeka-backups"
RETENTION_DAYS=7
DATE=$(date +%F_%H%M)

# Raíz del proyecto (~/omeka) = carpeta padre de este script
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# --- Preparación ---
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
cd "$PROJECT_DIR"

# --- 1. Base de datos (dump consistente sin bloquear tablas) ---
docker compose exec -T mariadb sh -c \
  'exec mariadb-dump --single-transaction -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"' \
  > "$BACKUP_DIR/db_${DATE}.sql"

# --- 2. Archivos subidos (volumen omeka_files) ---
# Nota: verificar nombre del volumen con `docker volume ls`
docker run --rm \
  -v omeka_omeka_files:/data:ro \
  -v "$BACKUP_DIR":/backup \
  alpine tar czf "/backup/files_${DATE}.tar.gz" -C /data .

# --- 3. Limpieza de respaldos antiguos ---
find "$BACKUP_DIR" -name "db_*.sql"       -mtime +"$RETENTION_DAYS" -delete
find "$BACKUP_DIR" -name "files_*.tar.gz" -mtime +"$RETENTION_DAYS" -delete

echo "[OK] Respaldo ${DATE} completado en $BACKUP_DIR"

# --- 4. Nivel 2: subida a Object Storage (pendiente de activar) ---
# Cuando exista el bucket OCI, configurar rclone y descomentar:
# rclone copy "$BACKUP_DIR" oci-omeka:omeka-backups --max-age 24h
