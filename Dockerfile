ARG rakudo_version=latest
FROM rakudo-zef:$rakudo_version
ARG rakudo_version

LABEL maintainer="Geoffrey Broadwell"
LABEL org.opencontainers.image.source=https://github.com/Raku-MUGS/MUGS-Core

# Partially adapted from cro-http-websocket Dockerfile, maintained by
# Jonathan Worthington <jonathan@edument.se>
ARG cro_version=0.8.9
ARG cro_cbor_version=0.0.5

USER root:root

RUN apt-get update \
 && apt-get -y --no-install-recommends install \
    build-essential libsodium-dev libsqlite3-dev libssl-dev \
 && zef update \
 && zef install OpenSSL --force \
 && zef install NativeHelpers::Array \
 && zef install Crypt::SodiumPasswordHash \
 && zef install Pluggable \
 && zef install --/test --exclude="pq:ver<5>:from<native>" Red \
 && zef install 'Cro::Core:ver<'$cro_version'>' \
 && zef install 'Cro::TLS:ver<'$cro_version'>' \
 && zef install 'Cro::HTTP:ver<'$cro_version'>' \
 && zef install 'Cro::WebSocket:ver<'$cro_version'>' \
 && zef install --/test 'Cro::CBOR:ver<'$cro_cbor_version'>' \
 && rm -rf /root/.zef /tmp/.zef /tmp/* \
 && apt-get purge -y --auto-remove build-essential \
 && rm -rf /var/lib/apt/lists/*

USER raku:raku

WORKDIR /home/raku/MUGS/MUGS-Core
COPY . .

RUN zef install --deps-only --exclude="pq:ver<5>:from<native>" . \
 && zef install --/test . \
 && mugs-admin create-universe \
 && rm -rf /home/raku/.zef /tmp/.zef

ENV MUGS_WEBSOCKET_HOST="0.0.0.0"
ENV MUGS_WEBSOCKET_PORT="10000"
EXPOSE 10000

CMD ["mugs-ws-server"]
