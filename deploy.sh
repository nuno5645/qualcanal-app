#!/bin/bash

# QualCanal Production Deployment Script
# Usage: ./deploy.sh [--setup] [--ssl]

set -e  # Exit on any error

SERVER="167.172.99.206"
USER="root"
APP_DIR="/opt/qualcanal-app"
DOMAIN="qualcanal.pt"

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

# Function to run commands on the server
run_remote() {
    ssh $USER@$SERVER "$1"
}

# Function to copy files to server
copy_to_server() {
    scp -r "$1" $USER@$SERVER:"$2"
}

# Check if this is initial setup
if [[ "$1" == "--setup" ]]; then
    log "Setting up server for initial deployment..."
    
    # Update system and install dependencies
    log "Updating system and installing dependencies..."
    run_remote "apt-get update && apt-get upgrade -y"
    run_remote "apt-get install -y docker.io docker-compose-plugin git curl ufw certbot python3-certbot-nginx"
    
    # Start and enable Docker
    run_remote "systemctl start docker && systemctl enable docker"
    
    # Setup firewall
    log "Configuring firewall..."
    run_remote "ufw allow ssh && ufw allow 80 && ufw allow 443 && ufw --force enable"
    
    # Create application directory
    run_remote "mkdir -p $APP_DIR"
    run_remote "mkdir -p $APP_DIR/ssl"
    run_remote "mkdir -p $APP_DIR/logs/nginx"
    run_remote "mkdir -p $APP_DIR/logs/django"
    
    success "Server setup completed!"
fi

# Copy application files
log "Copying application files to server..."
copy_to_server "." "$APP_DIR/"

# Create production environment file if it doesn't exist
log "Setting up environment variables..."
run_remote "cd $APP_DIR && if [ ! -f .env.prod ]; then cp .env.example .env.prod; fi"

# Build and start the application
log "Building and starting the application..."
run_remote "cd $APP_DIR && docker compose -f docker-compose.prod.yml down || true"
run_remote "cd $APP_DIR && docker compose -f docker-compose.prod.yml build --no-cache"
run_remote "cd $APP_DIR && docker compose -f docker-compose.prod.yml up -d"

# Wait for services to be ready
log "Waiting for services to start..."
sleep 30

# Check if services are running
log "Checking service status..."
run_remote "cd $APP_DIR && docker compose -f docker-compose.prod.yml ps"

# Setup SSL if requested
if [[ "$1" == "--ssl" ]] || [[ "$2" == "--ssl" ]]; then
    log "Setting up SSL certificate..."
    
    # Stop nginx temporarily for standalone certbot
    run_remote "cd $APP_DIR && docker compose -f docker-compose.prod.yml stop nginx"
    
    # Get SSL certificate
    run_remote "certbot certonly --standalone -d $DOMAIN -d www.$DOMAIN --agree-tos --no-eff-email --register-unsafely-without-email"
    
    # Copy certificates to application directory
    run_remote "cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem $APP_DIR/ssl/$DOMAIN.crt"
    run_remote "cp /etc/letsencrypt/live/$DOMAIN/privkey.pem $APP_DIR/ssl/$DOMAIN.key"
    
    # Set proper permissions
    run_remote "chmod 644 $APP_DIR/ssl/$DOMAIN.crt"
    run_remote "chmod 600 $APP_DIR/ssl/$DOMAIN.key"
    
    # Restart nginx with SSL
    run_remote "cd $APP_DIR && docker compose -f docker-compose.prod.yml start nginx"
    
    # Setup auto-renewal
    run_remote "crontab -l | grep -v certbot || true" # Remove existing certbot entries
    run_remote "(crontab -l 2>/dev/null; echo '0 12 * * * /usr/bin/certbot renew --quiet --deploy-hook \"cd $APP_DIR && docker compose -f docker-compose.prod.yml restart nginx\"') | crontab -"
    
    success "SSL certificate installed and auto-renewal configured!"
fi

# Final status check
log "Final deployment status:"
run_remote "cd $APP_DIR && docker compose -f docker-compose.prod.yml ps"

# Check if site is accessible
log "Testing site accessibility..."
if curl -s -o /dev/null -w "%{http_code}" "http://$SERVER" | grep -q "200\|301\|302"; then
    success "Site is accessible at http://$DOMAIN"
else
    warning "Site may not be fully accessible yet. Check logs with: ssh $USER@$SERVER 'cd $APP_DIR && docker compose -f docker-compose.prod.yml logs'"
fi

success "Deployment completed!"
echo
echo "📋 Next steps:"
echo "1. Point your domain DNS to $SERVER"
echo "2. Update .env.prod file on the server with your settings"
echo "3. Run './deploy.sh --ssl' to setup SSL certificates"
echo
echo "🔧 Useful commands:"
echo "   View logs: ssh $USER@$SERVER 'cd $APP_DIR && docker compose -f docker-compose.prod.yml logs -f'"
echo "   Restart:   ssh $USER@$SERVER 'cd $APP_DIR && docker compose -f docker-compose.prod.yml restart'"
echo "   Update:    ./deploy.sh"
