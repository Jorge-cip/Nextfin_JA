
# Nextfin_JA

## Instalación óptima en servidor Linux

### 1. Requisitos previos

- Tener instalado `git` y `dos2unix`:
  ```bash
  sudo apt-get update
  sudo apt-get install git dos2unix
  ```

### 2. Clonar el repositorio

Configura git para usar finales de línea LF (opcional pero recomendado):
```bash
git config --global core.autocrlf input
```

Clona el repositorio:
```bash
git clone https://github.com/usuario/Nextfin_JA.git
cd Nextfin_JA
```

### 3. Verificar y convertir finales de línea

Asegúrate de que los archivos tengan formato Unix (LF):
```bash
dos2unix setup.sh .env docker-compose.yml
```

Verifica con:
```bash
file setup.sh .env docker-compose.yml
```
Deben aparecer como "ASCII text" o "UTF-8 text", sin "CRLF".

### 4. Dar permisos de ejecución al script

```bash
chmod +x setup.sh
```

### 5. Ejecutar el script de instalación

```bash
sudo ./setup.sh
```
Durante la instalación, el script puede pedir autorización para instalar herramientas. Confirma cada paso según sea necesario.

---

## Herramientas instaladas y su función

- **restic**: Copias de seguridad seguras y rápidas de los datos del proyecto.
- **docker**: Ejecuta los servicios (Nextcloud, OnlyOffice, Jellyfin, Apache, etc.) en contenedores.
- **docker compose (v2)**: Orquesta y administra múltiples contenedores Docker.
- **ffmpeg y ffprobe**: Procesan y analizan archivos multimedia (audio y video).
- **jq**: Procesa y manipula datos en formato JSON.
- **bc**: Calculadora de precisión arbitraria para operaciones matemáticas en scripts.
- **wget**: Descarga archivos desde internet.
- **unzip**: Descomprime archivos ZIP.
- **imagemagick (convert)**: Manipula y convierte imágenes.

---

## Otras acciones importantes del script

- Verifica y carga variables de entorno desde el archivo `.env`.
- Crea y asegura permisos de directorios necesarios para los servicios.
- Sincroniza la contraseña de Restic para backups.
- Genera un Dockerfile personalizado para Apache con soporte HTTP/2.
- Configura permisos colaborativos en carpetas multimedia y de papelera.

---

## Notas adicionales

- Si el script no se ejecuta, intenta con:
  ```bash
  bash setup.sh
  ```
- Si tienes archivos adicionales (.yaml, .env, etc.), repite el proceso de conversión con `dos2unix`.
- Si quieres automatizar la instalación sin confirmaciones, ejecuta:
  ```bash
  sudo ./setup.sh --assume-yes
  ```

---

¡Listo! Ahora puedes instalar y configurar Nextfin_JA en cualquier servidor Linux siguiendo estos pasos.
