# 🚀 QualCanal Server Deployment Guide

Complete guide for deploying QualCanal on your server `167.172.99.206`.

## 📋 Quick Start

### 1. **Connect to Your Server**
```bash
ssh root@167.172.99.206
```

### 2. **Clone the Repository**
```bash
cd /opt
git clone <your-repository-url> qualcanal-app
cd qualcanal-app
```

### 3. **Run Server Setup (First Time Only)**
```bash
sudo chmod +x server-setup.sh
sudo ./server-setup.sh
```

### 4. **Deploy the Application**
```bash
sudo chmod +x server-deploy.sh
sudo ./server-deploy.sh
```

### 5. **Setup SSL (After DNS Configuration)**
```bash
sudo ./server-deploy.sh --ssl
```

## 🔧 Detailed Instructions

### **Initial Server Setup**

The `server-setup.sh` script will:
- ✅ Update system packages
- ✅ Install Docker, nginx, certbot, and other dependencies  
- ✅ Configure firewall (UFW)
- ✅ Create application directories
- ✅ Generate secure Django secret key
- ✅ Setup log rotation
- ✅ Create monitoring and backup scripts
- ✅ Setup helpful aliases

### **Application Deployment**

The `server-deploy.sh` script will:
- ✅ Build Docker containers
- ✅ Start all services (nginx, backend, frontend)
- ✅ Setup SSL certificates (with --ssl flag)
- ✅ Configure automatic backups
- ✅ Health check all services

## 🌐 DNS Configuration

**Before SSL setup**, configure your domain DNS:

```
A Record: qualcanal.pt → 167.172.99.206
A Record: www.qualcanal.pt → 167.172.99.206
```

## ⚙️ Configuration Files

### **Environment Variables** (`/opt/qualcanal-app/.env.prod`)
```bash
# Edit production settings
sudo nano /opt/qualcanal-app/.env.prod
```

Key settings to customize:
- `DJANGO_SECRET_KEY` (auto-generated)
- `DATABASE_URL` (if using PostgreSQL)
- Email settings for notifications
- Cache settings

### **Nginx Configuration**
Production nginx config: `nginx/nginx.prod.conf`
- SSL/TLS termination
- Security headers
- Rate limiting
- Gzip compression

## 🔐 SSL Certificates

### **Automatic Setup (Recommended)**
```bash
sudo ./server-deploy.sh --ssl
```

### **Manual Setup**
```bash
# Stop nginx temporarily
cd /opt/qualcanal-app
sudo docker compose -f docker-compose.prod.yml stop nginx

# Get certificates
sudo certbot certonly --standalone -d qualcanal.pt -d www.qualcanal.pt

# Copy certificates
sudo cp /etc/letsencrypt/live/qualcanal.pt/fullchain.pem ssl/qualcanal.pt.crt
sudo cp /etc/letsencrypt/live/qualcanal.pt/privkey.pem ssl/qualcanal.pt.key

# Restart nginx
sudo docker compose -f docker-compose.prod.yml start nginx
```

## 🛠️ Management Commands

After setup, use these convenient aliases:

```bash
qc-status     # Check application status
qc-logs       # View live logs  
qc-restart    # Restart all services
qc-update     # Pull from git and rebuild
qc-shell      # Navigate to app directory
```

### **Manual Commands**
```bash
cd /opt/qualcanal-app

# View logs
sudo docker compose -f docker-compose.prod.yml logs -f

# Restart services
sudo docker compose -f docker-compose.prod.yml restart

# Rebuild containers
sudo docker compose -f docker-compose.prod.yml up -d --build

# Check status
sudo docker compose -f docker-compose.prod.yml ps
```

## 💾 Backup & Monitoring

### **Automatic Backups**
- Weekly backups scheduled via cron
- Manual backup: `sudo qualcanal-backup`
- Backups stored in `/opt/backups/qualcanal/`

### **Monitoring**
- Status check: `sudo qualcanal-status`
- System resources, logs, and service status
- Automatic security updates enabled

## 🔥 Firewall Configuration

Ports automatically configured:
- `22` - SSH
- `80` - HTTP (redirects to HTTPS)
- `443` - HTTPS

## 📊 Architecture

```
Internet
    ↓
Nginx (Port 80/443)
├── SSL Termination
├── Security Headers  
├── Rate Limiting
├── Gzip Compression
└── Routing:
    ├── /api/* → Django Backend (:8000)
    └── /* → Next.js Frontend (:3000)
```

## 🆘 Troubleshooting

### **Services Not Starting**
```bash
cd /opt/qualcanal-app
sudo docker compose -f docker-compose.prod.yml logs
```

### **SSL Issues**
```bash
# Check certificate
sudo openssl x509 -in ssl/qualcanal.pt.crt -text -noout

# Regenerate certificate
sudo ./server-deploy.sh --ssl
```

### **DNS Issues**
```bash
# Check DNS propagation
nslookup qualcanal.pt
dig qualcanal.pt
```

### **Performance Issues**
```bash
# Check resources
qc-status
htop
df -h
```

## 🔄 Updates

### **Application Updates**
```bash
cd /opt/qualcanal-app
git pull
sudo ./server-deploy.sh
```

### **System Updates**
- Automatic security updates enabled
- Manual: `sudo apt update && sudo apt upgrade`

## 🌟 Production Features

- ✅ **HTTPS with automatic SSL renewal**
- ✅ **Security headers and rate limiting**
- ✅ **Gzip compression**
- ✅ **Static file caching**  
- ✅ **Health checks**
- ✅ **Log rotation**
- ✅ **Automatic backups**
- ✅ **System monitoring**
- ✅ **Firewall protection**
- ✅ **Docker containerization**

## 📞 Support

If you encounter issues:
1. Check logs: `qc-logs`
2. Check status: `qc-status`  
3. Restart services: `qc-restart`
4. Review this guide
5. Check Docker containers: `sudo docker ps`

Your application will be available at:
- **http://167.172.99.206** (immediately)
- **https://qualcanal.pt** (after DNS + SSL setup)
