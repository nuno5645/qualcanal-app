#!/bin/bash

# QualCanal Server Deployment Script
# Run this script on your server after cloning the repository
# Usage: sudo ./server-deploy.sh [--ssl]

set -e  # Exit on any error

# Configuration
APP_DIR="/opt/qualcanal-app"
DOMAIN="qualcanal.pt"
SERVER_IP=$(curl -s ipinfo.io/ip 2>/dev/null || hostname -I | awk '{print $1}')

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
   exit 1
fi

# Check if we're in the right directory
if [[ ! -f "docker-compose.prod.yml" ]]; then
    error "docker-compose.prod.yml not found. Make sure you're in the application directory."
    exit 1
fi

log "🚀 Deploying QualCanal application..."
log "Server IP: $SERVER_IP"
log "Domain: $DOMAIN"

# Ensure .env.prod exists
if [[ ! -f ".env.prod" ]]; then
    warning ".env.prod not found, creating from template..."
    if [[ -f "env.example" ]]; then
        cp env.example .env.prod
        # Generate a secure Django secret key
        DJANGO_SECRET=$(python3 -c "import secrets; print(secrets.token_urlsafe(50))" 2>/dev/null || openssl rand -base64 50)
        sed -i "s/your-super-secret-key-change-this-immediately/$DJANGO_SECRET/" .env.prod
        success "Created .env.prod with secure secret key"
    else
        error "Neither .env.prod nor env.example found!"
        exit 1
    fi
fi

# Create necessary directories
log "📁 Setting up directories..."
mkdir -p ssl logs/nginx logs/django
chown -R root:root .
chmod -R 755 .
chmod 600 .env.prod

# Stop any running containers
log "🛑 Stopping existing containers..."
docker compose --env-file .env.prod -f docker-compose.prod.yml down 2>/dev/null || true

# Clean up old images and containers
log "🧹 Cleaning up old Docker resources..."
docker system prune -f

# Build the application
log "🔨 Building application..."
docker compose --env-file .env.prod -f docker-compose.prod.yml build --no-cache

# Check if SSL setup is requested
if [[ "$1" == "--ssl" ]]; then
    log "🔒 Setting up SSL certificates..."

    # Ensure no leftover temp container and stop host nginx if present
    docker rm -f nginx-temp 2>/dev/null || true
    systemctl stop nginx 2>/dev/null || true
    systemctl disable nginx 2>/dev/null || true

    # Obtain certificate using standalone authenticator (binds to :80 temporarily)
    log "Requesting SSL certificate from Let's Encrypt (standalone)..."
    set +e
    certbot certonly \
        --standalone \
        --preferred-challenges http \
        --http-01-port 80 \
        --cert-name $DOMAIN \
        -d $DOMAIN -d www.$DOMAIN \
        --agree-tos \
        --no-eff-email \
        --register-unsafely-without-email \
        --expand \
        --non-interactive
    CERTBOT_EXIT_CODE=$?
    set -e

    if [[ $CERTBOT_EXIT_CODE -ne 0 ]]; then
        warning "Let's Encrypt issuance failed (exit $CERTBOT_EXIT_CODE). Falling back to self-signed cert."
        mkdir -p ssl
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout ssl/$DOMAIN.key \
            -out ssl/$DOMAIN.crt \
            -subj "/C=PT/ST=Portugal/L=Lisbon/O=QualCanal/CN=$DOMAIN"
        chmod 644 ssl/$DOMAIN.crt
        chmod 600 ssl/$DOMAIN.key
    else
        # Copy certificates for nginx container consumption
        log "Installing SSL certificates..."
        mkdir -p ssl
        cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem ssl/$DOMAIN.crt
        cp /etc/letsencrypt/live/$DOMAIN/privkey.pem ssl/$DOMAIN.key
        chmod 644 ssl/$DOMAIN.crt
        chmod 600 ssl/$DOMAIN.key

        # Setup auto-renewal cron job with deploy hook to restart nginx
        log "Setting up SSL auto-renewal..."
        (crontab -l 2>/dev/null | grep -v certbot; echo "0 12 * * * /usr/bin/certbot renew --quiet --deploy-hook 'cd $APP_DIR && docker compose --env-file .env.prod -f docker-compose.prod.yml restart nginx'") | crontab -
        success "SSL certificates installed and auto-renewal configured!"
    fi
    
