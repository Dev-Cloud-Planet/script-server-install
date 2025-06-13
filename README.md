# Instalador Automatizado de n8n para Producción by Dev Cloud Planet

Este repositorio aloja un script de Bash (`setup-n8n-cloud.sh`) diseñado por **Dev Cloud Planet** para automatizar el despliegue de una pila completa y robusta de [n8n](https://n8n.io/) en servidores Ubuntu. La configuración está optimizada para entornos de producción, utilizando Docker y un proxy inverso Nginx para garantizar seguridad, escalabilidad y facilidad de gestión.

El objetivo es abstraer la complejidad de la configuración, permitiendo a cualquier usuario, con o sin experiencia en DevOps, desplegar una instancia de n8n lista para producción en minutos, usando un único comando.

[![Licencia: MIT](https://img.shields.io/badge/Licencia-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/Shell-Bash-blue)](https://www.gnu.org/software/bash/)
[![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=white)](https://www.docker.com/)

---

## 🚀 Características Principales

*   **Ejecución en una Línea:** Despliega toda la pila con un solo comando, sin necesidad de clonar el repositorio.
*   **Pila de Producción Completa:** No solo instala n8n, sino también todos los componentes esenciales:
    *   **PostgreSQL:** Como base de datos persistente.
    *   **Redis:** Para la gestión de colas y habilitación de workers.
    *   **Nginx Proxy:** Como proxy inverso para gestionar tráfico y SSL.
    *   **pgAdmin:** Herramienta web para administrar la base de datos PostgreSQL.
    *   **Redis Commander:** Herramienta web para inspeccionar y gestionar Redis.
*   **Seguridad por Diseño:**
    *   Configuración de SSL/TLS obligatoria para todo el tráfico.
    *   Aislamiento de servicios mediante redes de Docker separadas (`frontend` y `backend`).
    *   No se exponen puertos de servicios críticos a la red pública.
*   **Gestión de SSL Flexible:**
    *   **Modo Automático:** Generación y renovación automática de certificados SSL gratuitos con **Let's Encrypt**.
    *   **Modo Manual:** Permite el uso de certificados SSL propios.
*   **Escalabilidad Integrada:** Permite configurar **workers de n8n** durante la instalación para distribuir la carga de trabajo y mejorar el rendimiento.
*   **Persistencia de Datos Garantizada:** Utiliza volúmenes de Docker para que todos los datos (workflows, credenciales, bases de datos) sobrevivan a reinicios y actualizaciones de los contenedores.

## 🛠️ Componentes del Stack

| Servicio          | Imagen de Docker                        | Propósito                                                   |
| ----------------- | --------------------------------------- | ----------------------------------------------------------- |
| **Nginx Proxy**   | `jwilder/nginx-proxy`                   | Proxy inverso que enruta el tráfico a los servicios.        |
| **Let's Encrypt** | `jrcs/letsencrypt-nginx-proxy-companion`| Compañero de Nginx para gestionar los certificados SSL.     |
| **n8n**           | `n8nio/n8n:latest`                      | El servicio principal de automatización.                    |
| **PostgreSQL**    | `postgres:15`                           | Base de datos relacional para los datos de n8n.             |
| **Redis**         | `redis:7`                               | Base de datos en memoria para la cola de ejecuciones.       |
| **pgAdmin**       | `dpage/pgadmin4`                        | Interfaz web para administrar PostgreSQL.                   |
| **Redis Commander**| `rediscommander/redis-commander`        | Interfaz web para administrar Redis.                        |

## 📋 Requisitos Previos

**Antes de ejecutar el script, es fundamental que cumplas con lo siguiente:**

1.  **Un servidor con Ubuntu 20.04 o 22.04 LTS.** Se recomienda una instancia limpia.
2.  **Una dirección IP pública estática** asignada al servidor.
3.  **Acceso al servidor vía terminal** con un usuario que tenga privilegios `sudo`.
4.  **Tres (3) nombres de dominio (o subdominios) apuntando a la IP pública de tu servidor.** Debes configurar los **registros DNS de tipo `A`** en tu proveedor de dominios *antes* de ejecutar el script.
    *   **Ejemplo:**
        *   `n8n.tudominio.com` -> `TU_IP_PÚBLICA`
        *   `pgadmin.tudominio.com` -> `TU_IP_PÚBLICA`
        *   `redis.tudominio.com` -> `TU_IP_PÚBLICA`

## ⚙️ Ejecución

### Método Rápido (Recomendado)

Este método descarga y ejecuta el script directamente desde GitHub, sin necesidad de clonar el repositorio. Simplemente copia y pega el siguiente comando en la terminal de tu servidor:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/Dev-Cloud-Planet/script-server-install/main/setup-n8n-cloud.sh)
```

### Proceso Interactivo

Una vez ejecutado, el script te guiará a través de una serie de preguntas para configurar el entorno:

*   Tus 3 dominios (para n8n, pgAdmin, Redis Commander).
*   El método de SSL (`automático` o `manual`).
*   Tu correo electrónico (para notificaciones de Let's Encrypt).
*   La zona horaria (ej: `America/Caracas`).
*   Contraseñas seguras y claves de cifrado.
*   Si deseas añadir workers y cuántos.

El script se encargará del resto, desde instalar Docker hasta configurar y lanzar todos los servicios.

## 🔑 Post-Instalación

Al finalizar, tendrás acceso a tus servicios a través de las URLs seguras que configuraste:

*   **n8n:** `https://n8n.tudominio.com`
*   **pgAdmin:** `https://pgadmin.tudominio.com`
*   **Redis Commander:** `https://redis.tudominio.com`

**Notas Importantes:**
*   **Propagación de SSL:** Si usaste el modo automático, la generación del certificado SSL puede tardar entre 2 y 5 minutos. Si ves un error `503 Service Temporarily Unavailable`, espera un poco y refresca la página.
*   **Permisos de Docker:** Es posible que necesites cerrar sesión y volver a iniciarla (o reiniciar el servidor) para poder ejecutar comandos de `docker` sin `sudo`.

## 📁 Gestión de la Pila de Servicios

El script crea los archivos `docker-compose.yml` y `.env` en el directorio desde donde lo ejecutaste. Puedes usarlos para gestionar tus servicios.

*   **Ver el estado de los contenedores:**
    ```bash
    docker compose ps
    ```
*   **Ver los logs de un servicio (ej. n8n):**
    ```bash
    docker compose logs -f n8n
    ```
*   **Detener todos los servicios:**
    ```bash
    docker compose down
    ```
*   **Iniciar todos los servicios:**
    ```bash
    docker compose up -d
    ```
*   **Eliminar todo (incluyendo datos persistentes):**
    ```bash
    # ¡CUIDADO! Esto borrará tus workflows, credenciales y bases de datos.
    docker compose down --volumes
    ```

## 🤝 Cómo Contribuir

En Dev Cloud Planet, creemos en el poder del código abierto. Si tienes ideas para mejorar este script, añadir funcionalidades o corregir errores, ¡tu contribución es bienvenida!

1.  **Haz un Fork** de este repositorio.
2.  **Crea una nueva rama** para tu funcionalidad (`git checkout -b feature/mi-mejora`).
3.  **Realiza tus cambios** y haz commit (`git commit -m 'Agrega mi increíble mejora'`).
4.  **Haz un Push** a tu rama (`git push origin feature/mi-mejora`).
5.  **Abre un Pull Request** explicando tus cambios.

## 📄 Licencia

Este proyecto está distribuido bajo la [Licencia MIT](LICENSE).

---
**Un proyecto de [Dev Cloud Planet](https://github.com/Dev-Cloud-Planet)**