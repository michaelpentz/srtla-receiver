# Build arguments that need to be available globally
ARG SRTLA_BRANCH=main
ARG SLS_TAG=latest

# Builder Stage
FROM alpine:3.20 AS builder

# Redeclare build argument for this stage
ARG SRTLA_BRANCH

ENV LD_LIBRARY_PATH=/lib:/usr/lib:/usr/local/lib64
WORKDIR /tmp

# Install required packages
RUN apk update \
    && apk add --no-cache linux-headers alpine-sdk cmake tcl openssl-dev zlib-dev spdlog spdlog-dev libmaxminddb-dev \
    && rm -rf /var/cache/apk/*

# Clone and build SRTla (CACHEBUST forces fresh clone when srtla repo changes)
ARG CACHEBUST=1
RUN git clone -b ${SRTLA_BRANCH} https://github.com/michaelpentz/srtla.git srtla \
    && cd srtla \
    && git submodule update --init --recursive \
    && cmake . \
    && make -j${nproc}

# SLS Stage
# Redeclare build argument for this stage
ARG SLS_TAG
FROM ghcr.io/openirl/srt-live-server:${SLS_TAG} AS sls-stage

# Final Stage
FROM alpine:3.20

ENV LD_LIBRARY_PATH=/lib:/usr/lib:/usr/local/lib64

RUN apk update \
    && apk add --no-cache openssl libstdc++ supervisor coreutils spdlog perl libmaxminddb \
    && rm -rf /var/cache/apk/*

# Create service users for security isolation
RUN adduser -D -u 3001 -s /bin/sh sls \
    && adduser -D -u 3002 -s /bin/sh srtla

# Copy binaries from the builder stage
COPY --from=builder /tmp/srtla/srtla_rec /usr/local/bin

# Copy binaries from the srt-live-server
COPY --from=sls-stage /usr/local/bin/* /usr/local/bin
COPY --from=sls-stage /usr/local/lib/libsrt* /usr/local/lib

# Copy binary files from the repo
COPY --chmod=755 bin/logprefix /bin/logprefix

# GeoIP ASN database is volume-mounted from the host AMI at runtime
# (see docker-compose volume mount for /usr/share/GeoIP/ipinfo_lite.mmdb)

# Copy configuration files from the srt-live-server
COPY --from=sls-stage /etc/sls/sls.conf /etc/sls/sls.conf

# Copy configuration files from the repo
COPY conf/supervisord.conf /etc/supervisord.conf

# Expose ports
EXPOSE 5000/udp 4000/udp 4001/udp 8080/tcp 5080/tcp

# Start supervisor
CMD ["/usr/bin/supervisord", "--nodaemon", "--configuration", "/etc/supervisord.conf"]