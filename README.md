# Custom Mautic Docker Deployment

A production-ready Docker setup for Mautic 7.0.0-rc2 with support for custom plugins, themes, and patches.

## 🚀 Features

- **Mautic 7.0.0-rc2** (or build from your own fork)
- **PHP 8.4** with optimized configuration
- **RabbitMQ** for reliable message queuing
- **Multi-role containers**: Web, Cron, and Worker services
- **Coolify-ready** with proper environment variable handling
- **Custom plugins & themes** via Composer
- **Persistent volumes** for data safety

## 📁 Project Structure

```
mautic-custom/
├── Dockerfile                 # Custom Mautic image build
├── docker-compose.yml         # Full stack deployment
├── docker-entrypoint.sh       # Container initialization
├── .env.example               # Environment variable template
├── plugins/                   # Custom plugins (add .gitkeep or your plugins)
├── themes/                    # Custom themes (add .gitkeep or your themes)
├── supervisor/
│   └── mautic-workers.conf    # Worker process management
├── scripts/                   # Custom startup scripts
└── cron/                      # Custom cron configurations
```

## 🛠️ Quick Start

### 1. Clone and Configure

```bash
# Clone this repository
git clone https://github.com/YOUR-USERNAME/mautic-custom.git
cd mautic-custom

# Copy and edit environment file
cp .env.example .env
# Edit .env with your settings
```

### 2. Add Custom Plugins (Optional)

Add plugins to the `plugins/` directory or install via Composer by editing the Dockerfile:

```dockerfile
# In Dockerfile, uncomment and modify:
RUN composer require vendor/plugin-name:^1.0 --no-update \
    && composer update --no-dev --optimize-autoloader
```

### 3. Add Custom Themes (Optional)

Add themes to the `themes/` directory:

```bash
# Example: Add a custom theme
cp -r /path/to/your-theme themes/your-theme
```

### 4. Build and Deploy

#### Local Development

```bash
# Build and start all services
docker compose up -d --build

# Watch logs
docker compose logs -f mautic_web
```

#### Deploy to Coolify

1. **Push to GitHub**: Push this repository to your GitHub account

2. **Create Service in Coolify**:
   - Go to your Coolify dashboard
   - Create a new "Docker Compose" service
   - Point to your GitHub repository
   - Branch: `main`

3. **Configure Environment Variables** in Coolify UI:
   ```
   MAUTIC_VERSION=7.0.0-beta
   MAUTIC_RUN_MIGRATIONS=true
   MAUTIC_LOAD_TEST_DATA=false
   RABBITMQ_PASSWORD=your-secure-password
   ```

4. **Deploy**: Click Deploy in Coolify

## 🔧 Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MAUTIC_VERSION` | `7.0.0-beta` | Mautic version to build |
| `MAUTIC_RUN_MIGRATIONS` | `true` | Run DB migrations on start |
| `MAUTIC_LOAD_TEST_DATA` | `false` | Load demo data |
| `MAUTIC_EMAIL_WORKERS` | `2` | Email queue workers |
| `MAUTIC_HIT_WORKERS` | `2` | Tracking queue workers |
| `PHP_MEMORY_LIMIT` | `512M` | PHP memory limit |

### Building from Your Fork

To build from your forked Mautic repository (e.g., `proofoftom/mautic`):

```bash
# Build with custom repository
docker build \
  --build-arg MAUTIC_VERSION=dev-7.0.0-rc2 \
  --build-arg MAUTIC_REPO=https://github.com/proofoftom/mautic.git \
  -t mautic-custom:7.0.0-rc2 .
```

Or in docker-compose.yml, uncomment:

```yaml
build:
  args:
    MAUTIC_REPO: 'https://github.com/proofoftom/mautic.git'
```

## 📦 Installing Plugins via Composer

Edit the Dockerfile to add Composer packages:

