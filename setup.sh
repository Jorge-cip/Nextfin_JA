#!/bin/bash
set -e

# ====================================================================================
# SCRIPT DE CONFIGURACION, INSTALACION Y GESTION PARA NEXTCLOUD + ONLYOFFICE + JELLYFIN
# VERSION FPM + APACHE SEPARADOS PARA PRODUCCION - v7.5 (AJUSTE FINO DE SCRIPTS DE OPTIMIZACIÓN)
# ====================================================================================

# --- PARSING DE ARGUMENTOS ---
ASSUME_YES_INSTALL=false
for arg in "$@"; do
    case $arg in
        --assume-yes|--non-interactive)
        ASSUME_YES_INSTALL=true
        shift # Remove --assume-yes or --non-interactive from processing
        ;; 
        *)
        # unknown option
        ;;esac
done
# --- FIN PARSING DE ARGUMENTOS ---

# --- PARTE 1: PREPARACION DEL ENTORNO Y DEPENDENCIAS ---
echo "--------------------------------------------------------"
echo "🚀 INICIANDO DESPLIEGUE NEXTCLOUD FPM + APACHE + ONLYOFFICE + JELLYFIN 🚀"
echo "--------------------------------------------------------"

# ------------------------------------------------------------------
# INSTALACIÓN AUTOMÁTICA DE DOCKER ENGINE + DOCKER COMPOSE v2
# ------------------------------------------------------------------
echo "--------------------------------------------------------"
echo "🔧 Verificando Docker Engine y Docker Compose v2..."

# Instalar Docker Engine si no está presente
if ! command -v docker &>/dev/null; then
    echo "⚠️  Docker Engine no encontrado. Instalando automáticamente..."
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker $USER
    echo "⚠️  Docker Engine instalado. Para que los permisos se apliquen correctamente, cierra y vuelve a entrar en tu sesión antes de continuar."
    exit 0
fi

# Verificar e instalar Docker Compose v2 como plugin
DOCKER_COMPOSE_PLUGIN_DIR="/usr/lib/docker/cli-plugins"
DOCKER_COMPOSE_BIN="$DOCKER_COMPOSE_PLUGIN_DIR/docker-compose"

if ! docker compose version &>/dev/null; then
    echo "⚠️  Docker Compose v2 no encontrado. Instalando plugin..."
    sudo mkdir -p "$DOCKER_COMPOSE_PLUGIN_DIR"
    sudo curl -SL \
      "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
      -o "$DOCKER_COMPOSE_BIN"
    sudo chmod +x "$DOCKER_COMPOSE_BIN"

    if docker compose version &>/dev/null; then
        echo "✅ Docker Compose v2 instalado correctamente."
        docker compose version
    else
        echo "❌ No se pudo instalar Docker Compose v2 automáticamente."
        exit 1
    fi
else
    echo "✅ Docker Compose v2 ya está instalado."
    docker compose version
fi
# ------------------------------------------------------------------
# FIN BLOQUE DOCKER + COMPOSE
# ------------------------------------------------------------------

# Verificación de dependencias mejorada
declare -A DEPENDENCIAS=(
    [restic]="restic"
    [docker]="docker"
    [ffmpeg]="ffmpeg"
    [ffprobe]="ffmpeg"
    [jq]="jq"
    [bc]="bc"
    [wget]="wget"
    [unzip]="unzip"
    [convert]="imagemagick" # El comando es 'convert', el paquete es 'imagemagick'
)

# --- INSTALACIÓN AUTOMÁTICA DE DOCKER COMPOSE v2 ---
echo "--------------------------------------------------------"
echo "🔧 Verificando Docker Compose v2..."

DOCKER_COMPOSE_PLUGIN_DIR="/usr/lib/docker/cli-plugins"
DOCKER_COMPOSE_BIN="$DOCKER_COMPOSE_PLUGIN_DIR/docker-compose"

if ! docker compose version &>/dev/null; then
    echo "⚠️  'docker compose' no está disponible. Instalando Docker Compose v2 plugin..."

    sudo mkdir -p "$DOCKER_COMPOSE_PLUGIN_DIR"

    # --- URL SIN ESPACIOS ---
    sudo curl -SL \
      "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
      -o "$DOCKER_COMPOSE_BIN"

    sudo chmod +x "$DOCKER_COMPOSE_BIN"

    if docker compose version &>/dev/null; then
        echo "✅ Docker Compose v2 instalado correctamente como plugin de Docker."
        docker compose version
    else
        echo "❌ No se pudo instalar Docker Compose v2 automáticamente. Instala manualmente."
        exit 1
    fi
else
    echo "✅ Docker Compose v2 ya está instalado."
    docker compose version
fi

for cmd in "${!DEPENDENCIAS[@]}"; do
    if ! command -v $cmd &> /dev/null; then
        pkg_to_install="${DEPENDENCIAS[$cmd]}"
        echo "⚠️ La herramienta '$cmd' (del paquete '$pkg_to_install') no está instalada. Es necesaria."
        if $ASSUME_YES_INSTALL; then
            echo "   -> Instalando '$pkg_to_install' automáticamente (--assume-yes)..."
            if command -v apt-get &> /dev/null; then sudo apt-get update && sudo apt-get install -y "$pkg_to_install";
            elif command -v dnf &> /dev/null; then sudo dnf install -y "$pkg_to_install";
            elif command -v yum &> /dev/null; then sudo yum install -y "$pkg_to_install";
            else echo "    ❌ No se pudo determinar el gestor de paquetes. Por favor, instale '$pkg_to_install' manualmente." >&2; exit 1; fi
            echo "✅ El paquete '$pkg_to_install' fue instalado correctamente."
        else
            read -p "❓ Desea intentar instalarla ahora? (s/n): " INSTALL_PKG
            if [[ "$INSTALL_PKG" == "s" || "$INSTALL_PKG" == "S" ]]; then
                if command -v apt-get &> /dev/null; then sudo apt-get update && sudo apt-get install -y "$pkg_to_install";
                else echo "    ❌ No se pudo determinar el gestor de paquetes. Por favor, instale '$pkg_to_install' manualmente." >&2; exit 1; fi
                echo "✅ El paquete '$pkg_to_install' fue instalado correctamente."
            else
                echo "❌ Despliegue cancelado. '$cmd' es obligatorio." >&2; exit 1;
            fi
        fi
    fi
done
echo "--- ✅ Dependencias verificadas. ---"

echo "--- 📋 Cargando configuracion desde .env ---"
if [ -f .env ]; then
    set -a; source .env; set +a;
else
    echo "❌ ERROR: No se encontro el archivo .env." >&2; exit 1;
fi

echo "--- 🔐 Asegurando que el archivo de contraseña para Restic esté actualizado ---"
echo "$RESTIC_PASSWORD" | sudo tee /etc/restic_password > /dev/null
sudo chmod 600 /etc/restic_password
sudo chown $USER:$USER /etc/restic_password
echo "    ✅ Archivo /etc/restic_password sincronizado con .env."

echo "--- 📁 Creando estructura de directorios ---"
sudo mkdir -p "$APP_DATA_PATH/nextcloud/html" \
              "$APP_DATA_PATH/nextcloud/database" \
              "$APP_DATA_PATH/onlyoffice/database" \
              "$APP_DATA_PATH/onlyoffice/logs" \
              "$APP_DATA_PATH/onlyoffice/lib" \
              "$APP_DATA_PATH/multimedia" \
              "$JELLYFIN_CONFIG_PATH" \
              "$MULTIMEDIA_PATH" \
              "$PAPELERA_MEDIA_PATH" # <-- Creación de la nueva carpeta de respaldo
mkdir -p ./scripts ./nextcloud_config ./apache_image

echo "--- 🔐 Asegurando permisos colaborativos en la carpeta multimedia ---"
sudo chown -R 33:${PGID} "${MULTIMEDIA_PATH}"
sudo chmod -R 775 "${MULTIMEDIA_PATH}"
sudo chmod -R g+s "${MULTIMEDIA_PATH}"
echo "✅ Permisos de la carpeta ${MULTIMEDIA_PATH} configurados para colaboración."

