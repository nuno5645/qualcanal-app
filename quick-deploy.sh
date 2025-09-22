#!/bin/bash

# Quick Deployment Script for QualCanal
# This script handles the most common deployment scenarios

set -e

SERVER="167.172.99.206"
USER="root"
DOMAIN="qualcanal.pt"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🚀 QualCanal Quick Deployment${NC}"
echo "Server: $SERVER"
echo "Domain: $DOMAIN"
echo

# Make deploy script executable
chmod +x deploy.sh

# Check if this is first time setup
echo -e "${YELLOW}Is this the first time setting up the server? (y/N)${NC}"
read -r first_setup

if [[ $first_setup =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}📦 Setting up server...${NC}"
    ./deploy.sh --setup
    
    echo
    echo -e "${YELLOW}Do you want to setup SSL certificates now? (y/N)${NC}"
    echo "Note: Make sure your domain DNS is pointing to $SERVER first!"
    read -r setup_ssl
    
    if [[ $setup_ssl =~ ^[Yy]$ ]]; then
        ./deploy.sh --ssl
    else
        echo -e "${YELLOW}⚠️ Remember to run './deploy.sh --ssl' after DNS is configured${NC}"
    fi
else
    echo -e "${BLUE}🔄 Updating existing deployment...${NC}"
    ./deploy.sh
fi

echo
echo -e "${GREEN}✅ Deployment completed!${NC}"
echo
echo "🌐 Your application should be available at:"
echo "   http://$DOMAIN"
echo "   http://$SERVER"
echo
echo "📋 Next steps:"
echo "1. Ensure DNS for $DOMAIN points to $SERVER"
echo "2. Configure environment variables on server:"
echo "   ssh $USER@$SERVER 'nano /opt/qualcanal-app/.env.prod'"
echo "3. Setup SSL if not done already:"
echo "   ./deploy.sh --ssl"
echo
echo "🔧 Useful commands:"
echo "   View logs: ssh $USER@$SERVER 'cd /opt/qualcanal-app && docker compose -f docker-compose.prod.yml logs -f'"
echo "   Restart:   ssh $USER@$SERVER 'cd /opt/qualcanal-app && docker compose -f docker-compose.prod.yml restart'"
