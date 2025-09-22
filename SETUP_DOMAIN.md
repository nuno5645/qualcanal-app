# Domain Setup for qualcanal.pt

## For Local Development

To test with the domain `qualcanal.pt` locally, you need to add an entry to your hosts file:

### On macOS/Linux:
```bash
sudo echo "127.0.0.1 qualcanal.pt" >> /etc/hosts
sudo echo "127.0.0.1 www.qualcanal.pt" >> /etc/hosts
```

### On Windows:
1. Open `C:\Windows\System32\drivers\etc\hosts` as Administrator
2. Add these lines:
```
127.0.0.1 qualcanal.pt
127.0.0.1 www.qualcanal.pt
```

## Starting the Application

After updating your hosts file, run:
```bash
docker compose up --build
```

Then visit: http://qualcanal.pt

## Architecture

```
Internet/Browser (qualcanal.pt)
        ↓
    Nginx (Port 80/443)
    ├── /api/* → Backend (Django :8000)
    └── /* → Frontend (Next.js :3000)
```

## Features Included

- ✅ Nginx reverse proxy
- ✅ Domain routing (qualcanal.pt)
- ✅ API routing (/api/* → backend)
- ✅ Frontend routing (/* → frontend)
- ✅ CORS configuration
- ✅ Security headers
- ✅ Rate limiting (API: 10r/s, Auth: 1r/s)
- ✅ Gzip compression
- ✅ Static file caching
- ✅ WebSocket support (for Next.js hot reload)
- 🔄 HTTPS ready (commented out for development)

## Production Setup

For production deployment:

1. **DNS**: Point `qualcanal.pt` and `www.qualcanal.pt` to your server's IP
2. **SSL**: Uncomment HTTPS section in `nginx/nginx.conf` and add SSL certificates
3. **Environment**: Set production environment variables
4. **Security**: Change `DJANGO_SECRET_KEY` and enable security features

## SSL Certificate Setup (Production)

```bash
# Using Let's Encrypt (example)
certbot certonly --standalone -d qualcanal.pt -d www.qualcanal.pt

# Then uncomment the HTTPS server block in nginx.conf
# and update certificate paths
```