# --- Permisos colaborativos para Papelera_media ---
sudo chown -R 33:${PGID} "${PAPELERA_MEDIA_PATH}"
sudo chmod -R 775 "${PAPELERA_MEDIA_PATH}"
sudo chmod -R g+s "${PAPELERA_MEDIA_PATH}"
echo "✅ Permisos de la carpeta ${PAPELERA_MEDIA_PATH} configurados para colaboración."
echo "✅ Directorios creados y permisos asignados."

echo "--- 🐋 Creando Dockerfile para Apache con HTTP/2 ---"
cat << 'EOF' > ./apache_image/Dockerfile
FROM httpd:2.4-alpine
# Forzar la recreación del usuario www-data con UID/GID 33
RUN apk update && \
    (delgroup www-data 2>/dev/null || true) && \
    (deluser www-data 2>/dev/null || true) && \
    addgroup -g 33 www-data && \
    adduser -u 33 -D -G www-data -h /var/www -s /sbin/nologin www-data && \
    apk add --no-cache apache2-http2 brotli
EOF
echo "✅ Dockerfile creado."

echo "--- 🔧 Generando configuraciones PHP-FPM y Apache ---"
cat << EOF > ./nextcloud_config/uploads.ini
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
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=10000
opcache.validate_timestamps=0
opcache.revalidate_freq=600
opcache.fast_shutdown=1
opcache.save_comments=1
opcache.max_wasted_percentage=10
apc.enabled=1
apc.shm_size=256M
apc.enable_cli=1
realpath_cache_size=20M
realpath_cache_ttl=7200
session.save_handler = redis
session.save_path = "tcp://redis_nextcloud:6379?auth=${REDIS_HOST_PASSWORD}"
session.gc_maxlifetime = 86400
; --- Optimizacion con JIT (Just-In-Time) ---
opcache.jit_buffer_size=128M
opcache.jit=tracing
EOF
cat << EOF > ./nextcloud_config/www.conf
[www]
user = www-data
group = www-data
listen = 9000
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
listen.backlog = 511
pm = dynamic
pm.max_children = 15
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

cat > ./nextcloud_config/httpd.conf <<EOF
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
LoadModule brotli_module modules/mod_brotli.so
LoadModule filter_module modules/mod_filter.so
LoadModule env_module modules/mod_env.so
LoadModule expires_module modules/mod_expires.so
LoadModule setenvif_module modules/mod_setenvif.so
LoadModule alias_module modules/mod_alias.so
LoadModule log_config_module modules/mod_log_config.so
LoadModule unixd_module modules/mod_unixd.so
User www-data
Group www-data
# --- Ajuste fino: compatibilidad con clientes móviles y reenvío de IP real ---
LoadModule remoteip_module modules/mod_remoteip.so
RemoteIPHeader X-Forwarded-For
RemoteIPTrustedProxy 172.18.0.0/16
SetEnvIf X-Forwarded-Proto https HTTPS=on
# --- Fin ajuste fino ---
ServerName localhost
ServerAdmin admin@localhost
DocumentRoot "/var/www/html"
DirectoryIndex index.php index.html
Protocols h2c http/1.1
ServerTokens Prod
ServerSignature Off
Timeout 300
KeepAlive On
MaxKeepAliveRequests 200
KeepAliveTimeout 2
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
<IfModule mod_brotli.c>
    AddOutputFilterByType BROTLI_COMPRESS text/html text/plain text/xml text/css text/javascript application/javascript application/json application/xml application/rss+xml
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
cat << 'EOF' > ./nextcloud_config/nextcloud.conf
<Directory "/var/www/html">
    Options -Indexes +FollowSymLinks
    AllowOverride All
    Require all granted
    <FilesMatch "\.php$">
        SetHandler "proxy:fcgi://nextcloud-app-server:9000"
    </FilesMatch>
</Directory>
<LocationMatch "\.(css|js|woff2?|eot|ttf|otf|png|jpe?g|gif|svg|ico|pdf)$"> 
    Header set Cache-Control "public, immutable, max-age=31536000"
</LocationMatch>
<Location "/apps/onlyoffice"> 
    ExpiresActive On
    ExpiresDefault "access plus 1 week"
    Header append Cache-Control "public, immutable"
</Location>
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

echo "--- 🗃️ Asegurando que el directorio del repositorio Restic exista ---"
sudo mkdir -p "$RESTIC_REPOSITORY"
# Se recomienda que el repositorio Restic sea propiedad de root y tenga permisos restrictivos
# para mayor seguridad, ya que los backups pueden contener datos sensibles.
sudo chown -R root:root "$RESTIC_REPOSITORY"
sudo chmod -R 700 "$RESTIC_REPOSITORY"

echo "--- 📝 Creando scripts de backup y restore en ./scripts ---"
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
    "$APP_DATA_PATH" "$(dirname "$0")/../" "$TMP_DIR" "$JELLYFIN_CONFIG_PATH" "$MULTIMEDIA_PATH" || error_exit "No se pudo crear el snapshot"
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
echo "⚠️ ¡ADVERTENCIA! Esto SOBREESCRIBIRÁ los datos en $APP_DATA_PATH, $JELLYFIN_CONFIG_PATH y $MULTIMEDIA_PATH."
read -p "❓ ¿Está seguro de continuar? (escriba 'CONFIRMO' para proceder): " CONFIRM
if [ "$CONFIRM" != "CONFIRMO" ]; then error_exit "Operación cancelada."; fi
echo "🛑 Deteniendo contenedores..."
docker compose down -v || echo "⚠️  No se pudieron detener los contenedores (quizás ya estaban detenidos). Continuando..."
echo "🧹 Limpiando datos antiguos..."
sudo rm -rf "$APP_DATA_PATH" "$JELLYFIN_CONFIG_PATH" "$MULTIMEDIA_PATH"
sudo mkdir -p "$APP_DATA_PATH" "$JELLYFIN_CONFIG_PATH" "$MULTIMEDIA_PATH" || error_exit "No se pudieron limpiar/crear los directorios de datos antiguos"
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
docker exec -u www-data nextcloud-app-server php occ files:scan --all

echo "🎉 ✅ Restauración completada con éxito!"
EOF
chmod +x scripts/restore.sh
echo "✅ Scripts de backup y restore creados."

# --- [INICIO DE LA MODIFICACIÓN QUIRÚRGICA] ---

echo "--- 🤖 Creando script de optimización de VIDEO INTERACTIVO en scripts/optimizer_videos.sh ---"
cat << 'EOF' > scripts/optimizer_videos.sh
#!/bin/bash
# ====================================================================================
# SCRIPT UNIFICADO PARA OPTIMIZACIÓN Y ESTANDARIZACIÓN DE VIDEOS
# ====================================================================================
set -e

# --- Colores y Emojis ---
C_BLUE="\033[1;34m"
C_YELLOW="\033[1;33m"
C_GREEN="\033[1;32m"
C_RED="\033[1;31m"
C_RESET="\033[0m"
E_ROCKET="🚀"
E_TADA="🎉"
E_CHECK="✅"
E_CROSS="❌"
E_INFO="ℹ️"
E_BOX="📦"
E_LOCK="🔐"
E_WRENCH="🔧"
E_HOURGLASS="⏳"
E_RUNNER="🏃"
E_WAVE="👋"
E_SWEEP="🧹"

echo -e "${C_BLUE}-- ${E_ROCKET} INICIANDO SCRIPT DE GESTIÓN DE VIDEOS --${C_RESET}"

# --- Cargar Configuración ---
SCRIPT_DIR=$(cd -- \
$(dirname -- "${BASH_SOURCE[0]}") &>/dev/null && pwd)
ENV_FILE="$(dirname "$SCRIPT_DIR")/.env"

if [ -f "$ENV_FILE" ]; then
    echo -e "${C_GREEN}Cargando configuración desde $ENV_FILE...${C_RESET}"
    set -a; source "$ENV_FILE"; set +a
else
    echo -e "${C_RED}${E_CROSS} ERROR: No se encontró el archivo .env. Saliendo.${C_RESET}"
    exit 1
fi

if [ -z "$PAPELERA_MEDIA_PATH" ] || [ -z "$MULTIMEDIA_PATH" ] || [ -z "$PGID" ]; then
    echo -e "${C_RED}${E_CROSS} ERROR: Variables requeridas no definidas en .env. Saliendo.${C_RESET}"
    exit 1
