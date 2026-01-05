#!/bin/bash
set -e

# Mautic Docker Entrypoint
# Handles different roles: mautic_web, mautic_cron, mautic_worker

MAUTIC_ROOT="${MAUTIC_ROOT:-/var/www/html}"
DOCKER_MAUTIC_ROLE="${DOCKER_MAUTIC_ROLE:-mautic_web}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Wait for database to be ready
wait_for_db() {
    log_info "Waiting for database connection..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if php -r "
            \$host = getenv('MAUTIC_DB_HOST') ?: 'mysql';
            \$port = getenv('MAUTIC_DB_PORT') ?: 3306;
            \$user = getenv('MAUTIC_DB_USER') ?: 'mautic';
            \$pass = getenv('MAUTIC_DB_PASSWORD') ?: '';
            
            try {
                new PDO(\"mysql:host=\$host;port=\$port\", \$user, \$pass, [
                    PDO::ATTR_TIMEOUT => 5,
                    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION
                ]);
                exit(0);
            } catch (Exception \$e) {
                exit(1);
            }
        " 2>/dev/null; then
            log_info "Database connection established"
            return 0
        fi
        
        log_warn "Database not ready, attempt $attempt/$max_attempts..."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    log_error "Could not connect to database after $max_attempts attempts"
    return 1
}

# Generate local.php configuration if it doesn't exist
generate_config() {
    local config_file="${MAUTIC_ROOT}/app/config/local.php"
    
    if [ ! -f "$config_file" ] && [ -n "$MAUTIC_DB_HOST" ]; then
        log_info "Generating Mautic configuration..."
        
        cat > "$config_file" << EOF
<?php
\$parameters = [
    'db_driver' => 'pdo_mysql',
    'db_host' => '${MAUTIC_DB_HOST:-mysql}',
    'db_port' => ${MAUTIC_DB_PORT:-3306},
    'db_name' => '${MAUTIC_DB_DATABASE:-mautic}',
    'db_user' => '${MAUTIC_DB_USER:-mautic}',
    'db_password' => '${MAUTIC_DB_PASSWORD}',
    'db_table_prefix' => '${MAUTIC_DB_PREFIX:-}',
    'db_backup_tables' => true,
    'db_backup_prefix' => 'bak_',
    'site_url' => '${MAUTIC_URL:-http://localhost}',
    'cache_path' => '%kernel.project_dir%/var/cache',
    'log_path' => '%kernel.project_dir%/var/logs',
    'image_path' => 'media/images',
    'upload_dir' => '%kernel.project_dir%/media/files',
    'tmp_path' => '%kernel.project_dir%/var/tmp',
    'secret_key' => '${MAUTIC_SECRET_KEY:-$(openssl rand -hex 32)}',
];
EOF
        
        chown www-data:www-data "$config_file"
        log_info "Configuration generated"
    fi
}

# Run database migrations
run_migrations() {
    if [ "${DOCKER_MAUTIC_RUN_MIGRATIONS:-false}" = "true" ]; then
        log_info "Running database migrations..."
        su-exec www-data php "${MAUTIC_ROOT}/bin/console" doctrine:migrations:migrate --no-interaction || {
            log_warn "Migrations failed or already applied"
        }
    fi
}

# Load test data if requested
load_test_data() {
    if [ "${DOCKER_MAUTIC_LOAD_TEST_DATA:-false}" = "true" ]; then
        log_info "Loading test data..."
        su-exec www-data php "${MAUTIC_ROOT}/bin/console" mautic:install:data --force || {
            log_warn "Test data loading failed"
        }
    fi
}

# Clear and warm up cache
warm_cache() {
    log_info "Warming up cache..."
    su-exec www-data php "${MAUTIC_ROOT}/bin/console" cache:clear --no-warmup
    su-exec www-data php "${MAUTIC_ROOT}/bin/console" cache:warmup
}

