#!/bin/bash
set -e

# ====================================================================================
# SCRIPT DE CONFIGURACION, INSTALACION Y GESTION PARA NEXTCLOUD + ONLYOFFICE + JELLYFIN
# VERSION FPM + APACHE SEPARADOS PARA PRODUCCION - v5 (SOLUCION DEFINITIVA)
# ====================================================================================

# --- PARTE 1: PREPARACION DEL ENTORNO Y DEPENDENCIAS ---
echo "--------------------------------------------------------"
echo "🚀 INICIANDO DESPLIEGUE NEXTCLOUD FPM + APACHE + ONLYOFFICE + JELLYFIN 🚀"
echo "--------------------------------------------------------"

# Verificación de dependencias
if ! command -v restic &> /dev/null; then
    echo "⚠️ La herramienta 'restic' no esta instalada. Es esencial para los backups incrementales."
    read -p "❓ Desea intentar instalarla ahora? (s/n): " INSTALL_RESTIC
    if [[ "$INSTALL_RESTIC" == "s" || "$INSTALL_RESTIC" == "S" ]]; then
        if command -v apt-get &> /dev/null; then
            echo "    🔍 Detectado sistema basado en Debian/Ubuntu. Usando 'apt'..."
            sudo apt-get update && sudo apt-get install -y restic
        elif command -v dnf &> /dev/null; then
            echo "    🔍 Detectado sistema basado en Fedora/CentOS. Usando 'dnf'..."
            sudo dnf install -y restic
        else
            echo "    ❌ No se pudo determinar el gestor de paquetes. Por favor, instale 'restic' manualmente." >&2; exit 1;
        fi
        echo "✅ 'restic' instalado correctamente."
    else
        echo "❌ Despliegue cancelado. 'restic' es obligatorio." >&2; exit 1;
    fi
fi

if ! command -v docker &> /dev/null; then
    echo "⚠️ Docker no esta instalado. Por favor, instalelo y asegurese de que el usuario actual tenga permisos para usarlo." >&2; exit 1;
fi

if ! command -v docker compose &> /dev/null; then
    echo "⚠️ Docker Compose V2 (comando 'docker compose') no esta instalado. Por favor, instalelo." >&2; exit 1;
fi
echo "--- ✅ Dependencias verificadas. ---"

echo "--- 📋 Cargando configuracion desde .env ---"
if [ -f .env ]; then
    echo "    📂 Cargando configuracion desde .env..."
    set -a; source .env; set +a;
else
    echo "❌ ERROR: No se encontro el archivo .env." >&2; exit 1;
fi

# Validar RESTIC_PASSWORD
if [ -z "$RESTIC_PASSWORD" ]; then
    echo "❌ ERROR: La variable RESTIC_PASSWORD no está definida en .env." >&2; exit 1;
fi

# Crear archivo /etc/restic_password si no existe
echo "--- 🔐 Creando o verificando archivo de contraseña para Restic ---"
if [ ! -f /etc/restic_password ]; then
    echo "    📝 Creando /etc/restic_password con RESTIC_PASSWORD desde .env..."
    echo "$RESTIC_PASSWORD" | sudo tee /etc/restic_password > /dev/null
    sudo chmod 600 /etc/restic_password
    sudo chown $USER:$USER /etc/restic_password
    echo "    ✅ Archivo /etc/restic_password creado."
else
    echo "    ✅ Archivo /etc/restic_password ya existe."
fi

echo "--- 📁 Creando estructura de directorios ---"
sudo mkdir -p "$APP_DATA_PATH/nextcloud/html" \
              "$APP_DATA_PATH/nextcloud/database" \
              "$APP_DATA_PATH/onlyoffice/database" \
              "$APP_DATA_PATH/onlyoffice/logs" \
              "$APP_DATA_PATH/onlyoffice/lib" \
              "$APP_DATA_PATH/multimedia" \
              "$JELLYFIN_CONFIG_PATH"
mkdir -p ./scripts ./nextcloud_config ./apache_image

