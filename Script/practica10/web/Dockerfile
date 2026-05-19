FROM httpd:alpine

# Eliminar firma del servidor
RUN sed -i 's/^ServerTokens .*/ServerTokens Prod/' /usr/local/apache2/conf/httpd.conf && \
    sed -i 's/^ServerSignature .*/ServerSignature Off/' /usr/local/apache2/conf/httpd.conf

# Crear usuario no administrativo
RUN addgroup -S webgroup && adduser -S webuser -G webgroup

# Copiar archivos del sitio
COPY . /usr/local/apache2/htdocs/

# Permisos
RUN chown -R webuser:webgroup /usr/local/apache2/htdocs/

EXPOSE 80