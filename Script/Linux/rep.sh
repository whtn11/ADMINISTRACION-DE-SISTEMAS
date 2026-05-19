sudo cp /srv/ftp/juan/general/general/cert.pem /srv/ftp/juan/general/apache_cert.pem
sudo cp /srv/ftp/juan/general/general/privkey.pem /srv/ftp/juan/general/apache_privkey.pem 2>/dev/null || sudo cp /srv/ftp/juan/general/general/privatekey.pem /srv/ftp/juan/general/apache_privkey.pem
sudo cp /srv/ftp/juan/general/general/Nginx/cert.pem /srv/ftp/juan/general/nginx_cert.pem
sudo cp /srv/ftp/juan/general/general/Nginx/privkey.pem /srv/ftp/juan/general/nginx_privkey.pem 2>/dev/null || sudo cp /srv/ftp/juan/general/general/Nginx/privatekey.pem /srv/ftp/juan/general/nginx_privkey.pem