#!/bin/bash

# QualCanal Server Setup Script
# Run this script on your server after git cloning the repository
# Usage: sudo ./server-setup.sh

set -e  # Exit on any error

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

log "🚀 Setting up QualCanal server..."

# Get server IP
SERVER_IP=$(curl -s ipinfo.io/ip || hostname -I | awk '{print $1}')
log "Server IP detected: $SERVER_IP"

# Update system
log "📦 Updating system packages..."
apt-get update && apt-get upgrade -y

# Install base dependencies (no docker.io to avoid conflicts)
log "📦 Installing base dependencies..."
apt-get install -y \
    git \
    curl \
    wget \
    ufw \
    certbot \
    python3-certbot-nginx \
    htop \
    nano \
    unzip \
    ca-certificates \
    gnupg \
    lsb-release

# Install Docker Engine using the official repository (handles Ubuntu 24.04/Noble)
if ! command -v docker >/dev/null 2>&1; then
    log "🐳 Installing Docker Engine from official repo..."

    # Remove potential conflicting packages first
    apt-get remove -y docker.io containerd runc || true
    apt-get autoremove -y || true

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    UBUNTU_CODENAME=$(lsb_release -cs)
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $UBUNTU_CODENAME stable" > /etc/apt/sources.list.d/docker.list

    apt-get update

    # Try installing Docker packages
    if ! apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        warning "Docker install encountered conflicts. Attempting conflict resolution..."
        apt-get remove -y containerd docker.io runc || true
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
else
    success "Docker already installed. Skipping Docker installation."
fi

# Start and enable Docker
log "🐳 Ensuring Docker is running..."
systemctl enable docker || true
systemctl start docker || true

# Add current user to docker group if not root
if [[ $SUDO_USER ]]; then
    usermod -aG docker $SUDO_USER
    log "Added $SUDO_USER to docker group"
fi

# Setup firewall
log "🔥 Configuring firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80
ufw allow 443
ufw --force enable

success "Firewall configured"

# Create application directory structure
APP_DIR="/opt/qualcanal-app"
log "📁 Setting up application directory..."

mkdir -p $APP_DIR/ssl
mkdir -p $APP_DIR/logs/nginx
mkdir -p $APP_DIR/logs/django
mkdir -p /var/www/certbot

# Set proper permissions
chown -R $SUDO_USER:$SUDO_USER $APP_DIR 2>/dev/null || chown -R root:root $APP_DIR
chmod -R 755 $APP_DIR

success "Application directories created"

# Generate secure Django secret key
log "🔐 Generating secure Django secret key..."
DJANGO_SECRET=$(python3 -c "import secrets; print(secrets.token_urlsafe(50))")

# Create production environment file
log "📝 Creating production environment file..."
cat > $APP_DIR/.env.prod << EOF
# Production Environment Variables for QualCanal
# Generated on $(date)

# Django Settings
DJANGO_SECRET_KEY=$DJANGO_SECRET
DJANGO_DEBUG=false

# Database (Optional - uses SQLite by default)
# DATABASE_URL=postgresql://user:password@postgres:5432/qualcanal

# PostgreSQL (if using database)
# POSTGRES_USER=qualcanal
# POSTGRES_PASSWORD=your-secure-password
# POSTGRES_DB=qualcanal

# Email Settings (Optional)
# EMAIL_HOST=smtp.gmail.com
# EMAIL_PORT=587
# EMAIL_USE_TLS=true
# EMAIL_HOST_USER=your-email@gmail.com
# EMAIL_HOST_PASSWORD=your-app-password

# Cache Settings
MATCH_CACHE_SECONDS=300

# Server Info
SERVER_IP=$SERVER_IP
EOF

success "Environment file created at $APP_DIR/.env.prod"

# Setup log rotation
log "📜 Setting up log rotation..."
cat > /etc/logrotate.d/qualcanal << EOF
$APP_DIR/logs/nginx/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 root root
    postrotate
        docker exec qualcanal-app-nginx-1 nginx -s reload 2>/dev/null || true
    endscript
}