fi
mkdir -p "$PAPELERA_MEDIA_PATH"

# ====================================================================================
# PARÁMETROS GLOBALES DE FFMPEG
# ====================================================================================

# --- Para Optimización de Antiguos ---
target_video_width=1920
target_video_height=1080
video_crf=23
video_preset="medium"
audio_bitrate="128k"

# --- Para Estandarización ---
STANDARDIZE_VIDEO_OPTS_FAST="-c:v copy"
STANDARDIZE_VIDEO_OPTS_RECODE="-c:v libx264 -r 30 -profile:v high -level 4.1 -crf 22 -pix_fmt yuv420p -color_trc smpte170m"
STANDARDIZE_AUDIO_OPTS="-c:a aac -b:a 128k -ac 2"

# ====================================================================================
# FUNCIÓN: Mover a la papelera, ajustar permisos y actualizar índice
# ====================================================================================
finalize_process() {
    local old_file="$1"
    local new_file="$2"
    local original_basename=$(basename "$old_file")

    echo -e " -> ${E_BOX} Moviendo archivo original a la papelera: $old_file"
    sudo mv "$old_file" "$PAPELERA_MEDIA_PATH/"

    if [ -f "$new_file" ]; then
        echo -e " -> ${E_LOCK} Ajustando permisos para $new_file..."
        sudo chown 33:$PGID "$new_file"
        sudo chmod 664 "$new_file"

        echo -e " -> ${E_SWEEP} Actualizando índice de Nextcloud (esto puede tardar un poco)..."
        docker exec -u www-data nextcloud-app-server php occ files:scan --all

        echo -e " -> ${E_TADA} Proceso completado para $original_basename."
    else
        echo -e " -> ${C_RED}${E_CROSS} ERROR: El archivo de salida $new_file no fue encontrado.${C_RESET}"
        return 1
    fi
}

# ====================================================================================
# SECCIÓN 1: OPTIMIZACIÓN DE VIDEOS ANTIGUOS
# ====================================================================================

# --- FUNCIÓN: Procesa un solo video (Modo Antiguo) ---
process_single_video_ancient() {
    local input_file="$1"
    local original_basename=$(basename "$input_file")
    local output_dir=$(dirname "$input_file")
    local output_file="$output_dir/${original_basename%.*}.mp4"

    echo "--------------------------------------------------------"
    echo -e "${C_BLUE}PROCESANDO (Antiguo): $input_file${C_RESET}"

    if [ ! -f "$input_file" ]; then
        echo -e " -> ${C_RED}${E_CROSS} ERROR: El archivo de entrada no existe. Omitiendo.${C_RESET}"
        return 1
    fi

    if [ "$input_file" == "$output_file" ]; then
        echo -e " -> ${C_YELLOW}${E_INFO} El archivo ya está en formato MP4. Omitiendo.${C_RESET}"
        return 0
    fi

    local probe_data=$(ffprobe -v quiet -print_format json -show_streams "$input_file" 2>/dev/null)
    if [ -z "$probe_data" ]; then
        echo -e " -> ${C_RED}${E_CROSS} ERROR: No se pudo obtener información de FFprobe. Omitiendo.${C_RESET}"
        return 1
    fi
    local field_order=$(echo "$probe_data" | jq -r '.streams[]? | select(.codec_type=="video") | .field_order' | head -n 1)

    local vf_chain="scale=${target_video_width:-1920}:${target_video_height:-1080}:flags=lanczos,hqdn3d"
    if [[ "$field_order" != "progressive" && -n "$field_order" ]]; then
        echo -e " -> ${E_INFO} Video entrelazado detectado. Aplicando desentrelazado (yadif)."
        vf_chain="yadif,${vf_chain}"
    fi

    echo -e " -> ${E_RUNNER} Ejecutando FFmpeg para optimizar (lento)..."
    ffmpeg -i "$input_file" \
        -vf "$vf_chain" \
        -c:v libx264 -crf "${VIDEO_CRF:-23}" -preset "${VIDEO_PRESET:-medium}" \
        -pix_fmt yuv420p \
        -c:a aac -b:a "${AUDIO_BITRATE:-128k}" \
        -map_metadata 0 \
        -y "$output_file"

    if [ $? -eq 0 ]; then
        echo -e " -> ${C_GREEN}${E_CHECK} Optimización (antiguo) exitosa.${C_RESET}"
        finalize_process "$input_file" "$output_file"
    else
        echo -e " -> ${C_RED}${E_CROSS} ERROR: El procesamiento con FFmpeg falló.${C_RESET}"
        rm -f "$output_file"
        return 1
    fi
    return 0
}


# --- FUNCIÓN: Detecta si un video es 'antiguo' ---
is_ancient_video() {
    local video_file="$1"
    local probe_data
    probe_data=$(ffprobe -v quiet -print_format json -show_format -show_streams "$video_file" 2>/dev/null)
    if [ -z "$probe_data" ]; then return 1; fi

    local video_data
    video_data=$(echo "$probe_data" | jq -r ' 
        [.streams[]? | select(.codec_type=="video")][0] | 
        if . then
            "\(.codec_name // "") \(.width // 0) \(.height // 0) \(.field_order // "")"
        else
            ""
        end
    ')

    if [ -z "$video_data" ]; then return 1; fi

    local video_codec width height field_order
    read -r video_codec width height field_order <<< "$video_data"

    local audio_codec
    audio_codec=$(echo "$probe_data" | jq -r '([.streams[]? | select(.codec_type=="audio")][0] | .codec_name) // ""')

    local is_video_codec_obsolete=1
    case "$video_codec" in "mpeg2video"|"msmpeg4"|"wmv1"|"wmv2"|"h263") is_video_codec_obsolete=0 ;; esac

    local is_resolution_low=1
    if [[ "$width" -le 720 || "$height" -le 576 ]]; then is_resolution_low=0; fi

    local is_interlaced=1
    if [[ "$field_order" != "progressive" && -n "$field_order" ]]; then is_interlaced=0; fi

    if [[ "$is_video_codec_obsolete" -eq 0 && ("$is_resolution_low" -eq 0 || "$is_interlaced" -eq 0) ]]; then return 0; fi

    local is_audio_codec_obsolete=1
    case "$audio_codec" in "mp2"|"ac3") is_audio_codec_obsolete=0 ;; esac

    if [[ "$is_audio_codec_obsolete" -eq 0 && "$is_resolution_low" -eq 0 ]]; then return 0; fi

    return 1
}

