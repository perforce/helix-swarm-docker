# ========================================================================= #
# This docker files was built by the Perforce Software Swarm team to demo   #
# Swarm in a docker environment.                                            #
# ========================================================================= #

FROM ubuntu:focal
LABEL vendor="Perforce Software"
LABEL maintainer="Swarm Team (https://github.com/perforce/helix-swarm-docker)"

ARG P4REPO="deb http://package.perforce.com/apt/ubuntu focal release"
ARG SWARM_VER
ARG PKGV

RUN \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y wget curl unzip vim gnupg zip lsb-release && \
  wget -qO - https://package.perforce.com/perforce.pubkey | apt-key add - && \
  echo "${P4REPO}\n" > /etc/apt/sources.list.d/perforce.list

RUN \
  apt-get update && \
  apt-get upgrade -y && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y -f helix-cli

RUN \
  [ ! -z $SWARM_VER ] && [ "$SWARM_VER" != "latest" ] && PKGV="=${SWARM_VER}~focal"; \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y -f helix-swarm$PKGV helix-swarm-optional$PKGV uuid


# P4D configuration
ENV P4D_PORT            "ssl:perforce:1666"
ENV P4D_SUPER           "super"
ENV P4D_SUPER_PASSWD    ""

# Swarm configuration
ENV SWARM_USER          "swarm"
ENV SWARM_PASSWD        ""
ENV SWARM_MAILHOST      "localhost"
ENV SWARM_HOST          "helix.swarm"
ENV SWARM_REDIS         "redis"
ENV P4D_GRACE           "30"
ENV SWARM_FORCE_EXT     "n"

COPY Version /opt/perforce/etc/Docker-Version

COPY setup/swarm-docker-setup.sh /opt/perforce/swarm/sbin/swarm-docker-setup.sh
RUN  chmod 755 /opt/perforce/swarm/sbin/swarm-docker-setup.sh

# Simple Swarm configuration
RUN echo http://localhost >> /opt/perforce/etc/swarm-cron-hosts.conf
RUN rm -f /etc/apache2/sites-enabled/000*


ENV P4DGRACE=$P4DGRACE



CMD /opt/perforce/swarm/sbin/swarm-docker-setup.sh
