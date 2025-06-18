#!/bin/bash
#
# Copyright (c) 2025 Dev Cloud Planet
# Este script está licenciado bajo la Licencia MIT.
# Puedes encontrar una copia de la licencia en el archivo LICENSE
# o en https://opensource.org/licenses/MIT
#
# Este script automatiza la instalación de n8n con Docker, PostgreSQL, Redis,
# pgAdmin, Redis Commander y un proxy inverso Nginx con Let's Encrypt integrado.
# Ofrece la opción de generar SSL automáticamente o usar certificados propios.

set -euo pipefail

# --- 1. Funciones de ayuda ---
log_info() { echo -e "\n\e[34m[INFO] $1\e[0m"; } 
log_success() { echo -e "\n\e[32m[ÉXITO] $1\e[0m"; } 
log_warn() { echo -e "\n\e[33m[ADVERTENCIA] $1\e[0m"; } 
log_error() { echo -e "\n\e[31m[ERROR] $1\e[0m"; exit 1; }

# --- 2. Preparación inicial y Sudo ---
log_info "🚀 Bienvenido al instalador de n8n para despliegues en la nube!"
log_info "Este script configurará n8n con Nginx, SSL y herramientas de gestión."

sudo -v || log_error "No se pudo obtener privilegios sudo. Asegúrate de que tu usuario tenga permisos sudo."
( while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done ) 2>/dev/null &

log_info "Creando directorios para la persistencia de datos de Nginx..."
mkdir -p data/certs data/vhost.d data/html data/conf.d || log_error "No se pudieron crear los directorios de datos."
log_success "Directorios de datos creados correctamente en $(pwd)/data."

# --- 3. Actualización del sistema ---
log_info "Actualizando tu sistema Ubuntu..."
sudo apt-get update -y && sudo apt-get upgrade -y || log_error "Falló la actualización del sistema."
log_success "Sistema actualizado correctamente."

# --- 4. Instalación de Docker y Docker Compose ---
log_info "Verificando e instalando Docker..."
if command -v docker &> /dev/null && docker --version &> /dev/null; then
  log_success "Docker ya está instalado. Saltando instalación..."
else
  log_warn "Docker no está instalado. Procediendo con la instalación..."
  sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common || log_error "Falló la instalación de paquetes base para Docker."
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg || log_error "Falló la descarga de la clave GPG de Docker."
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null || log_error "Falló la adición del repositorio de Docker."
  sudo apt-get update -y || log_error "Falló la actualización de los repositorios después de añadir Docker."
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io || log_error "Falló la instalación de Docker CE."
  log_success "Docker instalado correctamente."
  log_info "Agregando tu usuario ($USER) al grupo 'docker' para ejecutar comandos sin sudo..."
  sudo usermod -aG docker "$USER" || log_error "Falló la adición del usuario al grupo 'docker'."
  log_warn "Para aplicar los permisos de Docker, **ES NECESARIO CERRAR SESIÓN Y VOLVER A ENTRAR, O REINICIAR LA MÁQUINA.**"
fi

log_info "Verificando e instalando Docker Compose (plugin 'docker compose')..."
if docker compose version &> /dev/null; then
  log_success "Docker Compose (plugin) ya está disponible."
else
  log_warn "Docker Compose (plugin) no está instalado. Procediendo con la instalación..."
  sudo apt-get update -y || log_error "Falló la actualización de los repositorios para Docker Compose plugin."
  sudo apt-get install -y docker-compose-plugin || log_error "Falló la instalación del plugin de Docker Compose."
  docker compose version &> /dev/null || log_error "No se pudo instalar Docker Compose (plugin). Abortando..."
  log_success "Docker Compose (plugin) instalado correctamente."
fi

# --- 5. Recopilación de variables de entorno ---
log_info "Ahora, configuraremos tu entorno. Por favor, responde las siguientes preguntas:"

read -rp "🟡 Introduce el dominio/subdominio principal para n8n (ej: n8n.tudominio.com): " DOMAIN_N8N
[[ -z "$DOMAIN_N8N" ]] && log_error "El dominio no puede estar vacío."

read -rp "📊 Introduce el subdominio para pgAdmin (ej: pgadmin.tudominio.com): " DOMAIN_PGADMIN
[[ -z "$DOMAIN_PGADMIN" ]] && log_error "El dominio para pgAdmin no puede estar vacío."

read -rp "🔍 Introduce el subdominio para Redis Commander (ej: redis.tudominio.com): " DOMAIN_REDIS_COMMANDER
[[ -z "$DOMAIN_REDIS_COMMANDER" ]] && log_error "El dominio para Redis Commander no puede estar vacío."

