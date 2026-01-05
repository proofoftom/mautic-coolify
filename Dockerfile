# Custom Mautic Docker Image
# Based on official mautic/mautic with custom plugins, themes, and patches
#
# Build with:
#   docker build -t your-registry/mautic-custom:7.0.0-rc2 .
#
# For development from your fork:
#   docker build --build-arg MAUTIC_VERSION=dev-7.0.0-rc2 \
#                --build-arg MAUTIC_REPO=https://github.com/proofoftom/mautic.git \
#                -t your-registry/mautic-custom:7.0.0-rc2 .

ARG BASE_TAG=8.4-apache-bookworm
FROM php:${BASE_TAG}

# Build arguments
ARG MAUTIC_VERSION=7.0.0-beta
ARG MAUTIC_REPO=https://github.com/mautic/mautic.git
ARG COMPOSER_VERSION=2.7

LABEL maintainer="Your Name <your@email.com>" \
      description="Custom Mautic ${MAUTIC_VERSION} with plugins and themes" \
      version="${MAUTIC_VERSION}"

# Environment variables
ENV MAUTIC_VERSION=${MAUTIC_VERSION} \
    COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_HOME=/tmp/composer \
    MAUTIC_ROOT=/var/www/html

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Required packages
    cron \
    git \
    wget \
    unzip \
    supervisor \
    libfreetype6-dev \
    libjpeg62-turbo-dev \
    libpng-dev \
    libzip-dev \
    libicu-dev \
    libonig-dev \
    libxslt1-dev \
    libssl-dev \
    libc-client-dev \
    libkrb5-dev \
    # For PDF generation
    libfontconfig1 \
    # Cleanup
    && rm -rf /var/lib/apt/lists/*

# Configure and install PHP extensions
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-configure imap --with-kerberos --with-imap-ssl \
    && docker-php-ext-install -j$(nproc) \
        bcmath \
        exif \
        gd \
        imap \
        intl \
        mbstring \
        mysqli \
        opcache \
        pdo_mysql \
        xsl \
        zip \
    && pecl install apcu redis \
    && docker-php-ext-enable apcu redis

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- \
        --install-dir=/usr/local/bin \
        --filename=composer \
        --version=${COMPOSER_VERSION}.7 \
    && composer --version

# Configure PHP
RUN { \
    echo 'date.timezone = UTC'; \
    echo 'memory_limit = 512M'; \
    echo 'upload_max_filesize = 64M'; \
    echo 'post_max_size = 64M'; \
    echo 'max_execution_time = 300'; \
    echo 'opcache.enable = 1'; \
    echo 'opcache.memory_consumption = 256'; \
    echo 'opcache.max_accelerated_files = 20000'; \
    echo 'opcache.validate_timestamps = 0'; \
    echo 'realpath_cache_size = 4096K'; \
    echo 'realpath_cache_ttl = 600'; \
} > /usr/local/etc/php/conf.d/mautic.ini

# Configure Apache
RUN a2enmod rewrite headers

# Create www-data user home directory
RUN mkdir -p /var/www/.composer && chown -R www-data:www-data /var/www

# Set working directory
WORKDIR ${MAUTIC_ROOT}

# Clone Mautic from repository (supports tags, branches, or dev versions)
RUN if echo "${MAUTIC_VERSION}" | grep -q "^dev-"; then \
        BRANCH=$(echo "${MAUTIC_VERSION}" | sed 's/^dev-//'); \
        git clone --depth 1 --branch ${BRANCH} ${MAUTIC_REPO} .; \
    else \
        git clone --depth 1 --branch ${MAUTIC_VERSION} ${MAUTIC_REPO} . || \
        git clone --depth 1 ${MAUTIC_REPO} . && git checkout ${MAUTIC_VERSION}; \
    fi \
    && rm -rf .git

# Install Mautic dependencies
RUN composer install --no-dev --optimize-autoloader --no-interaction --prefer-dist

# Copy custom plugins (add your plugins to the plugins/ directory)
COPY plugins/ ${MAUTIC_ROOT}/plugins/

# Copy custom themes (add your themes to the themes/ directory)  
COPY themes/ ${MAUTIC_ROOT}/themes/

# Install any additional composer packages specified
# Uncomment and modify to add marketplace plugins:
# RUN composer require mautic/helloworld-bundle:^1.0 --no-update \
#     && composer update --no-dev --optimize-autoloader

# Copy custom entrypoint and scripts
COPY scripts/ /opt/mautic/scripts/
RUN chmod +x /opt/mautic/scripts/*.sh 2>/dev/null || true

# Copy cron configuration
COPY cron/ /opt/mautic/cron/
RUN chmod +x /opt/mautic/cron/*.sh 2>/dev/null || true

# Copy supervisor configuration
COPY supervisor/ /etc/supervisor/conf.d/

# Set correct permissions
RUN chown -R www-data:www-data ${MAUTIC_ROOT} \
    && find ${MAUTIC_ROOT} -type d -exec chmod 755 {} \; \
    && find ${MAUTIC_ROOT} -type f -exec chmod 644 {} \; \
    && chmod -R 775 ${MAUTIC_ROOT}/var \
    && chmod -R 775 ${MAUTIC_ROOT}/media \
    && chmod -R 775 ${MAUTIC_ROOT}/app/config

# Copy entrypoint
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Expose port
EXPOSE 80

# Define volumes for persistence
VOLUME ["${MAUTIC_ROOT}/app/config", "${MAUTIC_ROOT}/var/logs", "${MAUTIC_ROOT}/media"]

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["apache2-foreground"]
