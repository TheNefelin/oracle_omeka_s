#!/usr/bin/env bash
# Respaldo de Omeka S — base de datos + archivos subidos
# Uso:   ./respaldo.sh          (desde cualquier ubicación)
# Cron:  ver sección "Copias de seguridad" del README.md
set -euo pipefail

# --- Configuración ---
BACKUP_DIR="$HOME/omeka-backups"
RETENTION_DAYS=7
DATE=$(date +%Y%m%d_%H%M)

# Raíz del proyecto (~/omeka) = carpeta padre de este script
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# --- Preparación ---
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
cd "$PROJECT_DIR"

# --- Registro de auditoría ---
LOG_FILE="$BACKUP_DIR/respaldo.log"
log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"; }

# --- 1. Base de datos (dump consistente sin bloquear tablas) ---
docker compose exec -T mariadb sh -c \
  'exec mariadb-dump --single-transaction -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"' \
  > "$BACKUP_DIR/${DATE}_db.sql"

# --- 2. Archivos subidos (volumen omeka_files) ---
# Nota: verificar nombre del volumen con `docker volume ls`
docker run --rm \
  -v omeka_omeka_files:/data:ro \
  -v "$BACKUP_DIR":/backup \
  alpine tar czf "/backup/${DATE}_files.tar.gz" -C /data .

# --- 3. Limpieza de respaldos antiguos ---
find "$BACKUP_DIR" -name "*_db.sql"     -mtime +"$RETENTION_DAYS" -delete
find "$BACKUP_DIR" -name "*_files.tar.gz" -mtime +"$RETENTION_DAYS" -delete

log "[OK] Respaldo ${DATE} completado en $BACKUP_DIR"

# --- 4. Subida a Object Storage (bucket OCI) ---
# Copia solo los respaldos generados hoy; si falla la red, no aborta el script
if rclone copy "$BACKUP_DIR" "oci-backups:omeka-respaldos/" --max-age 24h --quiet; then
  log "[OK] Respaldos subidos al bucket omeka-respaldos"
else
  log "[WARN] No se pudo subir al bucket (revisar conexión con: rclone lsd oci-backups:)"
fi

# --- 5. Bitácora de salud del disco ---
log "[INFO] Disco: $(df -h / --output=used,size,pcent | tail -n 1)"
