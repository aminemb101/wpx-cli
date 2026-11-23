#!/usr/bin/env bash
set -euo pipefail

FORCE=false


WP_VERSION="latest"
HOST_NAME=""
ADMIN_EMAIL="admin@example.test"
ADMIN_USER="admin"
ADMIN_PASSWORD="password"
SITE_NAME=""
PHP_VERSION="8.2"
INST_PATH='.'
DB_ROOT_USER=root
DB_ROOT_PASS=hguyFtgfR4r9R4r76


usage() {
    echo "Usage: $0 --site_name <name> [options]"
    exit 1
}

if [[ "${1}" != -* ]]; then 
	INST_PATH=$1
	shift
fi


while [[ $# -gt 0 ]]; do
    case "$1" in
        --wp_version=*)
            WP_VERSION="${1#*=}"
            shift
            ;;
        --wp_version)
            WP_VERSION="${2:-}"
            shift 2
            ;;
        --host_name=*)
            HOST_NAME="${1#*=}"
            shift
         
            ;;
        --host_name)
            HOST_NAME="${2:-}"
            shift 2
           
            ;;
        --admin_email=*)
            ADMIN_EMAIL="${1#*=}"
            shift
            ;;
        --admin_email)
            ADMIN_EMAIL="${2:-}"
            shift 2
            ;;
        --admin_user=*)
            ADMIN_USER="${1#*=}"
            shift
            ;;
        --admin_user)
            ADMIN_USER="${2:-}"
            shift 2
            ;;
        --admin_pass=*)
            ADMIN_PASSWORD="${1#*=}"
            shift
            ;;
        --admin_pass)
            ADMIN_PASSWORD="${2:-}"
            shift 2
            ;;
        --site_name=*)
            SITE_NAME="${1#*=}"
            shift
            ;;
        --site_name)
            SITE_NAME="${2:-}"
            shift 2
            ;;
        --php=*)
            PHP_VERSION="${1#*=}"
            shift
            ;;
        --php)
            PHP_VERSION="${2:-}"
            shift 2
            ;;
        --redis)
            ENABLE_REDIS=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage
            ;;
        *)
            break
            ;;
    esac
done

if [[ -z "${SITE_NAME:-}" ]]; then
    echo "Error: SITE_NAME is required (used as the Docker Compose project name)." >&2
    exit 1
fi

if [[ -z "${HOST_NAME:-}" ]]; then
    echo "Error: HOST_NAME is required (used as the site folder name)." >&2
    exit 1
fi



if docker compose ls --all --format json | grep -q "\"Name\":\"${SITE_NAME}\"" && [[ "$FORCE" != true ]]; then
    echo "Error: Docker Compose project '${SITE_NAME}' already exists. Choose a different SITE_NAME or destroy it first." >&2
    exit 1
fi

PHP_SERVICE="wp-php"
MYSQL_SERVICE="wp-mariadb"
NGINX_SERVICE="wp-nginx"


SITE_SLUG="$(echo "$SITE_NAME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
# Installation directory where tempaltes (docker files and docker compose will be copied to)
DIR="${INST_PATH}/${SITE_SLUG}"


docker compose -p "${SITE_NAME}" down && rm -rf "$DIR"

if [[ -d "${DIR}" && -n "$(ls -A "${DIR}" 2>/dev/null)" && "$FORCE" != true ]]; then
    echo "Error: Directory '${DIR}' already exists and is not empty. Use --force to overwrite." >&2
    exit 1
fi

mkdir -p "$DIR/.docker"

cat << ENVFILE > "$DIR/.docker/.env" 
SITE_NAME=$SITE_NAME
COMPOSE_PROJECT_NAME=$SITE_NAME
HOST_NAME=$HOST_NAME
DB_ROOT_PASSWORD=$DB_ROOT_PASS
USER_UID=1000
USER_GID=1000
ENVFILE

TEMPLATES_DIR="./templates"


cp -r "${TEMPLATES_DIR}/dockerfiles" "${DIR}/.docker/"
cp ${TEMPLATES_DIR}/docker-compose.yml "${DIR}/.docker/"
#2 start the containers from compose
docker compose --env-file "${DIR}/.docker/.env"  -p "$SITE_NAME" -f "${DIR}/.docker/docker-compose.yml"  up  -d --wait 


#3 create the site
DB_NAME="wp-db"

docker compose -p "${SITE_NAME}" exec -T $MYSQL_SERVICE sh << EOF
	set -e 

	mariadb  "-p${DB_ROOT_PASS}" -e "DROP DATABASE IF EXISTS \\\`${DB_NAME}\\\`"	
	mariadb  "-p${DB_ROOT_PASS}" -e "CREATE DATABASE \\\`${DB_NAME}\\\`"
EOF


DOC_ROOT="/var/www/html/"

docker compose -p "${SITE_NAME}" exec -T "$PHP_SERVICE" sh << EOF
	
	set -e 
	
	if [[ -d ${DOC_ROOT} ]] 
    then 
        mkdir -p ${DOC_ROOT}  
	fi

	cd ${DOC_ROOT}
	wp core download --version=${WP_VERSION} --allow-root --force
	wp config create --force --dbname=${DB_NAME} --dbuser=$DB_ROOT_USER --dbpass=$DB_ROOT_PASS --dbhost=${MYSQL_SERVICE} --allow-root
	wp core install \
		--url="http://${HOST_NAME}" \
		--title="${SITE_NAME}" \
		--admin_user="${ADMIN_USER}" \
		--admin_password="${ADMIN_PASSWORD}" \
		--admin_email="${ADMIN_EMAIL}" \
		--allow-root
	chown -R 1000:1000 ${DOC_ROOT}
EOF


docker compose -p "${SITE_NAME}" exec -T  "${NGINX_SERVICE}" sh << EOF
       set -e 
	   
		cat << VHOST  >  "/etc/nginx/conf.d/${HOST_NAME}.conf"
				server  {
					listen 80;
					server_name ${HOST_NAME};
					root ${DOC_ROOT};
					location / {
						index index.php;
						try_files \\\$uri \\\$uri/ /index.php?\\\$args;
					}
					location ~ \.php$ {
					fastcgi_pass   wp-php:9000;
					fastcgi_index  index.php;
					fastcgi_param  SCRIPT_FILENAME \\\$document_root\\\$fastcgi_script_name;
					include        fastcgi_params;
					}	
				}
VHOST
	chown 1000:1000 "/etc/nginx/conf.d/${HOST_NAME}.conf"
	nginx -s reload 
EOF