# --- FUNCIÓN: Ejecuta el flujo de optimización de videos antiguos ---
run_ancient_video_optimizer() {
    echo "--------------------------------------------------------"
    echo -e "${E_HOURGLASS} Buscando videos con características antiguas (esto puede tardar)..."

    mapfile -d '' ALL_VIDEO_FILES < <(find "$MULTIMEDIA_PATH" -type f \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.mpg" -o -iname "*.mpeg" \) -print0)
    
    ANCIENT_VIDEO_FILES=()
    for file in "${ALL_VIDEO_FILES[@]}"; do
        if [[ -n "$file" ]] && is_ancient_video "$file"; then
            ANCIENT_VIDEO_FILES+=("$file")
        fi
    done

    while true; do
        if [ ${#ANCIENT_VIDEO_FILES[@]} -eq 0 ]; then
            echo "--------------------------------------------------------"
            echo -e "${C_GREEN}${E_CHECK} ¡No quedan videos antiguos para optimizar! Volviendo al menú principal.${C_RESET}"
            sleep 2
            break
        fi

        echo "--------------------------------------------------------"
        echo -e "${C_YELLOW}Encontrados ${#ANCIENT_VIDEO_FILES[@]} videos antiguos para procesar.${C_RESET}"

        declare -A FOLDER_SIZES
        for file in "${ANCIENT_VIDEO_FILES[@]}"; do
            if [[ -z "$file" ]]; then continue; fi
            dir=$(dirname "$file")
            if [[ -z "$dir" ]]; then continue; fi
            [[ -z "${FOLDER_SIZES[$dir]}" ]] && FOLDER_SIZES[$dir]=0
            file_size=$(du -b "$file" | awk '{print $1}')
            FOLDER_SIZES[$dir]=$((FOLDER_SIZES[$dir] + file_size))
        done

        mapfile -t FOLDER_MENU_OPTIONS < <(for dir in "${!FOLDER_SIZES[@]}"; do
            size_bytes=${FOLDER_SIZES[$dir]}
            size_human=$(numfmt --to=iec-i --suffix=B --format="%.1f" $size_bytes)
            echo "$size_bytes|($size_human) $dir"
        done | sort -n | cut -d'|' -f2-)

        TEMP_VIDEO_DATA=""
        for file in "${ANCIENT_VIDEO_FILES[@]}"; do
            size_bytes=$(du -b "$file" | awk '{print $1}')
            size_human=$(numfmt --to=iec-i --suffix=B --format="%.1f" $size_bytes)
            TEMP_VIDEO_DATA+="$size_bytes|($size_human) $file\n"
        done
        mapfile -t VIDEO_MENU_OPTIONS < <(echo -e "$TEMP_VIDEO_DATA" | sed '/^$/d' | sort -n | cut -d'|' -f2-)

        PS3="\nSelecciona una opción para videos antiguos: "
        options=("Procesar por carpeta" "Procesar individualmente" "Volver al menú principal")
        select opt in "${options[@]}"; do
            case $opt in
                "Procesar por carpeta")
                    PS3="Selecciona la carpeta a procesar: "
                    select folder_opt in "${FOLDER_MENU_OPTIONS[@]}" "PROCESAR TODAS" "VOLVER"; do
                        if [[ "$folder_opt" == "VOLVER" ]]; then break; fi
                        if [[ "$folder_opt" == "PROCESAR TODAS" ]]; then
                            TARGET_PATH="$MULTIMEDIA_PATH"
                        else
                            TARGET_PATH=$(echo "$folder_opt" | awk '{$1=""; print $0}' | sed 's/^ *//')
                        fi

                        VIDEOS_TO_PROCESS=()
                        for file in "${ANCIENT_VIDEO_FILES[@]}"; do
                            if [[ "$TARGET_PATH" == "$MULTIMEDIA_PATH" || "$(dirname "$file")" == "$TARGET_PATH" ]]; then
                                VIDEOS_TO_PROCESS+=("$file")
                            fi
                        done

                        echo -e "\nSe procesarán ${#VIDEOS_TO_PROCESS[@]} videos en $TARGET_PATH."
                        read -p "¿Confirmar? [s/N]: " confirm
                        if [[ "$confirm" =~ ^[sS]([íÍ])?$ ]]; then
                            for video in "${VIDEOS_TO_PROCESS[@]}"; do
                                process_single_video_ancient "$video"
                            done
                            TEMP_FILES=()
                            for f in "${ANCIENT_VIDEO_FILES[@]}"; do
                                is_processed=false
                                for pf in "${VIDEOS_TO_PROCESS[@]}"; do [[ "$f" == "$pf" ]] && is_processed=true && break; done
                                if ! $is_processed; then TEMP_FILES+=("$f"); fi
                            done
                            ANCIENT_VIDEO_FILES=("${TEMP_FILES[@]}")
                            echo -e "\n--- ${C_GREEN}${E_CHECK} Procesamiento de carpeta completado. ---"
                        else
                            echo "Cancelado."
                        fi
                        break
                    done
                    break
                    ;;
                "Procesar individualmente")
                    PS3="Selecciona el video a procesar: "
                    select video_opt in "${VIDEO_MENU_OPTIONS[@]}" "VOLVER"; do
                        if [[ "$video_opt" == "VOLVER" ]]; then break; fi
                        TARGET_FILE=$(echo "$video_opt" | awk '{$1=""; print $0}' | sed 's/^ *//')
                        process_single_video_ancient "$TARGET_FILE"
                        TEMP_FILES=()
                        for f in "${ANCIENT_VIDEO_FILES[@]}"; do [[ "$f" != "$TARGET_FILE" ]] && TEMP_FILES+=("$f"); done
                        ANCIENT_VIDEO_FILES=("${TEMP_FILES[@]}")
                        break
                    done
                    break
                    ;;
                "Volver al menú principal")
                    return
                    ;;
                *)
                    echo "Opción inválida."
                    ;;
            esac
        done
    done
}


# ====================================================================================
# SECCIÓN 2: ESTANDARIZACIÓN DE FORMATO DE VIDEO
# ====================================================================================

# --- FUNCIÓN: Procesa un solo video (Modo Estandarizar) ---
process_single_video_standardize() {
    local input_file="$1"
    echo "--------------------------------------------------------"
    echo -e "${C_BLUE}PROCESANDO (Estandarizar): $input_file${C_RESET}"

    if [ ! -f "$input_file" ]; then
        echo -e " -> ${C_RED}${E_CROSS} ERROR: El archivo de entrada no existe. Omitiendo.${C_RESET}"
        return 1
    fi

    local probe_data=$(ffprobe -v error -show_format -show_streams -of json "$input_file" 2>/dev/null)
    if [ -z "$probe_data" ]; then
        echo -e " -> ${C_RED}${E_CROSS} ERROR: No se pudo obtener información de FFprobe. Omitiendo.${C_RESET}"
        return 1
    fi

    local audio_codec=$(echo "$probe_data" | jq -r '.streams[]? | select(.codec_type=="audio") | .codec_name' | head -n 1)
    local frame_rate_frac=$(echo "$probe_data" | jq -r '.streams[]? | select(.codec_type=="video") | .avg_frame_rate' | head -n 1)
    local frame_rate=$(echo "scale=2; $frame_rate_frac" | bc)
    local format=$(echo "$probe_data" | jq -r '.format.format_name')
    local has_subtitles=$(echo "$probe_data" | jq -r '.streams[]? | select(.codec_type=="subtitle") | .codec_name' | head -n 1)

    local video_opts="$STANDARDIZE_VIDEO_OPTS_FAST"
    local needs_conversion=false

    if [[ "$format" != "mov,mp4,m4a,3gp,3g2,mj2" || "$audio_codec" != "aac" || -n "$has_subtitles" ]]; then
        needs_conversion=true
    fi

    if (( $(echo "$frame_rate < 23" | bc -l) )); then
        echo -e " -> ${E_INFO} FPS bajos detectados (<23). Se necesita re-codificación de VIDEO."
        video_opts="$STANDARDIZE_VIDEO_OPTS_RECODE"
        needs_conversion=true
    fi

    if [ "$needs_conversion" = true ]; then
        local original_basename=$(basename -- "$input_file")
        local output_dir=$(dirname -- "$input_file")
        local output_filename="${original_basename%.*}.mp4"
        local temp_output_file="$output_dir/temp_$output_filename"
        local final_output_file="$output_dir/$output_filename"

        echo " -> El archivo necesita conversión. El archivo final será: $final_output_file"
        echo -e " -> ${E_RUNNER} Ejecutando FFmpeg para estandarizar..."

        ffmpeg -i "$input_file" -map 0:v:0 -map 0:a:0 \
            $video_opts \
            $STANDARDIZE_AUDIO_OPTS \
            -f mp4 "$temp_output_file" -y

        if [ $? -eq 0 ] && [ -s "$temp_output_file" ]; then
            echo -e " -> ${C_GREEN}${E_CHECK} Estandarización a temporal exitosa.${C_RESET}"
            if [ -f "$final_output_file" ] && [ "$input_file" != "$final_output_file" ]; then
                 echo -e "    ${C_YELLOW}⚠️  ADVERTENCIA: El archivo de destino $final_output_file ya existe. Se sobrescribirá.${C_RESET}"
            fi
            mv "$temp_output_file" "$final_output_file"
            finalize_process "$input_file" "$final_output_file"
        else
            echo -e " -> ${C_RED}${E_CROSS} ERROR: La conversión con ffmpeg falló. No se realizarán cambios.${C_RESET}"
            rm -f "$temp_output_file"
            return 1
        fi
    else
        echo -e " -> ${C_GREEN}${E_CHECK} El archivo ya cumple con el estándar. No se requiere acción.${C_RESET}"
        return 2
    fi
    return 0
}

