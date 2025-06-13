FROM container-registry.oracle.com/os/oraclelinux:8

COPY rpms /tmp/

# Install vim-minimal, to allow editing main.js file easily during development, which will be removed later
RUN rpm -i /tmp/*.rpm && \
    mv /headlamp/backend/headlamp-server /headlamp/headlamp-server && \
    rmdir /headlamp/backend && \
    mkdir /headlamp/plugins && \
    mkdir /headlamp/static-plugins && \
    rm -rf /var/cache/yum/* /var/lib/rpm/* /tmp/*.rpm && \
    groupadd --system --gid 101 headlamp && \
    useradd --system --uid 100 -g headlamp --create-home --home-dir /home/headlamp headlamp && \
    chown -R headlamp:headlamp /headlamp

ENV HEADLAMP_CONFIG_TLS_CERT=/headlamp-cert/headlamp-ca.crt
ENV HEADLAMP_CONFIG_TLS_KEY=/headlamp-cert/headlamp-tls.key
USER headlamp

EXPOSE 4466

ENV HEADLAMP_STATIC_PLUGINS_DIR=/headlamp/static-plugins

ENTRYPOINT ["/headlamp/headlamp-server", "-html-static-dir", "/headlamp/frontend"]
