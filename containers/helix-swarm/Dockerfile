# ========================================================================= #
# This docker files was built by the Perforce Software Swarm team to demo   #
# Swarm in a docker environment.                                            #
# ========================================================================= #

FROM perforce/helix-base-ubuntu20:latest
LABEL vendor="Perforce Software"
LABEL maintainer="Swarm Team (https://github.com/perforce/helix-swarm-docker)"

ARG SWARM_VER
ARG PKGV

RUN \
  [ ! -z $SWARM_VER ] && [ "$SWARM_VER" != "latest" ] && PKGV="=${SWARM_VER}~focal"; \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y -f helix-swarm$PKGV helix-swarm-optional$PKGV uuid


# P4D configuration
ENV P4D_PORT            "ssl:perforce:1666"
ENV P4D_SUPER           "super"
ENV P4D_SUPER_PASSWD    "HelixDockerBay94"

# Swarm configuration
ENV SWARM_USER          "swarm"
ENV SWARM_PASSWD        "HelixDockerBay94"
ENV SWARM_MAILHOST      "localhost"
ENV SWARM_HOST          "helix.swarm"
ENV SWARM_REDIS         "redis"
ENV P4D_GRACE           "30"
ENV SWARM_FORCE_EXT     "n"

COPY Version /opt/perforce/etc/Docker-Version

COPY setup/swarm-docker-setup.sh /opt/perforce/swarm/sbin/swarm-docker-setup.sh
COPY setup/helix-swarm.p4-extension /opt/perforce/swarm/p4-bin/helix-swarm.p4-extension
RUN  chmod 755 /opt/perforce/swarm/sbin/swarm-docker-setup.sh

# Simple Swarm configuration
RUN echo http://localhost >> /opt/perforce/etc/swarm-cron-hosts.conf
RUN rm -f /etc/apache2/sites-enabled/000*


ENV P4DGRACE=$P4DGRACE



CMD /opt/perforce/swarm/sbin/swarm-docker-setup.sh