# Asignar permisos a carpetas compartidas
echo "--- 🔐 Asegurando permisos en carpetas multimedia y de datos ---"
sudo chown -R ${PUID}:${PGID} "$APP_DATA_PATH/multimedia"
sudo chmod -R 755 "$APP_DATA_PATH/multimedia"
echo "✅ Directorios creados y permisos asignados."

echo "--- 🐋 Creando Dockerfile para Apache con HTTP/2 ---"
cat << 'EOF' > ./apache_image/Dockerfile
FROM httpd:2.4-alpine
RUN apk update && apk add --no-cache apache2-http2
EOF
echo "✅ Dockerfile creado."

echo "--- 🔧 Generando configuraciones PHP-FPM optimizadas ---"
cat << 'EOF' > ./nextcloud_config/uploads.ini
[PHP]
memory_limit = ${PHP_MEMORY_LIMIT}
upload_max_filesize = ${PHP_UPLOAD_LIMIT}
post_max_size = ${PHP_UPLOAD_LIMIT}
max_execution_time = 3600
max_input_time = 3600
max_input_vars = 2000
output_buffering = 0
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=128
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=10000
opcache.validate_timestamps=0
opcache.revalidate_freq=600
opcache.fast_shutdown=1
opcache.save_comments=1
apc.enabled=1
apc.shm_size=128M
apc.enable_cli=1
realpath_cache_size=20M
realpath_cache_ttl=7200
session.save_handler = redis
session.save_path = "tcp://redis_nextcloud:6379?auth=${REDIS_HOST_PASSWORD}"
session.gc_maxlifetime = 86400
EOF

cat << 'EOF' > ./nextcloud_config/www.conf
[www]
user = www-data
group = www-data
listen = 9000
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
listen.backlog = 511
pm = dynamic
pm.max_children = 25
pm.start_servers = 8
pm.min_spare_servers = 5
pm.max_spare_servers = 15
pm.max_requests = 2000
pm.process_idle_timeout = 60s
request_terminate_timeout = 300
request_slowlog_timeout = 30
slowlog = /proc/self/fd/2
access.log = /proc/self/fd/2
catch_workers_output = yes
decorate_workers_output = no
clear_env = no
env[HOSTNAME] = $HOSTNAME
env[PATH] = /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
env[TMP] = /tmp
env[TMPDIR] = /tmp
env[TEMP] = /tmp
security.limit_extensions = .php .phar
rlimit_files = 65536
rlimit_core = 0
pm.status_path = /status
ping.path = /ping
EOF

echo "--- 🔧 Generando configuración Apache principal ---"
cat << 'EOF' > ./nextcloud_config/httpd.conf
ServerRoot "/usr/local/apache2"
Listen 80
LoadModule mpm_event_module modules/mod_mpm_event.so
LoadModule http2_module modules/mod_http2.so
LoadModule authz_core_module modules/mod_authz_core.so
LoadModule authz_host_module modules/mod_authz_host.so
LoadModule authz_user_module modules/mod_authz_user.so
LoadModule authn_core_module modules/mod_authn_core.so
LoadModule dir_module modules/mod_dir.so
LoadModule mime_module modules/mod_mime.so
LoadModule rewrite_module modules/mod_rewrite.so
LoadModule headers_module modules/mod_headers.so
LoadModule proxy_module modules/mod_proxy.so
LoadModule proxy_fcgi_module modules/mod_proxy_fcgi.so
LoadModule deflate_module modules/mod_deflate.so
LoadModule filter_module modules/mod_filter.so
LoadModule env_module modules/mod_env.so
LoadModule expires_module modules/mod_expires.so
LoadModule setenvif_module modules/mod_setenvif.so
LoadModule alias_module modules/mod_alias.so
LoadModule log_config_module modules/mod_log_config.so
LoadModule unixd_module modules/mod_unixd.so
ServerName localhost
ServerAdmin admin@localhost
DocumentRoot "/var/www/html"
DirectoryIndex index.php index.html
Protocols h2c http/1.1
ServerTokens Prod
ServerSignature Off
Timeout 300
KeepAlive On
MaxKeepAliveRequests 100
KeepAliveTimeout 5
<IfModule mpm_event_module>
    StartServers             2
    ServerLimit              4
    MinSpareThreads          25
    MaxSpareThreads          75
    ThreadsPerChild          25
    MaxRequestWorkers        100
    MaxConnectionsPerChild   0
