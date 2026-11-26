#!/usr/bin/env bash
set -euo pipefail

FORCE=false



HOST_NAME=""

WP_VERSION="latest"
ADMIN_EMAIL="admin@example.test"
ADMIN_USER="admin"
ADMIN_PASSWORD="password"
SITE_NAME="Demo site"
INST_PATH=$(pwd)


PHP_VERSION="8.2"

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
            WP_VERSION="${2:-$WP_VERSION}"
            shift 2
            ;;
        --host_name=*)
            HOST_NAME="${1#*=}"
            shift
            ;;
        --host_name)
            HOST_NAME="${2:-$HOST_NAME}"
            shift 2
            ;;
        --admin_email=*)
            ADMIN_EMAIL="${1#*=}"
            shift
            ;;
        --admin_email)
            ADMIN_EMAIL="${2:-$ADMIN_EMAIL}"
            shift 2
            ;;
        --admin_user=*)
            ADMIN_USER="${1#*=}"
            shift
            ;;
        --admin_user)
            ADMIN_USER="${2:-$ADMIN_USER}"
            shift 2
            ;;
        --admin_pass=*)
            ADMIN_PASSWORD="${1#*=}"
            shift
            ;;
        --admin_pass)
            ADMIN_PASSWORD="${2:-$ADMIN_PASSWORD}"
            shift 2
            ;;
        --site_name=*)
            SITE_NAME="${1#*=}"
            echo "${SITE_NAME}"
            shift
            ;;
        --site_name)
            SITE_NAME="${2:-$SITE_NAME}"
            shift 2
            ;;
        --php=*)
            PHP_VERSION="${1#*=}"
            shift
            ;;
        --php)
            PHP_VERSION="${2:-$PHP_VERSION}"
            shift 2
            ;;
		--db-root-pass=*)
			DB_ROOT_PASS="${1#*=}"
		    shift
			;;
		--db-root-pass)
			DB_ROOT_PASS="${2:-$DB_ROOT_PASS}"
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



if [[ -z "${HOST_NAME:-}" ]]; then
    echo "Error: HOST_NAME is required (used as the site folder name)." >&2
    exit 1
fi




PHP_SERVICE="wpx-php"
MYSQL_SERVICE="wpx-mariadb"
NGINX_SERVICE="wpx-nginx"


SITE_SLUG="$(echo "$SITE_NAME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
# Installation directory where tempaltes (docker files and docker compose will be copied to)
DIR="${INST_PATH}/${SITE_SLUG}"
PROJECT_NAME="$(printf '%s' "$DIR" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"

# if docker compose ls --all --format json | grep -q "\"Name\":\"${PROJECT_NAME}\"" && [[ "$FORCE" != true ]]; then
#     echo "Error: Docker Compose project '${PROJECT_NAME}' already exists. Choose a different path or destroy it first." >&2
#     exit 1
# fi


# Create the network only if it doesn't exist
if ! docker network inspect wpx-proxy >/dev/null 2>&1; then
  docker network create wpx-proxy
fi

# Start the proxy only if a container with this name doesn't exist
if ! docker container inspect wpx-nginx-proxy >/dev/null 2>&1; then
  docker run -d \
    --name wpx-nginx-proxy \
    --restart unless-stopped \
    --network wpx-proxy \
    -p 80:80 \
    -p 443:443 \
    -v /var/run/docker.sock:/tmp/docker.sock:ro \
    nginxproxy/nginx-proxy:1.11
fi

#TEAR down project if it exisits for testing only												   			
#docker compose -p "${PROJECT_NAME}" down && rm -rf "$DIR"


mkdir -p "$DIR/.docker"

cat << ENVFILE > "$DIR/.docker/.env" 
SITE_NAME=$SITE_NAME
COMPOSE_PROJECT_NAME=$PROJECT_NAME
HOST_NAME=$HOST_NAME
DB_ROOT_PASSWORD=$DB_ROOT_PASS
USER_UID=1000
USER_GID=1000
ENVFILE

TEMPLATES_DIR="./templates"


cp -r "${TEMPLATES_DIR}/dockerfiles" "${DIR}/.docker/"
cp ${TEMPLATES_DIR}/docker-compose.yml "${DIR}/.docker/"


#2 start the containers from compose
docker compose --env-file "${DIR}/.docker/.env"  -p "$PROJECT_NAME" -f "${DIR}/.docker/docker-compose.yml"  up  -d --wait 


#3 create the site
DB_NAME="wpx-db"

docker compose -p "${PROJECT_NAME}" exec -T $MYSQL_SERVICE sh << EOF
	set -e 

	mariadb  "-p${DB_ROOT_PASS}" -e "DROP DATABASE IF EXISTS \\\`${DB_NAME}\\\`"	
	mariadb  "-p${DB_ROOT_PASS}" -e "CREATE DATABASE \\\`${DB_NAME}\\\`"
EOF


DOC_ROOT="/var/www/html/"

docker compose -p "${PROJECT_NAME}" exec -T "$PHP_SERVICE" sh << EOF
	
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


docker compose -p "${PROJECT_NAME}" exec -T  "${NGINX_SERVICE}" sh << EOF
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
					fastcgi_pass   ${PHP_SERVICE}:9000;
					fastcgi_index  index.php;
					fastcgi_param  SCRIPT_FILENAME \\\$document_root\\\$fastcgi_script_name;
					include        fastcgi_params;
					}	
				}
VHOST
	chown 1000:1000 "/etc/nginx/conf.d/${HOST_NAME}.conf"
	nginx -s reload 
EOF
