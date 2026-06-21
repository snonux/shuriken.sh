FROM alpine:latest

RUN apk add --no-cache \
        bash \
        coreutils \
        findutils \
        gawk \
        grep \
        imagemagick \
        rsync \
        sed \
        tar

RUN install -d /etc/default /usr/share/shuriken

COPY bin/shuriken /usr/bin/shuriken
COPY share/templates /usr/share/shuriken/templates
COPY assets/site /usr/share/shuriken/assets
COPY src/shuriken.default.conf /etc/default/shuriken

RUN chmod 0755 /usr/bin/shuriken

WORKDIR /work
VOLUME ["/work"]
ENTRYPOINT ["shuriken"]
CMD ["--generate"]
