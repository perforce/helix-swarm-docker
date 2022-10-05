# ========================================================================= #
# This docker files was built by the Perforce Software Swarm team to demo   #
# Swarm in a docker environment.                                            #
# ========================================================================= #

FROM ubuntu:focal AS helix-swarm
LABEL vendor="Perforce Software"
LABEL maintainer="Swarm Team (https://github.com/perforce/helix-swarm-docker)"

# P4_PUBLIC_REPO should not be overridden
ARG P4_PUBLIC_REPO="deb http://package.perforce.com/apt/ubuntu focal release"
# P4REPO is designed to be overridden
ARG P4REPO="deb http://package.perforce.com/apt/ubuntu focal release"
ARG SWARM_VER
ARG PKGV

RUN \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt dist-upgrade -y && \
  DEBIAN_FRONTEND=noninteractive apt install -y wget curl unzip vim gnupg zip lsb-release iputils-ping && \
  wget -qO - https://package.perforce.com/perforce.pubkey | apt-key add - && \
  echo "${P4_PUBLIC_REPO}\n" > /etc/apt/sources.list.d/perforce.list

RUN \
  apt-get update && \
  apt-get upgrade -y && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y -f helix-cli

# Switch to the package repository we want to get Swarm from, which could be a development build.
RUN \
  echo "${P4REPO}\n" > /etc/apt/sources.list.d/perforce.list

RUN \
  [ ! -z $SWARM_VER ] && [ "$SWARM_VER" != "latest" ] && PKGV="=${SWARM_VER}~focal"; \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y -f helix-swarm$PKGV helix-swarm-optional$PKGV uuid


# P4D configuration
ENV P4D_PORT              "ssl:perforce:1666"
ENV P4D_SUPER             "super"
ENV P4D_SUPER_PASSWD      ""

# Swarm configuration
ENV SWARM_USER            "swarm"
ENV SWARM_PASSWD          ""
ENV SWARM_MAILHOST        "localhost"
ENV SWARM_HOST            "helix-swarm"
ENV SWARM_REDIS           "helix-redis"
ENV SWARM_REDIS_PORT      "7379"
ENV SWARM_REDIS_PASSWD    ""
ENV SWARM_REDIS_NAMESPACE ""
ENV P4D_GRACE             "30"
ENV SWARM_FORCE_EXT       "n"

COPY Version /opt/perforce/etc/Docker-Version

COPY setup/swarm-docker-setup.sh /opt/perforce/swarm/sbin/swarm-docker-setup.sh
RUN  chmod 755 /opt/perforce/swarm/sbin/swarm-docker-setup.sh

# Simple Swarm configuration
RUN echo http://localhost:80 > /opt/perforce/etc/swarm-cron-hosts.conf && \
    rm -f /etc/apache2/sites-enabled/* && \
    echo "#${P4REPO}" > /etc/apt/sources.list.d/perforce.list && \
    echo "${P4_PUBLIC_REPO}" >> /etc/apt/sources.list.d/perforce.list


ENV P4DGRACE=$P4DGRACE



CMD /opt/perforce/swarm/sbin/swarm-docker-setup.sh
