# Build stage
FROM elixir:1.18-otp-28 AS builder

# Install build dependencies (7zip for icon sync)
RUN apt-get update -y && apt-get install -y \
    build-essential \
    git \
    curl \
    p7zip-full \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set build ENV
ENV MIX_ENV=prod

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Create build directory
WORKDIR /app

# Copy mix files
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

# Copy config files so esbuild can read its configuration
COPY config config

# Install esbuild and tailwind
RUN mix esbuild.install
RUN mix tailwind.install

# Copy source code and assets
COPY lib lib
COPY assets assets
COPY priv priv

# Compile assets and application
RUN mix assets.deploy
RUN mix compile

# Build release
RUN mix release

# Runtime stage
FROM debian:trixie-slim

# Install runtime dependencies + 7zip/unzip for icon sync + resvg for PNG export
RUN apt-get update -y && apt-get install -y \
    libstdc++6 \
    openssl \
    libncurses6 \
    locales \
    ca-certificates \
    p7zip-full \
    unzip \
    resvg \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app

# Create non-root user
RUN groupadd -r pureadmin && useradd -r -g pureadmin pureadmin

# Create icons directory with correct permissions
RUN mkdir -p /app/.icons /app/.cache && chown -R pureadmin:pureadmin /app

# Copy the release from builder
COPY --from=builder --chown=pureadmin:pureadmin /app/_build/prod/rel/pure_admin_icons ./

# Switch to non-root user
USER pureadmin

# Expose Phoenix port
EXPOSE 8888

# Set environment to enable Phoenix server
ENV PHX_SERVER=true

# Start the release
CMD ["/app/bin/pure_admin_icons", "start"]
