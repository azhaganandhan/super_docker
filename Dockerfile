FROM bitwalker/alpine-elixir:1.9.0 AS phx-builder

MAINTAINER Shankar Dhanasekaran <shankardevy@gmail.com>

# Important!  Update this no-op ENV variable when this Dockerfile
# is updated with the current date. It will force refresh of all
# of the base images and things like `apt-get update` won't be using
# old cached versions when the Dockerfile is built.
ENV REFRESHED_AT=2019-07-31

# Install NPM
RUN \
    mkdir -p /opt/app && \
    chmod -R 777 /opt/app && \
    apk update && \
    apk --no-cache --update add \
      make \
      g++ \
      wget \
      curl \
      inotify-tools \
      nodejs \
      nodejs-npm && \
    npm install npm -g --no-progress && \
    update-ca-certificates --fresh && \
    rm -rf /var/cache/apk/*

# Add local node module binaries to PATH
ENV PATH=./node_modules/.bin:$PATH

# Ensure latest versions of Hex/Rebar are installed on build
ONBUILD RUN mix do local.hex --force, local.rebar --force

WORKDIR /opt/app

# Set exposed ports
ENV MIX_ENV=prod

# Cache elixir deps
ADD mix.exs mix.lock ./
RUN mix do deps.get, deps.compile

# Same with npm deps
ADD assets/package.json assets/
RUN cd assets && \
    npm install

ADD . .

# Run frontend build, compile, and digest assets
RUN cd assets/ && \
    npm run deploy && \
    cd - && \
    mix do compile, phx.digest && \
    mix release --force

FROM alpine:3.10.1

EXPOSE 4000
ENV PORT=4000 MIX_ENV=prod

ENV LANG=en_US.UTF-8 \
    HOME=/opt/app/ \
    # Set this so that CTRL+G works properly
    TERM=xterm \
    PATH=/opt/app/bin:/usr/local/bin:${PATH}

RUN \
    # Create default user and home directory, set owner to default
    adduser -s /bin/sh -u 1001 -G root -h "${HOME}" -S -D default && \
    chown -R 1001:0 "${HOME}" && \
    # Add tagged repos as well as the edge repo so that we can selectively install edge packages
    echo "@main http://dl-cdn.alpinelinux.org/alpine/v3.10/main" >> /etc/apk/repositories && \
    echo "@community http://dl-cdn.alpinelinux.org/alpine/v3.10/community" >> /etc/apk/repositories && \
    echo "@edge http://dl-cdn.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories && \
    # Upgrade Alpine and base packages
    apk --no-cache --update --available upgrade && \
    # Install bash and Erlang/OTP deps
    apk add --no-cache --update pcre@edge && \
    apk add --no-cache --update \
      bash \
      ca-certificates \
      openssl \
      ncurses \
      unixodbc \
      zlib && \
    # Update ca certificates
    update-ca-certificates --fresh