</IfModule>
TypesConfig conf/mime.types
AddType video/mp4 .mp4
AddType video/webm .webm
AddType video/ogg .ogv
AddType audio/mp4 .m4a
AddType audio/mpeg .mp3
AddType audio/ogg .oga .ogg
AddType audio/wav .wav
AddType image/webp .webp
<IfModule mod_deflate.c>
    AddOutputFilterByType DEFLATE text/plain
    AddOutputFilterByType DEFLATE text/html
    AddOutputFilterByType DEFLATE text/xml
    AddOutputFilterByType DEFLATE text/css
    AddOutputFilterByType DEFLATE application/xml
    AddOutputFilterByType DEFLATE application/xhtml+xml
    AddOutputFilterByType DEFLATE application/rss+xml
    AddOutputFilterByType DEFLATE application/javascript
    AddOutputFilterByType DEFLATE application/x-javascript
    AddOutputFilterByType DEFLATE application/json
</IfModule>
<IfModule mod_headers.c>
    Header always set X-Content-Type-Options nosniff
    Header always set X-Frame-Options SAMEORIGIN
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "no-referrer"
    Header always set X-Download-Options noopen
    Header always set X-Permitted-Cross-Domain-Policies none
</IfModule>
Include conf/extra/nextcloud.conf
ErrorLog /proc/self/fd/2
CustomLog /proc/self/fd/1 combined
LogLevel warn
EOF

echo "--- 🔧 Generando configuración específica de Nextcloud ---"
cat << 'EOF' > ./nextcloud_config/nextcloud.conf
<Directory "/var/www/html">
    Options -Indexes +FollowSymLinks
    AllowOverride All
    Require all granted
    <FilesMatch "\.php$">
        SetHandler "proxy:fcgi://nextcloud-app-server:9000"
    </FilesMatch>
</Directory>

# Caché agresiva para recursos estáticos
<LocationMatch "\.(css|js|woff2?|eot|ttf|otf|png|jpe?g|gif|svg|ico|pdf)$">
    Header set Cache-Control "public, immutable, max-age=31536000"
</LocationMatch>

# Caché para OnlyOffice (JS, WASM, etc.)
<Location "/apps/onlyoffice">
    ExpiresActive On
    ExpiresDefault "access plus 1 week"
    Header append Cache-Control "public, immutable"
</Location>

# Manejo de video/audio
<LocationMatch "\.(mp4|webm|ogv|avi|mov|flv|wmv|mkv)$">
    Header set Accept-Ranges bytes
    ExpiresActive On
    ExpiresDefault "access plus 7 days"
    Header append Cache-Control "public"
    SetEnv no-gzip 1
</LocationMatch>
<LocationMatch "\.(mp3|wav|ogg|oga|m4a|aac|flac)$">
    Header set Accept-Ranges bytes
    ExpiresActive On
    ExpiresDefault "access plus 7 days"
    Header append Cache-Control "public"
    SetEnv no-gzip 1
</LocationMatch>

# Reglas de seguridad y redirección
LimitRequestBody 0
RewriteEngine On
RewriteRule ^\.well-known/carddav /remote.php/dav/ [R=301,L]
RewriteRule ^\.well-known/caldav /remote.php/dav/ [R=301,L]

<DirectoryMatch "^/var/www/html/(config|data|\.git)">
    Require all denied
</DirectoryMatch>
<Files ".htaccess">
    Require all denied
</Files>
<Files "config.php">
    Require all denied
</Files>
EOF

echo "✅ Configuraciones Apache y PHP-FPM creadas."

echo "--- 🗃️ Asegurando que el directorio del repositorio Restic exista en ${RESTIC_REPOSITORY} ---"
sudo mkdir -p "$RESTIC_REPOSITORY"
sudo chown -R $USER:$USER "$RESTIC_REPOSITORY"