# Start cron jobs
start_cron() {
    log_info "Starting cron service..."
    
    # Install crontab
    cat > /etc/cron.d/mautic << 'EOF'
# Mautic cron jobs
# Run these at appropriate intervals for your setup

# Segment update - every 5 minutes
*/5 * * * * www-data php /var/www/html/bin/console mautic:segments:update >> /var/log/mautic-cron.log 2>&1

# Campaign update - every 5 minutes  
*/5 * * * * www-data php /var/www/html/bin/console mautic:campaigns:update >> /var/log/mautic-cron.log 2>&1

# Campaign trigger - every 5 minutes
*/5 * * * * www-data php /var/www/html/bin/console mautic:campaigns:trigger >> /var/log/mautic-cron.log 2>&1

# Process broadcasts - every 5 minutes
*/5 * * * * www-data php /var/www/html/bin/console mautic:broadcasts:send >> /var/log/mautic-cron.log 2>&1

# Process email queue - every 1 minute
* * * * * www-data php /var/www/html/bin/console mautic:emails:send >> /var/log/mautic-cron.log 2>&1

# Fetch emails (if IMAP is configured) - every 5 minutes
*/5 * * * * www-data php /var/www/html/bin/console mautic:email:fetch >> /var/log/mautic-cron.log 2>&1

# Social monitoring - every 10 minutes
*/10 * * * * www-data php /var/www/html/bin/console mautic:social:monitoring >> /var/log/mautic-cron.log 2>&1

# Webhooks - every 1 minute
* * * * * www-data php /var/www/html/bin/console mautic:webhooks:process >> /var/log/mautic-cron.log 2>&1

# Import contacts - every 5 minutes
*/5 * * * * www-data php /var/www/html/bin/console mautic:import >> /var/log/mautic-cron.log 2>&1

# Reports scheduler - every 10 minutes
*/10 * * * * www-data php /var/www/html/bin/console mautic:reports:scheduler >> /var/log/mautic-cron.log 2>&1

# Maintenance cleanup - daily at 2am
0 2 * * * www-data php /var/www/html/bin/console mautic:maintenance:cleanup --days-old=365 >> /var/log/mautic-cron.log 2>&1

# Max mind GeoIP update - weekly on Sunday at 3am
0 3 * * 0 www-data php /var/www/html/bin/console mautic:iplookup:download >> /var/log/mautic-cron.log 2>&1

# Clear old data - monthly on 1st at 4am
0 4 1 * * www-data php /var/www/html/bin/console mautic:unusedip:delete >> /var/log/mautic-cron.log 2>&1
EOF

    chmod 0644 /etc/cron.d/mautic
    touch /var/log/mautic-cron.log
    chown www-data:www-data /var/log/mautic-cron.log
    
    # Start cron in foreground
    cron -f
}

# Start message queue workers
start_workers() {
    log_info "Starting message queue workers..."
    
    local email_workers="${DOCKER_MAUTIC_WORKERS_CONSUME_EMAIL:-2}"
    local hit_workers="${DOCKER_MAUTIC_WORKERS_CONSUME_HIT:-2}"
    local failed_workers="${DOCKER_MAUTIC_WORKERS_CONSUME_FAILED:-1}"
    
    # Start supervisord which will manage the workers
    exec supervisord -c /etc/supervisor/supervisord.conf
}

# Main entrypoint logic
main() {
    log_info "Starting Mautic container in role: ${DOCKER_MAUTIC_ROLE}"
    
    # Fix permissions
    chown -R www-data:www-data "${MAUTIC_ROOT}/var" 2>/dev/null || true
    chown -R www-data:www-data "${MAUTIC_ROOT}/media" 2>/dev/null || true
    chown -R www-data:www-data "${MAUTIC_ROOT}/app/config" 2>/dev/null || true
    
    case "${DOCKER_MAUTIC_ROLE}" in
        mautic_web)
            wait_for_db
            generate_config
            run_migrations
            load_test_data
            log_info "Starting Apache..."
            exec "$@"
            ;;
        mautic_cron)
            wait_for_db
            log_info "Starting in cron mode..."
            start_cron
            ;;
        mautic_worker)
            wait_for_db
            log_info "Starting in worker mode..."
            start_workers
            ;;
        *)
            log_error "Unknown role: ${DOCKER_MAUTIC_ROLE}"
            log_error "Valid roles: mautic_web, mautic_cron, mautic_worker"
            exit 1
            ;;
    esac
}

main "$@"