# --- FUNCIÓN: Detecta si un video necesita estandarización ---
is_standardization_needed() {
    local video_file="$1"
    local probe_data=$(ffprobe -v quiet -print_format json -show_format -show_streams "$video_file" 2>/dev/null)
    if [ -z "$probe_data" ]; then return 1; fi

    local audio_codec=$(echo "$probe_data" | jq -r '.streams[]? | select(.codec_type=="audio") | .codec_name' | head -n 1)
    local frame_rate_frac=$(echo "$probe_data" | jq -r '.streams[]? | select(.codec_type=="video") | .avg_frame_rate' | head -n 1)
    local frame_rate=$(echo "scale=2; $frame_rate_frac" | bc)
    local format=$(echo "$probe_data" | jq -r '.format.format_name')
    local has_subtitles=$(echo "$probe_data" | jq -r '.streams[]? | select(.codec_type=="subtitle") | .codec_name' | head -n 1)

    if [[ "$format" != "mov,mp4,m4a,3gp,3g2,mj2" || "$audio_codec" != "aac" || -n "$has_subtitles" ]]; then return 0; fi
    if (( $(echo "$frame_rate < 23" | bc -l) )); then return 0; fi

    return 1
}

# --- FUNCIÓN: Ejecuta el flujo de estandarización de videos ---
run_standardize_video_formatter() {
    echo "--------------------------------------------------------"
    echo -e "${E_HOURGLASS} Buscando videos que no cumplan el estándar (esto puede tardar)..."

    mapfile -d '' ALL_VIDEO_FILES < <(find "$MULTIMEDIA_PATH" -type f \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.mpg" -o -iname "*.mpeg" \) -print0)

    NON_STANDARD_FILES=()
    for file in "${ALL_VIDEO_FILES[@]}"; do
        if [[ -n "$file" ]] && is_standardization_needed "$file"; then
            NON_STANDARD_FILES+=("$file")
        fi
    done

    while true; do
        if [ ${#NON_STANDARD_FILES[@]} -eq 0 ]; then
            echo "--------------------------------------------------------"
            echo -e "${C_GREEN}${E_CHECK} ¡No quedan videos para estandarizar! Volviendo al menú principal.${C_RESET}"
            sleep 2
            break
        fi

        echo "--------------------------------------------------------"
        echo -e "${C_YELLOW}Encontrados ${#NON_STANDARD_FILES[@]} videos que no cumplen el estándar.${C_RESET}"

        declare -A FOLDER_SIZES
        for file in "${NON_STANDARD_FILES[@]}"; do
            dir=$(dirname "$file")
            [[ -z "${FOLDER_SIZES[$dir]}" ]] && FOLDER_SIZES[$dir]=0
            file_size=$(du -b "$file" | awk '{print $1}')
            FOLDER_SIZES[$dir]=$((FOLDER_SIZES[$dir] + file_size))
        done

        mapfile -t FOLDER_MENU_OPTIONS < <(for dir in "${!FOLDER_SIZES[@]}"; do
            size_bytes=${FOLDER_SIZES[$dir]}
            size_human=$(numfmt --to=iec-i --suffix=B --format="%.1f" $size_bytes)
            echo "$size_bytes|($size_human) $dir"
        done | sort -n | cut -d'|' -f2-)

        TEMP_VIDEO_DATA=""
        for file in "${NON_STANDARD_FILES[@]}"; do
            size_bytes=$(du -b "$file" | awk '{print $1}')
            size_human=$(numfmt --to=iec-i --suffix=B --format="%.1f" $size_bytes)
            TEMP_VIDEO_DATA+="$size_bytes|($size_human) $file\n"
        done
        mapfile -t VIDEO_MENU_OPTIONS < <(echo -e "$TEMP_VIDEO_DATA" | sed '/^$/d' | sort -n | cut -d'|' -f2-)

        PS3="\nSelecciona una opción para estandarizar: "
        options=("Procesar por carpeta" "Procesar individualmente" "Volver al menú principal")
        select opt in "${options[@]}"; do
            case $opt in
                "Procesar por carpeta")
                    PS3="Selecciona la carpeta a procesar: "
                    select folder_opt in "${FOLDER_MENU_OPTIONS[@]}" "PROCESAR TODAS" "VOLVER"; do
                        if [[ "$folder_opt" == "VOLVER" ]]; then break; fi
                        if [[ "$folder_opt" == "PROCESAR TODAS" ]]; then
                            TARGET_PATH="$MULTIMEDIA_PATH"
                        else
                            TARGET_PATH=$(echo "$folder_opt" | awk '{$1=""; print $0}' | sed 's/^ *//')
                        fi

                        VIDEOS_TO_PROCESS=()
                        for file in "${NON_STANDARD_FILES[@]}"; do
                            if [[ "$TARGET_PATH" == "$MULTIMEDIA_PATH" || "$(dirname "$file")" == "$TARGET_PATH" ]]; then
                                VIDEOS_TO_PROCESS+=("$file")
                            fi
                        done

                        echo -e "\nSe procesarán ${#VIDEOS_TO_PROCESS[@]} videos en $TARGET_PATH."
                        read -p "¿Confirmar? [s/N]: " confirm
                        if [[ "$confirm" =~ ^[sS]([íÍ])?$ ]]; then
                            PROCESSED_IN_BATCH=()
                            for video in "${VIDEOS_TO_PROCESS[@]}"; do
                                process_single_video_standardize "$video"
                                if [ $? -ne 2 ]; then
                                    PROCESSED_IN_BATCH+=("$video")
                                fi
                            done
                            TEMP_FILES=()
                            for f in "${NON_STANDARD_FILES[@]}"; do
                                is_processed=false
                                for pf in "${PROCESSED_IN_BATCH[@]}"; do [[ "$f" == "$pf" ]] && is_processed=true && break; done
                                if ! $is_processed; then TEMP_FILES+=("$f"); fi
                            done
                            NON_STANDARD_FILES=("${TEMP_FILES[@]}")
                            echo -e "\n--- ${C_GREEN}${E_CHECK} Procesamiento de carpeta completado. ---"
                        else
                            echo "Cancelado."
                        fi
                        break
                    done
                    break
                    ;;
                "Procesar individualmente")
                    PS3="Selecciona el video a procesar: "
                    select video_opt in "${VIDEO_MENU_OPTIONS[@]}" "VOLVER"; do
                        if [[ "$video_opt" == "VOLVER" ]]; then break; fi
                        TARGET_FILE=$(echo "$video_opt" | awk '{$1=""; print $0}' | sed 's/^ *//')
                        process_single_video_standardize "$TARGET_FILE"
                        if [ $? -ne 2 ]; then
                            TEMP_FILES=()
                            for f in "${NON_STANDARD_FILES[@]}"; do [[ "$f" != "$TARGET_FILE" ]] && TEMP_FILES+=("$f"); done
                            NON_STANDARD_FILES=("${TEMP_FILES[@]}")
                        fi
                        break
                    done
                    break
                    ;;
                "Volver al menú principal")
                    return
                    ;;
                *)
                    echo "Opción inválida."
                    ;;
            esac
        done
    done
}


# ====================================================================================
# MENÚ PRINCIPAL
# ====================================================================================
while true; do
    echo "--------------------------------------------------------"
    echo -e "${C_BLUE}MENU PRINCIPAL${C_RESET}"
    echo "--------------------------------------------------------"
    PS3="¿Qué tarea deseas realizar? "
    options=(
        "Optimizar videos antiguos (Proceso lento, re-codificación completa)"
        "Estandarizar formato de video (Proceso rápido, solo convierte si es necesario)"
        "Actualizar índice de Nextcloud"
        "Salir"
    )
    select main_opt in "${options[@]}"; do
        case $main_opt in
            "Optimizar videos antiguos (Proceso lento, re-codificación completa)")
                run_ancient_video_optimizer
                break
                ;;
            "Estandarizar formato de video (Proceso rápido, solo convierte si es necesario)")
                run_standardize_video_formatter
                break
                ;;
            "Actualizar índice de Nextcloud")
                echo -e "--- ${E_SWEEP} ACTUALIZANDO ÍNDICE DE ARCHIVOS DE NEXTCLOUD (puede tardar) ---"
                docker exec -u www-data nextcloud-app-server php occ files:scan --all
                echo -e "--- ${C_GREEN}${E_CHECK} Índice de Nextcloud actualizado. ---"
                break
                ;;
            "Salir")
                echo -e "${E_WAVE} Saliendo del script."
                exit 0
                ;;
            *)
                echo "Opción inválida. Inténtalo de nuevo."
                break
                ;;
        esac
    done