if [[ "$DOMAIN_N8N" == "$DOMAIN_PGADMIN" || "$DOMAIN_N8N" == "$DOMAIN_REDIS_COMMANDER" || "$DOMAIN_PGADMIN" == "$DOMAIN_REDIS_COMMANDER" ]]; then
  log_error "Los dominios para n8n, pgAdmin y Redis Commander deben ser únicos."
fi

log_info "Configuración de SSL"
read -rp "🔒 ¿Cómo quieres configurar SSL? [a]utomático con Let's Encrypt (recomendado) o [m]anual con tus propios certificados: " SSL_MODE
if [[ ! "$SSL_MODE" =~ ^[aAmM]$ ]]; then log_error "Opción no válida. Debes elegir 'a' o 'm'."; fi

EMAIL=""
if [[ "$SSL_MODE" =~ ^[aA]$ ]]; then
    SSL_MODE="automatic"
    read -rp "📧 Introduce tu correo electrónico para Let's Encrypt (necesario para certificados SSL): " EMAIL
    if ! [[ "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}$ ]]; then
      log_error "El formato del correo electrónico no es válido."
    fi
else
    SSL_MODE="manual"
    log_info "Modo manual seleccionado. Proporciona la ruta a tus archivos de certificado."
    for domain in "$DOMAIN_N8N" "$DOMAIN_PGADMIN" "$DOMAIN_REDIS_COMMANDER"; do
        log_warn "Para el dominio: $domain"
        read -erp "   Ruta al archivo de certificado (.crt, debe ser la cadena completa): " cert_path
        read -erp "  Ruta al archivo de clave privada (.key): " key_path
        
        [[ ! -f "$cert_path" ]] && log_error "El archivo de certificado no existe en: $cert_path"
        [[ ! -f "$key_path" ]] && log_error "El archivo de clave privada no existe en: $key_path"

        log_info "Copiando certificados para $domain..."
        sudo cp "$cert_path" "./data/certs/${domain}.crt" || log_error "No se pudo copiar el certificado."
        sudo cp "$key_path" "./data/certs/${domain}.key" || log_error "No se pudo copiar la clave privada."
    done
fi

read -rp "🌍 Zona horaria (ej: America/Caracas o Europe/Madrid): " TZ
[[ -z "$TZ" ]] && log_error "La zona horaria no puede estar vacía."

read -rsp "🔐 Contraseña para PostgreSQL (¡anótala!): " POSTGRES_PASSWORD; echo
[[ -z "$POSTGRES_PASSWORD" ]] && log_error "La contraseña de PostgreSQL no puede estar vacía."

read -rp "👤 Usuario para acceso básico a n8n (ej: admin): " N8N_BASIC_AUTH_USER
[[ -z "$N8N_BASIC_AUTH_USER" ]] && log_error "El usuario de n8n no puede estar vacío."

read -rsp "🔑 Contraseña para acceso básico a n8n (¡anótala!): " N8N_BASIC_AUTH_PASSWORD; echo
[[ -z "$N8N_BASIC_AUTH_PASSWORD" ]] && log_error "La contraseña de n8n no puede estar vacía."

read -rsp "🧪 Clave secreta para cifrado en n8n (cadena larga y segura, ¡anótala!): " N8N_ENCRYPTION_KEY; echo
[[ -z "$N8N_ENCRYPTION_KEY" ]] && log_error "La clave de cifrado de n8n no puede estar vacía."

N8N_WORKERS=0
read -rp "🔁 ¿Quieres añadir workers para n8n? (s/n): " add_workers_response
if [[ "$add_workers_response" =~ ^[sS]$ ]]; then
  read -rp "🔢 ¿Cuántos workers quieres usar? (1-5): " N8N_WORKERS
  [[ ! "$N8N_WORKERS" =~ ^[1-5]$ ]] && log_error "Número inválido de workers."
fi

# --- 6. Creación del archivo .env ---
log_info "Generando el archivo .env con tus configuraciones..."
[ -f .env ] && read -rp "$(log_warn 'El archivo .env ya existe. ¿Sobrescribir? (s/n)')" confirm_overwrite && [[ ! "$confirm_overwrite" =~ ^[sS]$ ]] && log_error "Operación cancelada."

cat > .env << EOL
# --- Variables de Entorno para la Pila de n8n ---
# Dominios y SSL
DOMAIN_N8N=${DOMAIN_N8N}
DOMAIN_PGADMIN=${DOMAIN_PGADMIN}
DOMAIN_REDIS_COMMANDER=${DOMAIN_REDIS_COMMANDER}
EMAIL=${EMAIL}
N8N_SECURE_COOKIE=true
# Configuración General
TZ=${TZ}
POSTGRES_USER=postgres 
POSTGRES_DB=postgres   
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
# Credenciales de n8n
N8N_BASIC_AUTH_USER=${N8N_BASIC_AUTH_USER}
N8N_BASIC_AUTH_PASSWORD=${N8N_BASIC_AUTH_PASSWORD}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
N8N_WORKERS=${N8N_WORKERS}
EOL
log_success "Archivo .env generado correctamente."

# --- 7. Creación del archivo docker-compose.yml ---
log_info "Generando el archivo docker-compose.yml..."
cat > docker-compose.yml << EOL
services:
  nginx-proxy:
    image: nginxproxy/nginx-proxy:alpine
    container_name: nginx-proxy
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/tmp/docker.sock:ro
      - ./data/certs:/etc/nginx/certs:rw
      - ./data/vhost.d:/etc/nginx/vhost.d
      - ./data/html:/usr/share/nginx/html
      - ./data/conf.d:/etc/nginx/conf.d
    networks:
      - frontend 
    restart: always
EOL

if [[ "$SSL_MODE" == "automatic" ]]; then
cat >> docker-compose.yml << EOL
    environment:
      DEFAULT_EMAIL: \${EMAIL}
EOL
fi

cat >> docker-compose.yml << EOL
  letsencrypt:
    image: nginxproxy/acme-companion
    container_name: nginx-proxy-acme
    volumes:
      - ./data/certs:/etc/nginx/certs:rw
      - /var/run/docker.sock:/var/run/docker.sock:ro
    volumes_from:
      - nginx-proxy
    networks:
      - frontend
    restart: always
    depends_on:
      - nginx-proxy
  
  postgres:
    image: postgres:15
    container_name: postgres
    environment:
      POSTGRES_USER: \${POSTGRES_USER}
      POSTGRES_DB: \${POSTGRES_DB}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - backend 
    restart: always
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER} -d \${POSTGRES_DB}"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: redis
    restart: always
    networks:
      - backend 
    healthcheck: 
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis-commander:
    image: rediscommander/redis-commander:latest
    container_name: redis-commander
    environment:
      REDIS_HOSTS: local:redis:6379
      TZ: \${TZ}
      VIRTUAL_HOST: \${DOMAIN_REDIS_COMMANDER}
      VIRTUAL_PORT: 8081
EOL
if [[ "$SSL_MODE" == "automatic" ]]; then
cat >> docker-compose.yml << EOL
      LETSENCRYPT_HOST: \${DOMAIN_REDIS_COMMANDER}
      LETSENCRYPT_EMAIL: \${EMAIL}
EOL
fi
cat >> docker-compose.yml << EOL
    networks:
      - frontend 
      - backend
    restart: always
    depends_on: 
      redis:
        condition: service_healthy

  pgadmin:
    image: dpage/pgadmin4
    container_name: pgadmin
    environment:
      PGADMIN_DEFAULT_EMAIL: \${EMAIL:-admin@example.com}
      PGADMIN_DEFAULT_PASSWORD: \${POSTGRES_PASSWORD}
      VIRTUAL_HOST: \${DOMAIN_PGADMIN}
      PGADMIN_LISTEN_PORT: 80
EOL
if [[ "$SSL_MODE" == "automatic" ]]; then
cat >> docker-compose.yml << EOL
      LETSENCRYPT_HOST: \${DOMAIN_PGADMIN} 
      LETSENCRYPT_EMAIL: \${EMAIL}
EOL
fi
cat >> docker-compose.yml << EOL
    networks:
      - frontend
      - backend
    restart: always
    depends_on: 
      postgres:
        condition: service_healthy

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n-main
    environment:
      REDIS_PORT: 6379
      REDIS_HOST: redis
      N8N_BASIC_AUTH_ACTIVE: true
      N8N_BASIC_AUTH_USER: \${N8N_BASIC_AUTH_USER}
      N8N_BASIC_AUTH_PASSWORD: \${N8N_BASIC_AUTH_PASSWORD}
      N8N_ENCRYPTION_KEY: \${N8N_ENCRYPTION_KEY}
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: postgres
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: \${POSTGRES_DB}
      DB_POSTGRESDB_USER: \${POSTGRES_USER}
      DB_POSTGRESDB_PASSWORD: \${POSTGRES_PASSWORD}
      QUEUE_MODE: redis
      QUEUE_REDIS_HOST: redis
      TZ: \${TZ}
      WEBHOOK_TUNNEL_URL: https://\${DOMAIN_N8N}/
      N8N_HOST: \${DOMAIN_N8N}
      N8N_PORT: 5678
      VIRTUAL_HOST: \${DOMAIN_N8N}
      VIRTUAL_PORT: 5678
      N8N_TRUSTED_PROXIES: nginx-proxy
      N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS: false
      OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS: true
EOL
if [[ "$SSL_MODE" == "automatic" ]]; then
cat >> docker-compose.yml << EOL
      LETSENCRYPT_HOST: \${DOMAIN_N8N} 
      LETSENCRYPT_EMAIL: \${EMAIL}
EOL
fi
cat >> docker-compose.yml << EOL
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - frontend
      - backend
    restart: always
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy 

EOL

if (( N8N_WORKERS > 0 )); then
  log_info "Añadiendo ${N8N_WORKERS} workers a docker-compose.yml..."
  for i in $(seq 1 "$N8N_WORKERS"); do
    cat >> docker-compose.yml <<EOF

  n8n-worker-$i:
    image: n8nio/n8n:latest
    container_name: n8n-worker-$i
    command: worker
    restart: always
    environment:
      REDIS_PORT: 6379
      REDIS_HOST: redis
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: postgres
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: \${POSTGRES_DB}
      DB_POSTGRESDB_USER: \${POSTGRES_USER}
      DB_POSTGRESDB_PASSWORD: \${POSTGRES_PASSWORD}
      QUEUE_MODE: redis
      QUEUE_REDIS_HOST: redis
      N8N_ENCRYPTION_KEY: \${N8N_ENCRYPTION_KEY}
      TZ: \${TZ}
    networks:
      - backend
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
EOF
  done
  log_success "Workers añadidos al docker-compose.yml."
fi

cat >> docker-compose.yml << EOL

volumes:
  postgres_data: {}
  n8n_data: {}

networks:
  frontend:
  backend:
EOL
log_success "Archivo docker-compose.yml generado correctamente."

# --- 8. Levantar los servicios Docker ---
log_info "Limpiando instalaciones previas (si existen)..."
# Asegurar que partimos de un estado limpio
docker compose down --volumes --remove-orphans 2>/dev/null || true 

log_info "Levantando los servicios Docker. Esto puede tardar unos minutos..."

SUDO_CMD=""
if [ "$(id -u)" -ne 0 ] && ! id -nG "$USER" | grep -qw "docker"; then
    log_warn "El usuario no es root y no está en el grupo 'docker'. Usando 'sudo'..."
    SUDO_CMD="sudo"
fi

$SUDO_CMD docker compose up -d || log_error "Falló el levantamiento de los servicios Docker."

log_success "¡Todos los servicios Docker están en funcionamiento!"

# --- 9. Instrucciones Finales ---
log_info "🎉 ¡Configuración completada!"

log_warn "ACCIÓN REQUERIDA: Debes configurar los siguientes registros DNS de tipo 'A' para que apunten a la IP pública de este servidor:"
echo -e "\e[36m  - ${DOMAIN_N8N}\e[0m"
echo -e "\e[36m  - ${DOMAIN_PGADMIN}\e[0m"
echo -e "\e[36m  - ${DOMAIN_REDIS_COMMANDER}\e[0m"

log_info "Una vez que los DNS se hayan propagado, podrás acceder a tus servicios:"
log_info "n8n:             \e[1mhttps://${DOMAIN_N8N}\e[0m"
log_info "pgAdmin:         \e[1mhttps://${DOMAIN_PGADMIN}\e[0m (Usuario: ${EMAIL:-admin@example.com}, Contraseña: la de PostgreSQL)"
log_info "Redis Commander: \e[1mhttps://${DOMAIN_REDIS_COMMANDER}\e[0m"

if [[ "$SSL_MODE" == "automatic" ]]; then
    log_warn "La emisión de los certificados SSL puede tardar unos minutos. Si encuentras un error 503, espera un poco y refresca."
else
    log_success "Tus certificados SSL personalizados han sido cargados. Los servicios deberían estar disponibles inmediatamente."
fi

log_warn "RECORDATORIO: Si tu usuario no estaba en el grupo 'docker' antes, necesitarás cerrar sesión y volver a entrar (o reiniciar el servidor) para poder usar 'docker' sin 'sudo'."
log_success "¡Disfruta de tus servicios n8n en la nube!"
# --- 10. Finalización ---
log_info "Si tienes alguna duda o problema, revisa la documentación en Github o contacta con devcloudplanet@gmail.com"
log_info "Gracias por usar este script. ¡ÉXITO!"
exit 0