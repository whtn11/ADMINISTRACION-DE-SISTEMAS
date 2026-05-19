sudo cat > /etc/httpd/conf.d/security.conf << 'EOF'
# Ocultar version del servidor
ServerTokens Prod
ServerSignature Off

# Encabezados de seguridad
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
Header always set X-XSS-Protection "1; mode=block"
EOF

sudo systemctl restart httpd
sudo systemctl status httpd --no-pager