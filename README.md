# wpx

A lightweight Bash CLI for spinning up isolated local WordPress environments powered by Docker Compose, Nginx, PHP-FPM, and MariaDB.

## Prerequisites

* Docker Engine
* **Docker Compose v2.30+** (required for `pre_start` container lifecycle hooks)
* Bash 4+
* A `./templates` directory containing `docker-compose.yml` and `dockerfiles/`

## `create` Command

Creates a new WordPress site by slugifying `--site_name` (e.g., `My Shop` → `my-shop`) for the site directory and using `--site_name` as the Docker Compose project name.

### Syntax

```bash
wpx create [install_path] --site_name <name> --host_name <domain> [options]
```

### Positional Arguments

| Argument | Default | Description |
| :--- | :--- | :--- |
| `install_path` | `.` | Optional parent directory where `<site-slug>/` will be created. |

### Options

| Flag | Default | Description |
| :--- | :--- | :--- |
| `--site_name <name>` | *(Required)* | Site title and Docker Compose project name (slugified for folder naming). |
| `--host_name <domain>` | *(Required)* | Local domain configured in Nginx and WordPress (e.g., `shop.test`). |
| `--wp_version <ver>` | `latest` | WordPress core version to download via WP-CLI. |
| `--admin_user <user>` | `admin` | WordPress administrator username. |
| `--admin_pass <pass>` | `password` | WordPress administrator password. |
| `--admin_email <email>` | `admin@example.test` | WordPress administrator email address. |
| `-h`, `--help` | — | Display usage instructions and exit. |

*(Both `--flag value` and `--flag=value` formats are supported. Planned flags: `--php`, `--redis`, `--force`.)*

### Examples

**Create a site in the current directory:**

```bash
wpx create --site_name "Shop 3" --host_name shop3.test
```

**Create a site in a custom folder with a specific WordPress version and admin credentials:**

```bash
wpx create ~/sites \
  --site_name client-portal \
  --host_name portal.test \
  --wp_version 6.7 \
  --admin_user dev \
  --admin_pass "S3cur3P@ss!" \
  --admin_email dev@portal.test
```

### Generated Directory Structure

```text
<install_path>/<site-slug>/
└── .docker/
    ├── .env
    ├── docker-compose.yml
    └── dockerfiles/
```

## Todos

- Run a global `nginx-proxy` container on port `80`, connected to an external `proxy` network.
