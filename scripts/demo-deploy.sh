#!/bin/bash

# =============================================================================
# Secret Poll - Demo Deployment Script
# =============================================================================
# This script demonstrates how to deploy Secret Poll quickly for testing/demo
# =============================================================================

set -e

echo "🚀 Secret Poll - Demo Deployment"
echo "==============================="
echo

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "❌ This demo script needs to be run as root"
    echo "Please run: sudo $0"
    exit 1
fi

# Show available options
echo "Available deployment options:"
echo "1) Quick Demo (localhost, portable)"
echo "2) Auto deployment with custom domain"
echo "3) Interactive deployment (full control)"
echo

read -p "Choose option (1-3): " choice

case $choice in
    1)
        echo "🎯 Starting quick demo deployment..."
        /app/scripts/deploy-auto.sh localhost portable
        ;;
    2)
        read -p "Enter your domain or IP: " domain
        echo "🎯 Starting auto deployment for $domain..."
        /app/scripts/deploy-auto.sh "$domain" portable
        ;;
    3)
        echo "🎯 Starting interactive deployment..."
        /app/scripts/deploy.sh
        ;;
    *)
        echo "❌ Invalid option"
        exit 1
        ;;
esac

echo
echo "✅ Deployment script completed!"
echo "Check the output above for next steps."