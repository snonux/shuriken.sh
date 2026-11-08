# Pinned base: Alpine 3.24.4 (released 2026-11-05), multi-arch index digest.
# A floating alpine:latest made every rebuild a different, unrecorded base.
# Bump tag and digest together when Alpine publishes a new patch release
# (skopeo inspect docker://docker.io/library/alpine:<version>).
FROM alpine:3.24.4@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf

# apk upgrade pulls the v3.24 security fixes published after the base image
# was built. Packages are not pinned with `pkg=version`: Alpine drops
# superseded versions from its repositories, so exact pins break any later
# rebuild. The image tag is immutable instead (conf
# f3s/shuriken/docker-image/Justfile): it freezes the resolved package set,
# and every refresh is a NEW tag whose package list is recorded at build time.
RUN apk upgrade --no-cache && apk add --no-cache \
        bash \
        coreutils \
        findutils \
        gawk \
        grep \
        imagemagick \
        imagemagick-jpeg \
        imagemagick-webp \
        openssh-client \
        rsync \
        sed \
        tar

RUN install -d /etc/default /usr/share/shuriken

COPY bin/shuriken /usr/bin/shuriken
COPY share/templates /usr/share/shuriken/templates
COPY assets/site /usr/share/shuriken/assets
COPY src/shuriken.default.conf /etc/default/shuriken
COPY docker/entrypoint.sh /usr/local/bin/shuriken-entrypoint
COPY docker/imagemagick-policy.xml /etc/ImageMagick-7/policy.xml

RUN chmod 0755 /usr/bin/shuriken /usr/local/bin/shuriken-entrypoint

# /configs holds per-site shuriken.conf files (mounted via ConfigMap in K8s);
# /data is the shared NFS tree (INCOMING_DIR/DIST_DIR point at subpaths of it).
# Both are over-mounted at runtime, so no VOLUME directive (anonymous volumes
# would shadow nothing useful here and complicate local runs).
RUN install -d /configs /data
WORKDIR /data

ENTRYPOINT ["shuriken-entrypoint"]
