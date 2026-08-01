FROM alpine:latest

RUN apk add --no-cache \
        bash \
        coreutils \
        findutils \
        gawk \
        grep \
        imagemagick \
        imagemagick-jpeg \
        imagemagick-webp \
        rsync \
        sed \
        tar

RUN install -d /etc/default /usr/share/shuriken

COPY bin/shuriken /usr/bin/shuriken
COPY share/templates /usr/share/shuriken/templates
COPY assets/site /usr/share/shuriken/assets
COPY src/shuriken.default.conf /etc/default/shuriken
COPY docker/entrypoint.sh /usr/local/bin/shuriken-entrypoint

RUN chmod 0755 /usr/bin/shuriken /usr/local/bin/shuriken-entrypoint

# /configs holds per-site shuriken.conf files (mounted via ConfigMap in K8s);
# /data is the shared NFS tree (INCOMING_DIR/DIST_DIR point at subpaths of it).
# Both are over-mounted at runtime, so no VOLUME directive (anonymous volumes
# would shadow nothing useful here and complicate local runs).
RUN install -d /configs /data
WORKDIR /data

ENTRYPOINT ["shuriken-entrypoint"]