echo "--- 📝 Creando script de backup incremental en scripts/backup.sh ---"
cat << 'EOF' > scripts/backup.sh
#!/bin/bash
set -eo pipefail
error_exit() { echo "❌ ERROR: $1" >&2; logger -t nextcloud_backup "ERROR: $1"; exit 1; }
log_message() { echo "$1"; logger -t nextcloud_backup "$1"; }
ENV_FILE="$(dirname "$0")/../.env"
if [ ! -f "$ENV_FILE" ]; then error_exit "No se encontró el archivo .env"; fi
set -a; source "$ENV_FILE"; set +a
for var in RESTIC_REPOSITORY APP_DATA_PATH POSTGRES_USER_NC POSTGRES_DB_NC POSTGRES_USER_OO POSTGRES_DB_OO RESTIC_PASSWORD JELLYFIN_CONFIG_PATH; do
    if [ -z "${!var}" ]; then error_exit "Variable $var no está definida en .env"; fi
done
if ! command -v restic &> /dev/null; then error_exit "Restic no está instalado"; fi
if ! command -v zstd &> /dev/null; then
    log_message "⚠️ zstd no está instalado. Intentando instalar..."
    if command -v apt-get &> /dev/null; then sudo apt-get update && sudo apt-get install -y zstd || error_exit "No se pudo instalar zstd";
    elif command -v dnf &> /dev/null; then sudo dnf install -y zstd || error_exit "No se pudo instalar zstd";
    else error_exit "No se pudo determinar el gestor de paquetes para instalar zstd"; fi
    log_message "✅ zstd instalado correctamente"
fi
if [ ! -f /etc/restic_password ]; then error_exit "El archivo /etc/restic_password no existe"; fi
log_message "🗃️ Iniciando backup incremental con Restic..."
TMP_DIR=$(mktemp -d -t nextcloud-backup-XXXXXX) || error_exit "No se pudo crear directorio temporal"
chmod 700 "$TMP_DIR"
trap 'log_message "Limpiando... Desactivando modo de mantenimiento."; docker exec -u www-data nextcloud-app-server php occ maintenance:mode --off > /dev/null 2>&1; sudo rm -rf "$TMP_DIR"' EXIT
if ! restic -r "$RESTIC_REPOSITORY" --password-file /etc/restic_password cat config >/dev/null 2>&1; then
    log_message "🔧 Inicializando nuevo repositorio Restic..."
    restic -r "$RESTIC_REPOSITORY" --password-file /etc/restic_password init || error_exit "No se pudo inicializar el repositorio Restic"
fi
log_message "⚠️ Activando modo de mantenimiento de Nextcloud..."
docker exec -u www-data nextcloud-app-server php occ maintenance:mode --on || error_exit "No se pudo activar el modo de mantenimiento"
log_message "💾 Respaldando bases de datos en paralelo..."
(docker exec -u postgres nextcloud-postgres-db pg_dump --clean -U "$POSTGRES_USER_NC" -d "$POSTGRES_DB_NC" | zstd -T0 -1 > "$TMP_DIR/nextcloud_db.sql.zst") &
(docker exec -u postgres onlyoffice-postgres-db pg_dump --clean -U "$POSTGRES_USER_OO" -d "$POSTGRES_DB_OO" | zstd -T0 -1 > "$TMP_DIR/onlyoffice_db.sql.zst") &
wait || error_exit "Fallo en el dump de una de las bases de datos"
log_message "📸 Creando snapshot incremental..."
DATE_TAG=$(date +%F_%H-%M-%S)
sudo restic -r "$RESTIC_REPOSITORY" --password-file /etc/restic_password backup \
    --tag "$DATE_TAG" --tag "nextcloud-stack" \
    --exclude-caches \
    "$APP_DATA_PATH" "$(dirname "$0")/../" "$TMP_DIR" "$JELLYFIN_CONFIG_PATH" || error_exit "No se pudo crear el snapshot"
log_message "✅ Desactivando modo de mantenimiento de Nextcloud..."
docker exec -u www-data nextcloud-app-server php occ maintenance:mode --off || error_exit "No se pudo desactivar el modo de mantenimiento"
log_message "🧹 Purgando backups antiguos..."
restic -r "$RESTIC_REPOSITORY" --password-file /etc/restic_password forget \
    --keep-daily "${RESTIC_KEEP_DAILY:-7}" \
    --keep-weekly "${RESTIC_KEEP_WEEKLY:-4}" \
    --keep-monthly "${RESTIC_KEEP_MONTHLY:-12}" \
    --prune || error_exit "No se pudo purgar backups antiguos"
