# Production image of Melody Studio. The deploy workflow builds it with Kamal.
#
# Builder image: https://hub.docker.com/r/hexpm/elixir/tags
# Runner image:  https://hub.docker.com/_/debian/tags
# Keep the Elixir and Erlang versions in step with mise.toml.

ARG ELIXIR_VERSION=1.19.7
ARG OTP_VERSION=28.5.0.8
ARG DEBIAN_VERSION=trixie-20261104-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# git fetches the GitHub dependencies of mix.lock; npm installs the assets packages.
RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git nodejs npm \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force \
  && mix local.rebar --force

ENV MIX_ENV="prod"

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy the compile-time config before the dependencies compile, so that a
# change to it compiles them again.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# assets.setup installs tailwind, esbuild and the npm packages of assets/.
COPY assets/package.json assets/package-lock.json assets/
RUN mix assets.setup

COPY priv priv
COPY lib lib
RUN mix compile

COPY assets assets
RUN mix assets.deploy

# A change to config/runtime.exs needs no new compile.
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

FROM ${RUNNER_IMAGE} AS final

RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates \
  && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

ENV MIX_ENV="prod"

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/melody_studio ./

USER nobody

EXPOSE 4000

# bin/start runs the database migrations, then starts the web server.
CMD ["/app/bin/start"]