elif [[ ! -f "ssl/$DOMAIN.crt" ]]; then
    warning "No SSL certificates found. Creating self-signed certificates for testing..."
    
    # Create self-signed certificate for testing
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout ssl/$DOMAIN.key \
        -out ssl/$DOMAIN.crt \
        -subj "/C=PT/ST=Portugal/L=Lisbon/O=QualCanal/CN=$DOMAIN"
    
    chmod 644 ssl/$DOMAIN.crt
    chmod 600 ssl/$DOMAIN.key
    
    warning "Self-signed certificate created. Run with --ssl flag to get real certificates."
fi

# Start the application
log "🚀 Starting application..."
docker compose --env-file .env.prod -f docker-compose.prod.yml up -d

# Wait for services to be ready
log "⏳ Waiting for services to start..."
sleep 30

# Check service health
log "🏥 Checking service health..."
max_attempts=12
attempt=0

while [[ $attempt -lt $max_attempts ]]; do
    if docker compose --env-file .env.prod -f docker-compose.prod.yml ps | grep -q "Up"; then
        success "Services are running!"
        break
    fi
    
    attempt=$((attempt + 1))
    log "Attempt $attempt/$max_attempts - waiting for services..."
    sleep 10
done

if [[ $attempt -eq $max_attempts ]]; then
    error "Services failed to start properly. Check logs:"
    docker compose --env-file .env.prod -f docker-compose.prod.yml logs
    exit 1
fi

# Test connectivity
log "🌐 Testing connectivity..."
if curl -s -o /dev/null -w "%{http_code}" "http://localhost" | grep -q "200\|301\|302"; then
    success "Application is responding!"
else
    warning "Application may not be fully ready yet"
fi

# Display status
log "📊 Application status:"
docker compose --env-file .env.prod -f docker-compose.prod.yml ps

# Create backup script
log "💾 Creating backup script..."
cat > /usr/local/bin/qualcanal-backup << 'EOF'
#!/bin/bash
BACKUP_DIR="/opt/backups/qualcanal"
DATE=$(date +"%Y%m%d_%H%M%S")

mkdir -p $BACKUP_DIR

# Backup database
cd /opt/qualcanal-app
docker compose --env-file .env.prod -f docker-compose.prod.yml exec -T backend python manage.py dumpdata > $BACKUP_DIR/db_backup_$DATE.json

# Backup environment and configs
cp .env.prod $BACKUP_DIR/env_backup_$DATE
cp -r ssl $BACKUP_DIR/ssl_backup_$DATE

# Keep only last 7 days of backups
find $BACKUP_DIR -name "*backup*" -type f -mtime +7 -delete

echo "Backup completed: $BACKUP_DIR"
EOF

chmod +x /usr/local/bin/qualcanal-backup

# Setup weekly backups
(crontab -l 2>/dev/null | grep -v qualcanal-backup; echo "0 2 * * 0 /usr/local/bin/qualcanal-backup") | crontab -

success "Backup script created and scheduled weekly"

# Final status and instructions
echo
echo "🎉 Deployment completed successfully!"
echo
echo "📊 Current Status:"
docker compose --env-file .env.prod -f docker-compose.prod.yml ps
echo
echo "🌐 Your application is available at:"
echo "   http://$SERVER_IP"
if [[ -f "ssl/$DOMAIN.crt" ]]; then
    echo "   https://$DOMAIN (if DNS is configured)"
    echo "   https://$SERVER_IP"
fi
echo
echo "📋 Important Information:"
echo "   Domain: $DOMAIN"
echo "   Server IP: $SERVER_IP"
echo "   App Directory: $APP_DIR"
echo "   Environment: .env.prod"
echo
echo "🔧 Management Commands:"
echo "   Status:   qc-status"
echo "   Logs:     qc-logs"
echo "   Restart:  qc-restart"
echo "   Update:   qc-update"
echo "   Backup:   qualcanal-backup"
echo
echo "📝 Next Steps:"
echo "1. Configure your domain DNS to point to: $SERVER_IP"
echo "2. Edit .env.prod if needed: nano .env.prod"
if [[ "$1" != "--ssl" && ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]]; then
    echo "3. Setup SSL certificates: sudo ./server-deploy.sh --ssl"
fi
echo
echo "🆘 Troubleshooting:"
echo "   View logs: docker compose --env-file .env.prod -f docker-compose.prod.yml logs -f"
echo "   Restart:   docker compose --env-file .env.prod -f docker-compose.prod.yml restart"
echo "   Rebuild:   docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --build"

success "QualCanal is now running in production mode!"