log_message "🔍 Verificando integridad del repositorio..."
restic -r "$RESTIC_REPOSITORY" --password-file /etc/restic_password check --read-data-subset=5% || error_exit "La verificación de integridad falló"
log_message "🎉 ✅ Backup incremental completado con éxito!"
EOF
chmod +x scripts/backup.sh

echo "--- 📝 Creando script de restauracion en scripts/restore.sh ---"
cat << 'EOF' > scripts/restore.sh
#!/bin/bash
set -eo pipefail
error_exit() { echo "❌ ERROR: $1" >&2; exit 1; }
ENV_FILE="$(dirname "$0")/../.env"
if [ ! -f "$ENV_FILE" ]; then error_exit "No se encontró el archivo .env"; fi
set -a; source "$ENV_FILE"; set +a
for var in RESTIC_REPOSITORY APP_DATA_PATH POSTGRES_USER_NC POSTGRES_DB_NC POSTGRES_USER_OO POSTGRES_DB_OO; do
    if [ -z "${!var}" ]; then error_exit "Variable $var no está definida en .env"; fi
done
if ! command -v restic &> /dev/null; then error_exit "Restic no está instalado."; fi
if ! command -v zstd &> /dev/null; then error_exit "zstd no está instalado."; fi
if ! command -v docker &> /dev/null; then error_exit "Docker no está instalado."; fi
if ! command -v docker compose &> /dev/null; then error_exit "Docker Compose no está instalado."; fi
if [ ! -f /etc/restic_password ]; then error_exit "El archivo /etc/restic_password no existe"; fi
echo "🔄 Iniciando restauración desde snapshot..."
echo "🔍 Verificando integridad del repositorio..."
restic -r "$RESTIC_REPOSITORY" --password-file /etc/restic_password check || error_exit "La verificación de integridad del repositorio falló"
echo "📋 Snapshots disponibles:"
restic -r "$RESTIC_REPOSITORY" --password-file /etc/restic_password snapshots || error_exit "No se pudieron listar los snapshots"
read -p "❓ Por favor, ingrese el ID del snapshot a restaurar (o 'latest'): " SNAPSHOT_ID
if [ -z "$SNAPSHOT_ID" ]; then error_exit "ID no ingresado. Abortando."; fi
echo "⚠️ ¡ADVERTENCIA! Esto SOBREESCRIBIRÁ los datos en $APP_DATA_PATH y $JELLYFIN_CONFIG_PATH."
read -p "❓ ¿Está seguro de continuar? (escriba 'CONFIRMO' para proceder): " CONFIRM
if [ "$CONFIRM" != "CONFIRMO" ]; then error_exit "Operación cancelada."; fi
echo "🛑 Deteniendo contenedores..."
docker compose down -v || echo "⚠️  No se pudieron detener los contenedores (quizás ya estaban detenidos). Continuando..."
echo "🧹 Limpiando datos antiguos..."
sudo rm -rf "$APP_DATA_PATH" "$JELLYFIN_CONFIG_PATH"
sudo mkdir -p "$APP_DATA_PATH" "$JELLYFIN_CONFIG_PATH" || error_exit "No se pudieron limpiar/crear los directorios de datos antiguos"
TMP_DIR=$(mktemp -d -t nextcloud-restore-XXXXXX) || error_exit "No se pudo crear directorio temporal"
chmod 700 "$TMP_DIR"
trap 'sudo rm -rf "$TMP_DIR"' EXIT
echo "📦 Restaurando datos desde el snapshot..."
sudo restic -r "$RESTIC_REPOSITORY" --password-file /etc/restic_password restore "$SNAPSHOT_ID" --target / || error_exit "No se pudo restaurar los datos del snapshot"
echo "✅ Datos de $APP_DATA_PATH y del proyecto restaurados."
echo "📤 Extrayendo dumps de bases de datos al directorio temporal..."
sudo restic -r "$RESTIC_REPOSITORY" --password-file /etc/restic_password restore "$SNAPSHOT_ID" --target "$TMP_DIR" --path "/tmp" || error_exit "No se pudieron extraer los dumps."
NC_DUMP_FILE=$(sudo find "$TMP_DIR" -type f -name "nextcloud_db.sql.zst" | head -n 1)
OO_DUMP_FILE=$(sudo find "$TMP_DIR" -type f -name "onlyoffice_db.sql.zst" | head -n 1)
if [ -z "$NC_DUMP_FILE" ] || ! sudo test -f "$NC_DUMP_FILE"; then error_exit "No se pudo encontrar el dump de la DB de Nextcloud."; fi
if [ -z "$OO_DUMP_FILE" ] || ! sudo test -f "$OO_DUMP_FILE"; then error_exit "No se pudo encontrar el dump de la DB de OnlyOffice."; fi
echo "✅ Dumps de bases de datos localizados."
echo "🚀 Levantando solo las bases de datos..."
docker compose up -d db_nextcloud db_onlyoffice || error_exit "No se pudieron iniciar las bases de datos"
echo "⏳ Esperando 20 segundos a que las bases de datos se inicien..."
sleep 20
echo "🔍 Verificando que las bases de datos estén listas..."
docker exec nextcloud-postgres-db pg_isready -U "$POSTGRES_USER_NC" || error_exit "La DB de Nextcloud no está lista"
docker exec onlyoffice-postgres-db pg_isready -U "$POSTGRES_USER_OO" || error_exit "La DB de OnlyOffice no está lista"
echo "🤫 Restaurando base de datos de Nextcloud..."
sudo zstd -d -c "$NC_DUMP_FILE" | docker exec -i nextcloud-postgres-db psql -q -U "$POSTGRES_USER_NC" -d "$POSTGRES_DB_NC" > /dev/null || error_exit "No se pudo restaurar la DB de Nextcloud"
echo "🤫 Restaurando base de datos de OnlyOffice..."
sudo zstd -d -c "$OO_DUMP_FILE" | docker exec -i onlyoffice-postgres-db psql -q -U "$POSTGRES_USER_OO" -d "$POSTGRES_DB_OO" > /dev/null || error_exit "No se pudo restaurar la DB de OnlyOffice"
echo "✅ Bases de datos restauradas."
echo "🚀 Levantando todos los servicios..."
docker compose up -d || error_exit "No se pudieron iniciar todos los servicios"
echo "⏳ Esperando hasta 60 segundos para la inicialización final de Nextcloud..."
sleep 60
docker exec -u www-data nextcloud-app-server php occ status || echo "⚠️ Nextcloud tardó en responder, se continuará de todas formas."
echo "🔧 Ejecutando reparaciones finales..."
docker exec -u www-data nextcloud-app-server php occ maintenance:repair --include-expensive
docker exec -u www-data nextcloud-app-server php occ db:add-missing-indices
docker exec -u www-data nextcloud-app-server php occ db:convert-filecache-bigint --no-interaction
docker exec -u www-data nextcloud-app-server php occ maintenance:mode --off
echo "🎉 ✅ Restauración completada con éxito!"
EOF
chmod +x scripts/restore.sh

