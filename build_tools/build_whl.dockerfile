FROM python:3.6

ENV NODE_VERSION=20.19.3

# python:3.6 is EOL Debian bullseye; deb.debian.org/security.debian.org have
# aged the packages off entirely. archive.debian.org mirrors the main suite
# but never picked up a bullseye-security tree (its debian-security listing
# tops out at buster), so rewriting the host 404s. Use the pinned
# snapshot.debian.org URLs already provided below instead.
RUN sed -i \
    -e 's|^# deb http://snapshot.debian.org|deb http://snapshot.debian.org|g' \
    -e '/^deb http:\/\/deb.debian.org/d' \
    -e '/^deb http:\/\/security.debian.org/d' \
    /etc/apt/sources.list && \
    sed -i '/stretch-updates/d' /etc/apt/sources.list && \
    echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until

# install required packages
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl \
    software-properties-common \
    gettext \
    git \
    git-lfs \
    sqlite3 \
    python3-sphinx

RUN ln -s /usr/bin/python3.6 /usr/bin/python
# Upgrade pip. Otherwise pip cannot install c extension packages that are not
# for current platform
RUN pip install -U pip

# install nodejs, then enable Corepack so `pnpm` resolves to the version
# pinned by package.json's "packageManager" field. commit 75b44ba5a6
# ("chore: migrate from yarn to pnpm") updated the docker-whl Makefile
# target's cache volume to pnpm_cache but never touched this Dockerfile,
# which was still installing and invoking classic Yarn -- it errored
# because package.json no longer declares yarn as its packageManager.
RUN apt-get update && \
    curl -sSO https://deb.nodesource.com/node_20.x/pool/main/n/nodejs/nodejs_$NODE_VERSION-1nodesource1_amd64.deb && \
    dpkg -i ./nodejs_$NODE_VERSION-1nodesource1_amd64.deb && \
    rm nodejs_$NODE_VERSION-1nodesource1_amd64.deb && \
    corepack enable

RUN git lfs install &&\
    mkdir kolibri &&\
    mkdir pnpm_cache &&\
    mkdir cext_cache

WORKDIR /kolibri

# Python dependencies
COPY requirements/ requirements/
RUN echo '--- Installing Python dependencies' && \
    pip install -r requirements/build.txt

# Set pnpm store folder for easy binding during runtime (see -v pnpm_cache
# in the docker-whl Makefile target)
RUN pnpm config set store-dir /pnpm_cache

# Copy all files in this directory
COPY . .

CMD echo '--- Installing JS dependencies' && \
    pnpm install --frozen-lockfile && \
    echo '--- Making whl' && \
    make dist && \
    echo '--- Making pex' && \
    make pex