$APP_DIR/logs/django/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 root root
}
EOF

success "Log rotation configured"

# Setup system monitoring
log "📊 Setting up basic monitoring..."
cat > /usr/local/bin/qualcanal-status << 'EOF'
#!/bin/bash
echo "=== QualCanal Application Status ==="
echo "Date: $(date)"
echo "Server: $(hostname) ($(curl -s ipinfo.io/ip))"
echo
echo "=== Docker Services ==="
cd /opt/qualcanal-app && docker compose -f docker-compose.prod.yml ps
echo
echo "=== System Resources ==="
echo "CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)% used"
echo "Memory: $(free -h | awk '/^Mem:/ {print $3 "/" $2}')"
echo "Disk: $(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 " used)"}')"
echo
echo "=== Recent Logs (last 10 lines) ==="
cd /opt/qualcanal-app && docker compose -f docker-compose.prod.yml logs --tail=10
EOF

chmod +x /usr/local/bin/qualcanal-status

success "Monitoring script created: /usr/local/bin/qualcanal-status"

# Setup automatic updates
log "🔄 Setting up automatic security updates..."
apt-get install -y unattended-upgrades
cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

systemctl enable unattended-upgrades

success "Automatic security updates enabled"

# Create helpful aliases
log "⚡ Creating helpful aliases..."
cat >> /root/.bashrc << 'EOF'

# QualCanal aliases
alias qc-status='qualcanal-status'
alias qc-logs='cd /opt/qualcanal-app && docker compose -f docker-compose.prod.yml logs -f'
alias qc-restart='cd /opt/qualcanal-app && docker compose -f docker-compose.prod.yml restart'
alias qc-update='cd /opt/qualcanal-app && git pull && docker compose -f docker-compose.prod.yml up -d --build'
alias qc-shell='cd /opt/qualcanal-app'
EOF

if [[ $SUDO_USER ]]; then
    cat >> /home/$SUDO_USER/.bashrc << 'EOF'

# QualCanal aliases
alias qc-status='sudo qualcanal-status'
alias qc-logs='cd /opt/qualcanal-app && sudo docker compose -f docker-compose.prod.yml logs -f'
alias qc-restart='cd /opt/qualcanal-app && sudo docker compose -f docker-compose.prod.yml restart'
alias qc-update='cd /opt/qualcanal-app && git pull && sudo docker compose -f docker-compose.prod.yml up -d --build'
alias qc-shell='cd /opt/qualcanal-app'
EOF
fi

success "Helpful aliases created"

# Final setup message
echo
echo "🎉 Server setup completed successfully!"
echo
echo "📋 Next steps:"
echo "1. Clone your repository:"
echo "   git clone <your-repo-url> $APP_DIR"
echo "   cd $APP_DIR"
echo
echo "2. Run the deployment script:"
echo "   sudo ./server-deploy.sh"
echo
echo "3. Setup SSL certificates:"
echo "   sudo ./server-deploy.sh --ssl"
echo
echo "🔧 Useful commands:"
echo "   qc-status    - Check application status"
echo "   qc-logs      - View live logs"
echo "   qc-restart   - Restart services"
echo "   qc-update    - Update from git and rebuild"
echo
echo "📁 Important files:"
echo "   Environment: $APP_DIR/.env.prod"
echo "   Logs:        $APP_DIR/logs/"
echo "   SSL:         $APP_DIR/ssl/"
echo
echo "⚠️  Remember to:"
echo "   - Configure your domain DNS to point to: $SERVER_IP"
echo "   - Edit $APP_DIR/.env.prod with your settings"
echo "   - Run 'source ~/.bashrc' to load new aliases"

if [[ $SUDO_USER ]]; then
    warning "You may need to log out and back in for Docker group permissions to take effect"
fi