echo "✅ Scripts de backup y restore creados."

echo "--------------------------------------------------------"
echo "🛠️ ASIGNANDO PERMISOS Y DESPLEGANDO..."
echo "--------------------------------------------------------"

# ✅ CORRECCIÓN CLAVE: PERMISOS DE JELLYFIN (evita fallo al inicio)
echo "--- 🔐 Asegurando permisos correctos para Jellyfin ---"
sudo mkdir -p "$JELLYFIN_CONFIG_PATH"
sudo chown -R ${PUID}:${PGID} "$JELLYFIN_CONFIG_PATH"
sudo chmod -R 755 "$JELLYFIN_CONFIG_PATH"
echo "✅ Permisos de Jellyfin corregidos."

echo "🔑 Asignando permisos con IDs fijos..."
sudo chown -R 33:33 "$APP_DATA_PATH/nextcloud/html"
sudo chown -R 70:70 "$APP_DATA_PATH/nextcloud/database"
sudo chown -R 999:999 "$APP_DATA_PATH/onlyoffice/database"
sudo chown -R 998:998 "$APP_DATA_PATH/onlyoffice/lib" "$APP_DATA_PATH/onlyoffice/logs"
echo "✅ Permisos asignados."

echo "⬆️ Levantando stack (la primera vez construirá la imagen de Apache, puede tardar un minuto)..."
docker compose up -d --build --remove-orphans

