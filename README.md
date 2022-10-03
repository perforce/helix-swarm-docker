[![Support](https://img.shields.io/badge/Support-Official-green.svg)](mailto:support@perforce.com)

# Helix Swarm Docker Container

Welcome to the Perforce Software Swarm Docker container. This container
is built for public use and is for customers that want to run Swarm in either
test or production environments.

There is a Makefile for building the images on Linux, though it is possible
to do this manually using a simple docker command.

This documentation assumes that you have at least a basic knowledge of how
to use Docker. For a more complete guide, please see the Helix Swarm
documentation at https://www.perforce.com/manuals/swarm/Content/Swarm/home-swarm.html

---

## Helix Swarm Images

Helix Swarm images are available on docker hub as `perforce/helix-swarm`:

https://hub.docker.com/repository/docker/perforce/helix-swarm

#### Tags

The following tagged images are available:

* perforce/helix-swarm:latest
* perforce/helix-swarm:2022.2

Versioned tags will be updated if there is a patch release for that version.
The latest tag will always be the very latest patch for the latest version.

### Helix Swarm Image Source

The source code for these images can be found at:

https://github.com/perforce/helix-swarm-docker


# Getting Started

## Prerequisites

* A running P4D instance, to which you have super access.
* An environment to run Docker in.
* Internet access.
* A knowledge of how to use Docker.

There are many different ways that Docker containers can be configured and
managed. What is show below is meant merely as an example. If you use
Kubernates, Docker Compose, Podman etc then these should work as well.
How to setup and configure these is left as an exercise to the reader.

The examples below use bind mounts, but there is no reason that volume
mounts can't be used instead.

## Running the container

*The following will configure a fresh installation of Swarm against a Helix
Core Server. It is best for first time setup.*

First, create a .env file with something like the following content:

```
P4D_PORT=ssl:myperforce:1666
P4D_SUPER=super
P4D_SUPER_PASSWD=HelixDockerBay94
SWARM_USER=swarm
SWARM_PASSWD=HelixDockerBay94

SWARM_HOST=mymachine

SWARM_REDIS=helix-redis
SWARM_REDIS_PORT=7379

# If set to 'y', then extensions will be installed even if they already
# exist, overwriting existing configuration.
SWARM_FORCE_EXT=y
```

The `P4D_PORT` must be set to the port of your P4D instance. It must be
reachable from the docker image. The `P4_SUPER_PASSWD` and `P4D_SUPER` 
variables must be set equal to a super user on your P4D.

The `SWARM_USER` will be created if it doesn't exist, and the `SWARM_PASSWD`
must be set correctly. This needs to be an admin or super user.

`SWARM_HOST` must be the hostname that will be used by the docker container.
This needs to be reachable from the P4D server.

**IMPORTANT**: The SWARM_HOST is used to configure the extensions, so it's
vital that P4D can use this to call back to the hostname given here.

`SWARM_REDIS` and `SWARM_REDIS_PORT` need to be set to allow Swarm to connect
to a Redis server to use as a cache. This can be an existing server, or you
can use the redis-server docker container that is available on DockerHub.

This configuration file will then be used by the Docker container to configure
itself. The very simplest command to get things running would be:

```
docker run -d --name helix-swarm --network-alias helix-swarm \
    --env-file .env -p 80:80 perforce/helix-swarm
```

The following docker commands can be used to set up a local private network,
and pulls down both Redis and Helix Swarm to run in that network. This allows
the Redis server to be private to Swarm, so it can't be accessed from the
outside. Note that in this example, you don't need to set any of the
`SWARM_REDIS` variables in the .env, since the defaults will work.

```
docker network create helix
docker run -d --name helix-redis --network helix --network-alias helix-redis \
    redis redis-server --protected-mode no --port 7379
    
docker run -d --name helix-swarm --network helix --network-alias helix-swarm \
    --env-file .env -p 80:80 perforce/helix-swarm
```

### Persisting Containers (Production)

A full production environment requires that Swarm and Redis data can be
persisted beyond the lifetime of the containers. This can be done through
the use of bind mounts when starting the docker containers.

In order to preserve data, the `/opt/perforce/swarm/data` directory should 
be mounted outside of the container using a bind or volume mount.

It is also possible to configure Redis to write its cache to disc, and to
preserve it between restarts.

```
docker network create helix

mkdir -p storage/redis-data
docker run -d --name helix-redis --network helix --network-alias helix-redis \
    -v $PWD/storage/redis-data:/data redis \
    redis-server --protected-mode no --port 7379 --appendonly yes    

mkdir -p storage/swarm-data
docker run -d --name helix-swarm --network helix --network-alias helix-swarm \
    -p 80:80 -v $PWD/storage/swarm-data:/opt/perforce/swarm/data \
    --env-file .env perforce/helix-swarm
```

This configuration preserves the Swarm configuration and Redis cache data
outside of the container. Swarm log files, the worker queue, tokens and
workspaces will also be preserved.

### Restarting Docker

When the container starts, if the `/opt/perforce/swarm/data/config.php` file
already exists then most of the configuration steps are skipped. This allows
the container to be restarted without having to reconfigure the system each
time.

This has the side effect that the `.env` file is no longer needed. After the
docker container has been deleted, it can be recreated and restarted with
the following.

```
docker run -d --name helix-swarm --network helix --network-alias helix-swarm \
    -p 80:80 -v $PWD/storage/swarm-data:/opt/perforce/swarm/data \
    perforce/helix-swarm
```

Note that the swarm-data directory will have had its file permissions re-written
by the container, so you will need root access to look at it.

#### The docker directory

If it does not already exist, a `/opt/perforce/swarm/data/docker` directory
will be created on start. Into this is copied the Apache site configuration
and several Swarm configuration files that don't live within the data
directory.

These are then linked to from their usual locations. This allows users to
make modifications to these files outside of the container. Any changes will
be preserved between restarts.

* /etc/apache2/sites-available -> docker/sites-available [directory]
* /opt/perforce/etc/swarm-cron-hosts.conf -> docker/swarm-cron-hosts.conf
* /opt/perforce/swarm/public/custom -> docker/custom [directory]

The Swarm version file, and the container version file, are also copied
into this directory.

The entire `/etc/apache2/sites-available` directory is soft linked to the
`/opt/perforce/swarm/data/docker/sites-available` directory, and any .conf
files in there have `a2ensite` run against them.

This allows any number of Apache site configurations to be automatically
run. Normally there will be a single perforce-swarm-site.conf file in
here. If you need to also enable HTTPS though, then there could be a need
for a second virtual host.

Any modifications to these site config files will be preserved between
restarts of Docker.

Note that if `docker/sites-available` exists and is a file rather than
a directory, then no soft linking will be performed. This allows the
entire apache directory to be mounted outside of the container.

#### Further configuration of the config.php

With the `config.php` mapped outside the container, then it is easy to
modify this with any other configuration required. Just remember to clear the
cache afterwards to get Swarm to pick up the changes.

### Migration to Docker

If you are looking to replace an existing Swarm server with Docker, then it's
possible to re-use the existing config.php configuration file. You can also
configure Swarm to use a different Redis instance. For example, you could
continue to use the existing Redis.

If you are moving from an existing Swarm setup to a Dockerised one, then
you can copy the `data` directory to a suitable location for the Docker
container to use. This will contain all the necessary configuration which
the containerized Swarm will then use.

- Create a `./storage` directory
- Copy the contents of the old `data` directory to `./storage/swarm-data`
- Ensure configuration for network connections in the `config.php` are
correct. For example, Swarm hostname, Redis, Email, Jira etc. The docker
container needs to be able to reach all of these.
- Ensure there is a suitable site configuration file for Apache. You can
place one at `swarm-data/etc/perforce-swarm-site.conf`, and it will be
copied into place in the container when it starts.

```
docker network create helix

mkdir -p storage/redis-data
docker run -d --name helix-redis --network helix --network-alias helix-redis \
    -v $PWD/storage/redis-data:/data redis \
    redis-server --protected-mode no --port 7379 --appendonly yes
    

mkdir -p storage/swarm-data
docker run -d --name helix-swarm --network helix --network-alias helix-swarm \
    -p 80:80 -v $PWD/storage/swarm-data:/opt/perforce/swarm/data \
    perforce/helix-swarm
```

A `docker` directory will be created inside the `data` directory. This will
contain a number of configuration files which are linked to from within the
Docker container.

On first configuration, these files are moved into here unless they already
exist.

* perforce-swarm-site.conf - Apache site configuration file
* swarm-cron-hosts.conf - List of Cron worker configuration
* custom - Directory which contains any custom configurations for Swarm

These can be edited from outside of Docker, and changes will be immediately
reflected within the container since the 'original' locations are soft links
to them.


#### Be Aware

If you are moving from a Swarm installation on a machine, to a Docker
installation on the same machine, then you need to be aware of the following
possible issues.

* The login ticket for the Swarm user will still need to change, unless you
are using a host unlocked ticket.
* Any cron jobs running on the host machine could interfere with the Docker
instance. If they were previously calling localhost:80, and the Docker
container is available on localhost:80, they will still be creating workers.
It is recommended that host cron jobs are stopped and that you only rely on
the ones in the container.
* The Redis configuration will need to change since that will no longer be
local to the Apache instance. You should use either a private network or
set passwords to be used.

It is possible to mount the host's /opt/perforce/swarm/data directly into
the Docker container. This could be confusing though, so we recommend using
a different mount point.

## Advanced Options

There are a number of options that can be placed into the .env file in order
to modify the configuration of the Helix Swarm docker image. These are listed
below.

Note that most of these are ignored if there is a config.php file already in
place. `SWARM_HOST` will be used to configure Apache unless a site config
file is found.

| Config             | Default           | Description              |
| :---               | :---              | :---                     |
| P4D_SUPER          | super             | Name of the super user   |
| P4D_SUPER_PASSWD   | *no default*      | Super user password      |
| P4D_PORT           | ssl:perforce:1666 | Port for the P4D server  |
| SWARM_USER         | swarm             | Name of the swarm user   |
| SWARM_PASSWD       | *no default*      | Swarm user password      |
| SWARM_MAILHOST     | localhost         | Mail server address      |
| SWARM_HOST         | helix-swarm       | Hostname of Swarm server |
| SWARM_FORCE_EXT    | n                 | Set to 'y' to overwrite extensions |
| SWARM_REDIS        | helix-redis       | Hostname of Redis server |
| SWARM_REDIS_PORT   | 7379              | Port for Redis server    |
| SWARM_REDIS_PASSWD |                   | Password for Redis server |
| SWARM_REDIS_NAMESPACE |                | Redis namespace          |


## Further Configuration

Once Swarm has been setup, you are free to make any changes to the config.php
that you need to. More complicated Email configuration for example requires
manual changes to the config.php, and can't be managed from the environent
variables passed into Docker.

Similar restrictions apply to Jira integrations, or support for Multi-P4D.

If you want more complicated configurations, it is highly recommended that
the data directory is mounted externally, then any configurations will be
preserved.

### Apache Configurations

By default, three modules are enabled for Apache - rewrite, ssl and remoteip.
The ssl module is only needed it you want to run HTTPS from within the container.
If you are using SSL, then you will also need a location to place the SSL
key and certificate file. There are two options for this.

The first is to place them within the data/docker directory, and reference
to them there from the Apache site configuration file.

The second option is to place them elsewhere and mount that location
externally. This is the more secure option since the private key file
will be outside of the Swarm file area.

A third option is to manage SSL externally to the container. The entire
container could be fronted by another web server which acts as a proxy onto 
the container. This external server can then provide any HTTPS functionality
that is required.

#### Apache Proxy

If the Docker container is being fronted by another web server, then you
may run into problems with Helix tickets unless they are host unlocked.
Normally Apache forwards the IP address of the client to Swarm. This allows
a ticket that has been obtained on a client machine to work with Swarm,
even though Swarm is a different machine.

If Swarm is behind a web proxy (such as a second Apache server, running SSL),
then the IP address of the client is lost. In this situation, host unlocked
tickets must be used (obtained with `p4 login -ap`).

Alternatively, the remoteip module can be used to allow the container
Apache to trust the proxy, enabling the forwarding of client IPs.

Add these lines into the perforce-swarm-site.conf, at the same level
as the DocumentRoot.

```
RemoteIPHeader X-Forwarded-For
RemoteIPInternalProxy 172.19.0.1/24
```

The RemoteIPInternalProxy should be the IP address of the host, as seen
seen by the container.

## Make

There is a Make file present which abstracts some of the commands that can
be run. If you are on a Linux system with suitable build tools, then this
might be useful. However, it is probably more useful for development and
testing rather than production deployments.

The Makefile sets some default parameters:

```
REPO    := perforce
IMAGE   := helix-swarm-development
TAG     := DEV-BUILD
ARGS    := 
NAME    := helix-swarm
```

These can be overridden by a build.mk file.

#### make build

Build the docker file locally. The `ARGS` variable can be used to pass extra
parameters to the build.

#### make build-clean

Build the docker file locally, without using the docker cache. This ensures
everything that is built is up to date.

#### make push

Push the built image up to Docker Hub. You will need to set the REPO and IMAGE
variables to a repository that you have write access to.

#### make clean

Remove any running docker containers.

#### make run

Run a Redis and Helix Swarm container in their own network, using the local
.env file for configuration.

#### make bash

Open a shell onto the running Helix Swarm container.

#### make log

Display the contents of the docker log file.

#### make tail

Tail the contents of the docker log file.



---

 @copyright   2022 Perforce Software. All rights reserved.

---
 @license     Please see LICENSE in the top-level folder of this distribution.