done

echo -e "--- ${E_TADA} SCRIPT DE GESTIÓN DE VIDEOS FINALIZADO ---"
EOF
chmod +x scripts/optimizer_videos.sh
echo "✅ Script 'optimizer_videos.sh' (con respaldo de originales) creado."

# --- [FIN DE LA MODIFICACIÓN QUIRÚRGICA] ---

echo "--- ✨ Creando script de escalado de IMÁGENES en scripts/optimizer_images.sh ---"
cat << 'EOF' > scripts/optimizer_images.sh
#!/bin/bash

# =================================================================================
# =      SCRIPT DE OPTIMIZACIÓN DE IMÁGENES v5.0 (Consistente con Video)         #
# =================================================================================
#
# - Homologado con el script de video para consistencia.
# - Requiere sudo para ajustar permisos para Nextcloud.
# - Optimiza las imágenes y las reemplaza en su lugar.
# - Mueve los archivos originales a la papelera (`PAPELERA_MEDIA_PATH`).
# - Al finalizar un lote, ejecuta automáticamente un escaneo de Nextcloud.
# - Optimiza en paralelo usando todos los núcleos de la CPU.
#
# --------------------------------------------------------------------------------- 

# --- Colores y Emojis ---
C_BLUE="\033[1;34m"
C_YELLOW="\033[1;33m"
C_GREEN="\033[1;32m"
C_RED="\033[1;31m"
C_RESET="\033[0m"
E_ROCKET="🚀"
E_TADA="🎉"
E_CHECK="✅"
E_CROSS="❌"
E_INFO="ℹ️"
E_BOX="📦"
E_LOCK="🔐"
E_WRENCH="🔧"
E_HOURGLASS="⏳"
E_RUNNER="🏃"
E_WAVE="👋"
E_SWEEP="🧹"
E_GEAR="⚙️"
E_IMG="🖼️"

echo -e "${C_BLUE}--- ${E_ROCKET} INICIANDO SCRIPT DE OPTIMIZACIÓN DE IMÁGENES ---${C_RESET}"

# --- 1. VERIFICACIÓN DE DEPENDENCIAS Y ENTORNO ---
 echo -e "${C_BLUE}Verificando requisitos...${C_RESET}"
for cmd in convert nproc docker identify; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${C_RED}${E_CROSS} Error: El comando '$cmd' no está instalado. Por favor, instálalo.${C_RESET}"
        exit 1
    fi
done

if [[ ! -f ".env" ]]; then
    echo -e "${C_RED}${E_CROSS} Error: No se encontró el archivo .env.${C_RESET}"
    exit 1
fi

set -o allexport
source .env
set +o allexport

if [[ -z "$TARGET_WIDTH" || -z "$MULTIMEDIA_PATH" || -z "$PAPELERA_MEDIA_PATH" || -z "$PGID" ]]; then
    echo -e "${C_RED}${E_CROSS} Error: Asegúrate de que TARGET_WIDTH, MULTIMEDIA_PATH, PAPELERA_MEDIA_PATH y PGID estén en .env.${C_RESET}"
    exit 1
fi

for path_var in "MULTIMEDIA_PATH" "PAPELERA_MEDIA_PATH"; do
    if [[ ! -d "${!path_var}" ]]; then
        echo -e "${C_RED}${E_CROSS} Error: El directorio de $path_var (${!path_var}) no existe.${C_RESET}"
        exit 1
    fi
done

CPU_CORES=$(nproc)
 echo -e "${C_GREEN}${E_CHECK} Requisitos cumplidos. Usando $CPU_CORES núcleos.${C_RESET}"
 echo -e "${C_GREEN}${E_INFO} Ancho estándar: $TARGET_WIDTH px. Ruta de medios: $MULTIMEDIA_PATH. Papelera: $PAPELERA_MEDIA_PATH${C_RESET}"