echo ""
echo "--------------------------------------------------------"
echo "✨ CONFIGURACION FINAL"
echo "--------------------------------------------------------"
echo "⏳ Esperando inicialización de contenedores..."
while [ "$(docker inspect --format='{{.State.Status}}' nextcloud-app-server)" != "running" ] || [ "$(docker inspect --format='{{.State.Status}}' nextcloud-apache)" != "running" ]; do sleep 10; echo -n "."; done
echo ""
echo "✅ Contenedores FPM y Apache ejecutándose!"
echo "⏳ Esperando inicialización completa de Nextcloud (puede tardar hasta 3 minutos)..."
sleep 90
echo "🔍 Verificando que la instalación de Nextcloud finalice..."
RETRY_COUNT=0
MAX_RETRIES=18
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if docker exec -u www-data nextcloud-app-server test -f /var/www/html/config/config.php && \
       docker exec -u www-data nextcloud-app-server grep -q "'installed' => true," /var/www/html/config/config.php; then
        echo ""; echo "✅ Nextcloud completamente instalado y confirmado!"; break
    else
        echo -n "."; sleep 10; RETRY_COUNT=$((RETRY_COUNT + 1))
    fi
done
if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo ""; echo "❌ ERROR: Nextcloud no finalizó la instalación a tiempo."; exit 1
fi

# === CONFIGURACIÓN DE ONLYOFFICE CON VERIFICACIÓN ===
echo "🔧 Configurando OnlyOffice con verificación de salud..."

docker exec -u www-data nextcloud-app-server php occ app:enable onlyoffice || {
    echo "❌ No se pudo habilitar la app OnlyOffice"; exit 1;
}

echo "⏳ Esperando a que OnlyOffice esté listo..."
RETRY_COUNT=0
MAX_RETRIES=20
until curl -f -s "http://$(echo ${NEXTCLOUD_TRUSTED_DOMAINS} | cut -d' ' -f1):${ONLYOFFICE_PORT}/healthcheck" >/dev/null 2>&1 || \
       docker exec documentserver_onlyoffice curl -f -s http://localhost/healthcheck >/dev/null 2>&1; do
    echo -n "."
    sleep 10
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo ""
        echo "❌ ERROR: OnlyOffice no respondió después de 200 segundos."
        exit 1
    fi
done
echo ""
echo "✅ OnlyOffice está listo."

docker exec -u www-data nextcloud-app-server php occ config:app:set onlyoffice DocumentServerUrl --value="${ONLYOFFICE_PUBLIC_URL%/}/"
docker exec -u www-data nextcloud-app-server php occ config:app:set onlyoffice DocumentServerInternalUrl --value="http://documentserver_onlyoffice/"
docker exec -u www-data nextcloud-app-server php occ config:app:set onlyoffice jwt_secret --value="${JWT_SECRET}"
docker exec -u www-data nextcloud-app-server php occ config:app:set onlyoffice jwt_header --value="Authorization"
docker exec -u www-data nextcloud-app-server php occ config:app:set onlyoffice jwt_in_body --value="1"
echo "✅ OnlyOffice configurado y verificado."

# === OPTIMIZACIONES DE RENDIMIENTO EFICIENTES ===
echo "⚡ Aplicando optimizaciones esenciales..."
# ... (configuraciones previas ya están)

# ✅ Caché de Redis optimizada (bajo consumo)
echo "⚡ Optimizando Redis..."
docker exec nextcloud-redis redis-cli -a "${REDIS_HOST_PASSWORD}" config set maxmemory 256mb
docker exec nextcloud-redis redis-cli -a "${REDIS_HOST_PASSWORD}" config set maxmemory-policy allkeys-lru

