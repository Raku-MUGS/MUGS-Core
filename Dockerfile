ARG rakudo_version=2020.10
FROM rakudo-star:$rakudo_version
ARG rakudo_version

LABEL maintainer="Geoffrey Broadwell"
LABEL org.opencontainers.image.source=https://github.com/Raku-MUGS/MUGS-Core

RUN mkdir /home/raku \
 && chmod 700 /home/raku \
 && chown raku:raku /home/raku

WORKDIR /home/raku

# Partially adapted from cro-http-websocket Dockerfile, maintained by
# Jonathan Worthington <jonathan@edument.se>
ARG cro_version=0.8.4

RUN apt-get update \
 && apt-get -y --no-install-recommends install build-essential libsodium-dev libssl-dev \
 && zef update \
 && zef install zef --force \
 && zef update \
 && zef install OpenSSL --force \
 && zef install NativeHelpers::Array \
 && zef install Crypt::SodiumPasswordHash \
 && zef install Pluggable \
 && zef install --exclude="pq:ver<5>:from<native>" Red \
 && zef install 'Cro::Core:ver<'$cro_version'>' \
 && zef install 'Cro::TLS:ver<'$cro_version'>' \
 && zef install 'Cro::HTTP:ver<'$cro_version'>' \
 && zef install 'Cro::WebSocket:ver<'$cro_version'>' \
 && apt-get purge -y --auto-remove build-essential \
 && rm -rf /var/lib/apt/lists/*

COPY . /home/raku

RUN zef install --deps-only --exclude="pq:ver<5>:from<native>" . \
 && raku -c -Ilib bin/mugs-ws-server \
 && raku -c -Ilib bin/mugs-admin

USER raku:raku

RUN zef install .

ENV PATH=/home/raku/.raku/bin:$PATH

RUN mugs-admin create-universe

ENV MUGS_WEBSOCKET_HOST="0.0.0.0"
ENV MUGS_WEBSOCKET_PORT="10000"
EXPOSE 10000

ENTRYPOINT ["mugs-ws-server"]