# --- 2. FUNCIÓN DE PROCESAMIENTO (PARA XARGS) ---
export TARGET_WIDTH PAPELERA_MEDIA_PATH MULTIMEDIA_PATH PGID C_GREEN C_RED C_RESET E_CHECK E_CROSS E_LOCK E_BOX E_GEAR
process_image() {
    img_path=$1
    sharpen_opt=$2
    temp_path="${img_path}.tmp"

    echo -e "${E_GEAR} Procesando: $(basename -- "$img_path")"
    
    # 1. Optimizar a un archivo temporal
    convert "$img_path" -strip -quality 85 -resize "${TARGET_WIDTH}" -interlace Plane $sharpen_opt "$temp_path"

    # 2. Si la optimización fue exitosa, reemplazar el original
    if [ $? -eq 0 ]; then
        # 2a. Mover el original a la papelera
        trash_relative_path=${img_path#$MULTIMEDIA_PATH/}
        trash_path="$PAPELERA_MEDIA_PATH/$trash_relative_path"
        trash_dir_for_file=$(dirname "$trash_path")
        mkdir -p "$trash_dir_for_file"
        sudo mv "$img_path" "$trash_path"

        # 2b. Mover el temporal al lugar del original
        mv "$temp_path" "$img_path"

        # 2c. Ajustar permisos para Nextcloud
        sudo chown 33:$PGID "$img_path"
        sudo chmod 664 "$img_path"
        
        echo -e "${C_GREEN}${E_CHECK} Reemplazado: $(basename -- "$img_path")${C_RESET}"
    else
        # 3. Si la optimización falló, limpiar el temporal
        rm -f "$temp_path"
        echo -e "${C_RED}${E_CROSS} ERROR al procesar: $(basename -- "$img_path")${C_RESET}"
    fi
}
export -f process_image

# --- 3. BUCLE PRINCIPAL DEL MENÚ ---
BASE_DIR=$MULTIMEDIA_PATH

while true; do
    echo -e "
${C_BLUE}Buscando carpetas con imágenes en $BASE_DIR...${C_RESET}"
    
    DIR_LIST=$(find "$BASE_DIR" -type f -iregex '.*\.\(jpg\|jpeg\|png\|webp\)' -printf "%h\n" | sort -u)
    
    if [ -z "$DIR_LIST" ]; then
        echo -e "${C_RED}No se encontraron carpetas con imágenes en la ruta $BASE_DIR.${C_RESET}"
        exit 1
    fi

    MENU_OPTIONS=()
    SORTED_LIST=$(echo "$DIR_LIST" | xargs -d '\n' du -sk | sort -n)

    while read -r line; do
        if [ -z "$line" ]; then continue; fi
        dir=$(echo "$line" | awk '{$1=""; print $0}' | sed 's/^ *//')
        size_human=$(du -sh "$dir" | awk '{print $1}')
        relative_dir=${dir#$BASE_DIR/}
        MENU_OPTIONS+=("$dir" "$relative_dir ($size_human)")
    done <<< "$SORTED_LIST"

    echo -e "
--- ${E_IMG} ELIGE LA CARPETA A OPTIMIZAR ---"
    i=0
    while [ $i -lt ${#MENU_OPTIONS[@]} ]; do
        echo "  [$((i/2+1))] ${MENU_OPTIONS[i+1]}"
        i=$((i+2))
    done
    echo "  [0] Salir"
    echo "-------------------------------------"

    read -p "Ingresa el número de tu elección: " choice

    if [[ "$choice" == "0" ]]; then
        echo -e "
${C_BLUE}${E_WAVE} Saliendo del script.${C_RESET}"
        exit 0
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt $((${#MENU_OPTIONS[@]}/2)) ]; then
        echo -e "${C_RED}Opción no válida. Inténtalo de nuevo.${C_RESET}"
        continue
    fi

    CHOSEN_DIR=${MENU_OPTIONS[($choice-1)*2]}

    echo -e "
${C_BLUE}Verificando si las imágenes en '$CHOSEN_DIR' ya están estandarizadas...${C_RESET}"
    image_list_for_check=$(find "$CHOSEN_DIR" -type f -iregex '.*\.\(jpg\|jpeg\|png\|webp\)')
    
    if [ -z "$image_list_for_check" ]; then
        echo -e "${C_GREEN}No se encontraron imágenes en esta carpeta.${C_RESET}"
        continue
    fi

    all_images_are_standard=true
    images_to_process=()
    while IFS= read -r img_path; do
        width=$(identify -format "%w" "$img_path" 2>/dev/null || echo "0")
        if [ "$width" != "$TARGET_WIDTH" ]; then
            all_images_are_standard=false
            images_to_process+=("$img_path")
        fi
    done <<< "$image_list_for_check"

    if [ "$all_images_are_standard" = true ]; then
        echo -e "${C_GREEN}${E_CHECK} ¡Excelente! Todas las imágenes en esta carpeta ya tienen el ancho estándar de ${TARGET_WIDTH}px.${C_RESET}"
        read -n 1 -s -r -p "Presiona cualquier tecla para volver al menú..."
        continue
    fi

    read -p "¿Deseas aplicar un filtro de nitidez (unsharp mask)? (s/n): " apply_sharpen
    SHARPEN_OPTION=""
    if [[ "$apply_sharpen" =~ ^[sS]$ ]]; then
        SHARPEN_OPTION="-unsharp 0x.5"
    fi

    total_to_process=${#images_to_process[@]}
    echo -e "
${C_YELLOW}Se van a procesar $total_to_process imágenes en paralelo.${C_RESET}"
    read -p "¿Continuar? (s/n): " confirm_run

    if [[ "$confirm_run" =~ ^[sS]$ ]]; then
        echo -e "
${C_BLUE}${E_RUNNER} Iniciando optimización en paralelo...${C_RESET}"
        printf "%s\0" "${images_to_process[@]}" | xargs -0 -P "$CPU_CORES" -I {} bash -c 'process_image "$@"' _ {} "$SHARPEN_OPTION"
        echo -e "
${C_GREEN}${E_TADA} ¡Optimización completada para $CHOSEN_DIR!${C_RESET}"

        echo -e "
${C_BLUE}${E_SWEEP} Ejecutando escaneo de Nextcloud para actualizar los cambios (puede tardar)...${C_RESET}"
        docker exec --user www-data nextcloud-app-server php occ files:scan --all
        echo -e "${C_GREEN}${E_CHECK} Escaneo de Nextcloud finalizado.${C_RESET}"
    else
        echo -e "${C_RED}Operación cancelada.${C_RESET}"
    fi
done
EOF
chmod +x scripts/optimizer_images.sh
echo "✅ Script 'optimizer_images.sh' (con respaldo de originales) creado y listo para usar."

# --- [FIN DE LA MODIFICACIÓN QUIRÚRGICA] ---

echo "--------------------------------------------------------"
echo "🛠️ ASIGNANDO PERMISOS Y DESPLEGANDO..."
echo "--------------------------------------------------------"

echo "--- 🔐 Asegurando permisos correctos para Jellyfin ---"
sudo mkdir -p "$JELLYFIN_CONFIG_PATH"
sudo chown -R ${PUID}:${PGID} "$JELLYFIN_CONFIG_PATH"
sudo chmod -R 755 "$JELLYFIN_CONFIG_PATH"
echo "✅ Permisos de Jellyfin corregidos."

echo "🔑 Asignando permisos con IDs fijos para datos internos..."
sudo chown -R 33:33 "$APP_DATA_PATH/nextcloud/html"
sudo chown -R 70:70 "$APP_DATA_PATH/nextcloud/database"
sudo chown -R 999:999 "$APP_DATA_PATH/onlyoffice/database"
sudo chown -R 998:998 "$APP_DATA_PATH/onlyoffice/lib" "$APP_DATA_PATH/onlyoffice/logs"
echo "✅ Permisos internos asignados."

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
RETRY_COUNT=0
MAX_RETRIES=18 # 18 reintentos * 10 segundos = 180 segundos (3 minutos)
FIRST_DOMAIN=$(echo ${NEXTCLOUD_TRUSTED_DOMAINS} | cut -d' ' -f1)
until docker exec -u www-data nextcloud-app-server php occ status >/dev/null 2>&1; do
    echo -n "."
    sleep 10
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo ""
        echo "❌ ERROR: Nextcloud no respondió después de 180 segundos."
        exit 1
    fi
done
echo ""
echo "✅ Nextcloud completamente instalado y confirmado!"
echo "⏳ Dando un tiempo adicional para que Nextcloud termine de inicializarse..."
sleep 30 # Espera adicional para asegurar que todos los comandos 'occ' estén disponibles

# --- [MODIFICACIÓN] AJUSTE PARA COMPATIBILIDAD CON APP MÓVIL ---
# Se han comentado las directivas 'overwrite' para permitir el acceso multi-IP sin redirección.
# Nextcloud determinará el host y el protocolo dinámicamente desde la solicitud entrante.
# Esto es ideal para tu caso de uso con múltiples IPs en una red local.
# docker exec -u www-data nextcloud-app-server php occ config:system:set overwritehost --value="${FIRST_DOMAIN}:${NEXTCLOUD_PORT}"
# docker exec -u www-data nextcloud-app-server php occ config:system:set overwriteprotocol --value="http"
# Para la URL de la CLI, es mejor establecer una que sea genérica y funcione internamente.
docker exec -u www-data nextcloud-app-server php occ config:system:set overwrite.cli.url --value="http://localhost:${NEXTCLOUD_PORT}"
echo "✅ Directivas 'overwrite' ajustadas para acceso multi-IP."

# --- Configurando trusted_proxies para el proxy inverso (Apache) ---
echo "--- 🌐 Configurando trusted_proxies para Nextcloud ---"
# Limpieza idempotente de trusted_proxies (elimina todos los índices previos)
for i in $(seq 0 9); do
  docker exec -u www-data nextcloud-app-server php occ config:system:delete trusted_proxies $i 2>/dev/null || true
done

# --- [MODIFICADO] Lógica simplificada y robusta para trusted_proxies ---
# Se usará el nombre del servicio 'nextcloud-apache' directamente.
# Docker lo resolverá a la IP correcta dentro de la red interna.
APACHE_SERVICE_NAME="nextcloud-apache"
docker exec -u www-data nextcloud-app-server php occ config:system:set trusted_proxies 0 --value="$APACHE_SERVICE_NAME"
echo "✅ Contenedor de Apache ('$APACHE_SERVICE_NAME') añadido a trusted_proxies."

# --- FIN DE LA MODIFICACIÓN ---

# --- Configurando trusted_domains de forma idempotente (multi-dominio) ---
echo "--- 🌐 Configurando trusted_domains para Nextcloud ---"
# Limpia todos los trusted_domains previos
for i in $(seq 0 9); do
  docker exec -u www-data nextcloud-app-server php occ config:system:delete trusted_domains $i 2>/dev/null || true
done
# Agrega todos los dominios de la variable, uno por uno
i=0
for domain in $NEXTCLOUD_TRUSTED_DOMAINS; do
  docker exec -u www-data nextcloud-app-server php occ config:system:set trusted_domains $i --value="$domain"
  i=$((i+1))
done
echo "✅ Dominios añadidos a trusted_domains: $NEXTCLOUD_TRUSTED_DOMAINS"
# --- FIN DE LA MODIFICACIÓN ---


# --- Ajustes para compatibilidad total con clientes móviles y redes externas ---
docker exec -u www-data nextcloud-app-server php occ config:system:set forwarded_for_headers 0 --value="HTTP_X_FORWARDED_FOR"
docker exec -u www-data nextcloud-app-server php occ config:system:set rate_limit --value="1000"
docker exec -u www-data nextcloud-app-server php occ config:system:set session_lifetime --value="86400"
docker exec -u www-data nextcloud-app-server php occ config:system:set session_keepalive --value="false"

# === CONFIGURACIÓN DE ONLYOFFICE CON VERIFICACIÓN ===
echo "🔧 Configurando OnlyOffice con verificación de salud..."

docker exec -u www-data nextcloud-app-server php occ app:enable onlyoffice || {
    echo "❌ No se pudo habilitar la app OnlyOffice"; exit 1;
}

echo "⏳ Esperando a que OnlyOffice esté listo..."
RETRY_COUNT=0
MAX_RETRIES=20
until curl -f -s "http://${FIRST_DOMAIN}:${ONLYOFFICE_PORT}/healthcheck" >/dev/null 2>&1 || \
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

# Fuerza un refresh de la app OnlyOffice (simula el “Guardar” manual)
docker exec -u www-data nextcloud-app-server php occ app:disable onlyoffice
docker exec -u www-data nextcloud-app-server php occ app:enable onlyoffice

echo "✅ OnlyOffice configurado y verificado."

# === MEJORAS DE CACHÉ Y DESHABILITAR APPS INNECESARIAS ===
docker exec -u www-data nextcloud-app-server php occ config:system:set memcache.local --value='\OC\Memcache\APCu'
docker exec -u www-data nextcloud-app-server php occ config:system:set memcache.locking --value='\OC\Memcache\Redis'
docker exec -u www-data nextcloud-app-server php occ config:system:set memcache.distributed --value='\OC\Memcache\Redis'
docker exec -u www-data nextcloud-app-server php occ app:disable recommendations
docker exec -u www-data nextcloud-app-server php occ app:disable survey_client
docker exec -u www-data nextcloud-app-server php occ app:disable federation

# === OPTIMIZACIONES DE RENDIMIENTO EFICIENTES ===
echo "⚡ Aplicando optimizaciones esenciales..."
docker exec nextcloud-redis redis-cli -a "${REDIS_HOST_PASSWORD}" config set maxmemory 256mb
docker exec nextcloud-redis redis-cli -a "${REDIS_HOST_PASSWORD}" config set maxmemory-policy allkeys-lru

echo "🖼️ Configurando generador de vistas previas (eficiente)..."
docker exec -u www-data nextcloud-app-server php occ app:enable previewgenerator
docker exec -u www-data nextcloud-app-server php occ config:app:set previewgenerator squareSizes --value="32 256"
docker exec -u www-data nextcloud-app-server php occ config:app:set previewgenerator widthSizes --value="256"
docker exec -u www-data nextcloud-app-server php occ config:app:set previewgenerator heightSizes --value="256"

# === HABILITANDO APLICACIONES MULTIMEDIA ===
echo "🎬 Habilitando aplicaciones multimedia..."
docker exec -u www-data nextcloud-app-server php occ app:enable viewer

# === ALMACENAMIENTO EXTERNO (MODO ROBUSTO) ===
echo "🔗 Habilitando y configurando almacenamiento externo (modo robusto)..."
docker exec -u www-data nextcloud-app-server php occ app:enable files_external || echo "   -> (Info) La app 'files_external' ya está habilitada."
echo "   -> Verificando/Creando grupo 'media_users' en Nextcloud..."
docker exec -u www-data nextcloud-app-server php occ group:add media_users || echo "   -> (Info) El grupo 'media_users' ya existe."

# --- Función para configurar un montaje externo de forma idempotente ---
configure_external_storage() {
    local mount_point="$1"
    local data_dir="$2"

    echo "--- Configurando montaje: $mount_point ---"
    
    # Paso 1: Eliminar cualquier montaje existente con el mismo nombre para asegurar una configuración limpia
    EXISTING_IDS=$(docker exec -u www-data nextcloud-app-server php occ files_external:list --output=json | jq -r --arg name "$mount_point" '.[] | select(.mount_point == $name) | .mount_id')
    for id in $EXISTING_IDS; do
        echo "   -> Encontrado montaje existente de '$mount_point' con ID $id. Eliminando para reconfigurar..."
        docker exec -u www-data nextcloud-app-server php occ files_external:delete "$id"
    done

    # Paso 2: Crear el nuevo montaje
    echo "   -> Creando nuevo montaje externo para '$mount_point'..."
    MOUNT_ID=$(docker exec -u www-data nextcloud-app-server php occ files_external:create "$mount_point" local null::null | grep -o '[0-9]*')

    if [ -z "$MOUNT_ID" ]; then
        echo "   -> ❌ ERROR: No se pudo crear la carpeta externa '$mount_point'."
        return 1
    fi

    # Paso 3: Configurar el montaje recién creado
    echo "   -> Configurando ruta para ID: $MOUNT_ID..."
    docker exec -u www-data nextcloud-app-server php occ files_external:config "$MOUNT_ID" datadir "$data_dir"
    echo "   -> Aplicando montaje al grupo 'media_users'..."
    docker exec -u www-data nextcloud-app-server php occ files_external:applicable --add-group "media_users" "$MOUNT_ID"
    
    echo "✅ Carpeta '$mount_point' conectada y accesible para 'media_users'."
}

# --- Configurar los dos montajes necesarios ---
configure_external_storage "Multimedia" "/media/multimedia"
configure_external_storage "Papelera_media" "/media/papelera"

# --- Añadir usuario admin al grupo media_users para asegurar acceso ---
echo "   -> Asegurando que el usuario 'admin' pertenece al grupo 'media_users'..."
docker exec -u www-data nextcloud-app-server php occ group:adduser media_users admin || echo "   -> (Info) El usuario 'admin' ya pertenece al grupo."


# === REPARACIONES FINALES ===
echo "🔧 Ejecutando reparaciones finales..."
docker exec -u www-data nextcloud-app-server php occ maintenance:repair --include-expensive
docker exec -u www-data nextcloud-app-server php occ db:add-missing-indices
docker exec -u www-data nextcloud-app-server php occ db:convert-filecache-bigint --no-interaction
docker exec -u www-data nextcloud-app-server php occ files:scan --all

echo ""
echo "🎉 =============================================================
🎉 DESPLIEGUE COMPLETADO CON EXITO!
🎉 =============================================================
"
echo "📊 ARQUITECTURA DESPLEGADA:"
echo "   ✅ Nextcloud FPM (Procesamiento PHP)"
echo "   ✅ Apache HTTP (Servidor Web + Proxy) con HTTP/2"
echo "   ✅ PostgreSQL (Base de datos)"
echo "   ✅ Redis (Cache)"
echo "   ✅ OnlyOffice Document Server"
echo "   ✅ Jellyfin Media Server"
echo ""
echo "📱 ACCESO WEB:"
echo "   Nextcloud: http://${FIRST_DOMAIN}:${NEXTCLOUD_PORT}"
echo "   OnlyOffice: http://${FIRST_DOMAIN}:${ONLYOFFICE_PORT}"
echo "   Jellyfin:   http://${FIRST_DOMAIN}:${JELLYFIN_PORT}"
echo ""
echo "🔐 CREDENCIALES:"
echo "   Usuario: ${NEXTCLOUD_ADMIN_USER}"
echo "   Contraseña: ${NEXTCLOUD_ADMIN_PASSWORD}"
echo ""
echo "🗂️ DATOS ALMACENADOS EN:"
echo "   ${APP_DATA_PATH}"
echo "   ${JELLYFIN_CONFIG_PATH}"
echo "   ${MULTIMEDIA_PATH}"
echo "   (Papelera de media en: ${PAPELERA_MEDIA_PATH})"
echo ""
echo "💾 SCRIPTS DE BACKUP Y OPTIMIZACIÓN:"
echo "   ./scripts/backup.sh  - Crear backup incremental"
echo "   ./scripts/restore.sh - Restaurar desde backup"
echo "   ./scripts/optimizer_videos.sh - Herramienta interactiva para estandarizar videos (con respaldo)"
echo "   ./scripts/optimizer_images.sh - Herramienta automática para ampliar imágenes (con respaldo)"
echo ""
echo "============================================================= 
"
echo "🎯 PROXIMOS PASOS:"
echo "============================================================= 
"
echo "1. 🌐 Accede a tus servicios y verifica el funcionamiento"
echo "2. 📱 Prueba la conexión con la app de Nextcloud para Android. ¡Debería funcionar!"
echo "3. ⚡ Ejecuta tus scripts de optimización cuando lo necesites:"
echo "      - Para VIDEO (Interactivo): sudo ./scripts/optimizer_videos.sh"
echo "      - Para IMÁGENES (Automático): sudo ./scripts/optimizer_images.sh"
echo "4. 🎬 Sigue el procedimiento recomendado para Jellyfin (desactivar monitoreo, etc.)"
echo "5. 💾 Programa el backup: sudo crontab -e -> 0 2 * * * /ruta/a/tu/proyecto/scripts/backup.sh"
echo "============================================================= 
"
echo "✨ ¡Stack completo y listo para producción con herramientas a medida! ✨"