# ✅ Vistas previas eficientes
echo "🖼️ Configurando generador de vistas previas (eficiente)..."
docker exec -u www-data nextcloud-app-server php occ app:enable previewgenerator
docker exec -u www-data nextcloud-app-server php occ config:app:set previewgenerator squareSizes --value="32 256"
docker exec -u www-data nextcloud-app-server php occ config:app:set previewgenerator widthSizes --value="256"
docker exec -u www-data nextcloud-app-server php occ config:app:set previewgenerator heightSizes --value="256"

echo "🎬 Habilitando aplicaciones multimedia..."
docker exec -u www-data nextcloud-app-server php occ app:enable viewer

# === ALMACENAMIENTO EXTERNO ===
echo "🔗 Configurando almacenamiento externo para Jellyfin en Nextcloud..."
sleep 15
docker exec -u www-data nextcloud-app-server php occ app:enable files_external
docker exec -u www-data nextcloud-app-server php occ files_external:create "Multimedia" "local" "null::null"
docker exec -u www-data nextcloud-app-server php occ files_external:config "1" "datadir" "${APP_DATA_PATH}/multimedia"
docker exec -u www-data nextcloud-app-server php occ files_external:applicable --add-user "${NEXTCLOUD_ADMIN_USER}" "1"
echo "✅ Carpeta 'Multimedia' conectada a Jellyfin."

# === REPARACIONES FINALES ===
echo "🔧 Ejecutando reparaciones finales..."
docker exec -u www-data nextcloud-app-server php occ maintenance:repair --include-expensive
docker exec -u www-data nextcloud-app-server php occ db:add-missing-indices
docker exec -u www-data nextcloud-app-server php occ db:convert-filecache-bigint --no-interaction

echo ""
echo "🎉 ============================================================="
echo "🎉 DESPLIEGUE COMPLETADO CON EXITO!"
echo "🎉 ============================================================="
echo ""
echo "📊 ARQUITECTURA DESPLEGADA:"
echo "   ✅ Nextcloud FPM (Procesamiento PHP)"
echo "   ✅ Apache HTTP (Servidor Web + Proxy) con HTTP/2"
echo "   ✅ PostgreSQL (Base de datos)"
echo "   ✅ Redis (Cache)"
echo "   ✅ OnlyOffice Document Server"
echo "   ✅ Jellyfin Media Server"
echo ""
echo "📱 ACCESO WEB:"
echo "   Nextcloud: http://$(echo ${NEXTCLOUD_TRUSTED_DOMAINS} | cut -d' ' -f1):${NEXTCLOUD_PORT}"
echo "   OnlyOffice: http://$(echo ${NEXTCLOUD_TRUSTED_DOMAINS} | cut -d' ' -f1):${ONLYOFFICE_PORT}"
echo "   Jellyfin:   http://$(echo ${NEXTCLOUD_TRUSTED_DOMAINS} | cut -d' ' -f1):${JELLYFIN_PORT}"
echo ""
echo "🔐 CREDENCIALES:"
echo "   Usuario: ${NEXTCLOUD_ADMIN_USER}"
echo "   Contraseña: ${NEXTCLOUD_ADMIN_PASSWORD}"
echo ""
echo "🗂️ DATOS ALMACENADOS EN:"
echo "   ${APP_DATA_PATH}"
echo "   ${JELLYFIN_CONFIG_PATH}"
echo ""
echo "💾 SCRIPTS DE BACKUP:"
echo "   ./scripts/backup.sh  - Crear backup incremental"
echo "   ./scripts/restore.sh - Restaurar desde backup"
echo ""
echo "============================================================="
echo "🎯 PROXIMOS PASOS:"
echo "============================================================="
echo "1. 🌐 Accede a tus servicios y verifica el funcionamiento"
echo "2. 🎬 Configura tus bibliotecas multimedia en Jellyfin"
echo "3. 💾 Programa el backup: sudo crontab -e -> 0 2 * * * /ruta/a/tu/proyecto/scripts/backup.sh"
echo "4. 🔄 Ejecuta el primer backup manualmente: sudo ./scripts/backup.sh"
echo "============================================================="
echo ""
echo "✨ ¡Stack completo y listo para producción! ✨"