```dockerfile
# After "Install Mautic dependencies" section, add:
RUN composer require \
    vendor/plugin-one:^1.0 \
    vendor/plugin-two:^2.0 \
    --no-update \
  && composer update --no-dev --optimize-autoloader
```

Example marketplace plugins:

```dockerfile
# GrapesJS Builder
RUN composer require mautic/grapesjsbuilder-bundle:^3.0 --no-update

# Focus Bundle (popups)
RUN composer require mautic/focus-bundle:^3.0 --no-update

# Update after adding all requirements
RUN composer update --no-dev --optimize-autoloader
```

## 🔄 Applying Patches

Create a `patches/` directory and use Composer's patch feature:

1. Add patch file: `patches/fix-something.patch`

2. Update `composer.json`:
```json
{
    "extra": {
        "patches": {
            "mautic/core-lib": {
                "Fix something": "patches/fix-something.patch"
            }
        }
    }
}
```

## 📊 Services Overview

| Service | Port | Description |
|---------|------|-------------|
| `mautic_web` | 80 | Main web application |
| `mautic_cron` | - | Scheduled tasks (segments, campaigns) |
| `mautic_worker` | - | Message queue processors |
| `mysql` | 3306 | Database |
| `rabbitmq` | 5672, 15672 | Message queue (+ management UI) |

## 🩺 Health Checks

All services include health checks:

- **mautic_web**: HTTP check on `/`
- **mautic_cron**: Process check for `cron`
- **mautic_worker**: Process check for `messenger:consume`
- **mysql**: `mysqladmin ping`
- **rabbitmq**: `rabbitmq-diagnostics ping`

## 📋 Common Commands

```bash
# View logs
docker compose logs -f mautic_web

# Clear Mautic cache
docker compose exec mautic_web php bin/console cache:clear

# Run Mautic commands
docker compose exec --user www-data mautic_web php bin/console mautic:segments:update

# Access MySQL
docker compose exec mysql mysql -u root -p mautic

# Access RabbitMQ Management
# Visit: http://localhost:15672 (guest/guest or your configured credentials)

# Rebuild images
docker compose build --no-cache

# Full restart
docker compose down && docker compose up -d --build
```

## 🔒 Production Checklist

- [ ] Set strong passwords for MySQL and RabbitMQ
- [ ] Set `MAUTIC_LOAD_TEST_DATA=false`
- [ ] Configure HTTPS via Coolify/reverse proxy
- [ ] Set up backup schedule for volumes
- [ ] Configure email sending (SMTP or API)
- [ ] Review and adjust cron schedules
- [ ] Set appropriate worker counts for your load
- [ ] Enable monitoring/logging

## 📝 Upgrading Mautic

1. Update `MAUTIC_VERSION` in `.env` or `docker-compose.yml`
2. Rebuild: `docker compose build --no-cache`
3. Backup your database
4. Redeploy: `docker compose up -d`
5. Migrations run automatically if `MAUTIC_RUN_MIGRATIONS=true`

## 🐛 Troubleshooting

### Container won't start
```bash
# Check logs
docker compose logs mautic_web

# Verify database connection
docker compose exec mautic_web php bin/console doctrine:database:create --if-not-exists
```

### Permission issues
```bash
# Fix permissions
docker compose exec mautic_web chown -R www-data:www-data /var/www/html/var
```

### Plugin not showing
```bash
# Clear cache and reinstall assets
docker compose exec --user www-data mautic_web php bin/console cache:clear
docker compose exec --user www-data mautic_web php bin/console mautic:assets:install
```

## 📄 License

MIT License - Feel free to use and modify for your needs.

## 🔗 Resources

- [Mautic Documentation](https://docs.mautic.org)
- [Mautic Docker Official](https://github.com/mautic/docker-mautic)
- [Coolify Documentation](https://coolify.io/docs)
- [Mautic 7.0 Release Notes](https://github.com/mautic/mautic/releases)
