![Support](https://img.shields.io/badge/Support-Community-yellow.svg)

# Helix Swarm Docker Environment

Welcome to the Perforce Software Swarm Docker environment. This environment
is built for public use and is for customers that want to test Swarm in a 
pre-setup environment.

This Docker environment is built using Helix Swarm 2021.2, Docker 20.10.5,
and docker-compose 1.28.4. It is recommended that at least these versions
of the tools are used.

This is a **TECHNICAL PREVIEW** and not tested for production use. It's
purpose is to gain feedback from our customers so that we can determine
the use cases to which it would be put, and tweak the configuration in
order to improve its usability.

This does mean that there is a chance the configuration will change
dramatically over the next few releases, and we do not guarantee backwards
compatibility.

There are two use cases that are supported, starting up Swarm against a clean
P4D system (one which has not had Swarm configured against it), and starting
Swarm using an existing configuration. These are both described below.

Note that the provided Makefile is for use on Linux, and may work on Mac.
These images have not been tested on Windows.

---

## What is Docker?

Docker is a tool designed to make it easier to create, deploy, and run 
applications by using containers. If you want to find out more about
what these containers are, try the documentation at docker.com:

https://www.docker.com/resources/what-container

### Prerequisites for this Docker environment

* Internet access
* Docker-compose

By default, the following port must be free to enable connection to the 
containers from the outside world or local machine.

* 80 (Swarm HTTP)

These can be changed if you don't want to use these default ports. By
default, Swarm is not configured to use HTTPS.

### Containers

These containers are setup to be used with Docker Compose, however it should
be possible to run them without the use of Docker Compose. In this first 
technical preview this hasn't been tested.

#### helix.base

Based on a Ubuntu 20.04 container, sets up the Perforce package repository
and installs the Helix command line client. Used as a base by helix-swarm.

#### helix.swarm

Contains the Swarm and Apache server, can be configured to talk to an existing
P4D instance.

It exposes port 80 by default for access externally. If you want to use HTTPS,
then manual configuration of the container is required.

#### helix.redis

Based on the standard redis container, used by helix.swarm by default as the
local redis cache. Note that this version of redis uses the standard default
port of 6379, whereas the one shipped with Swarm uses a default port of 7379.
This means we need to specify the port on the command line when the server
starts.

### Data Storage

Since Docker containers can be temporary, both the Swarm and Redis containers
store their data outside of the containers on the local file system in the
`storage` directory.

## New Swarm

The simplest configuration is to run up a new Swarm against an existing P4D
server. If Swarm has been used against this P4D (Helix Server) in the past, 
then some parts of the configuration may need to be manually done.

We recommend a Unicode enabled P4D for use with Swarm. If P4D is running on
Microsoft Windows, then you will also need to configure the triggers.

First configure the .env file to be suitable for your environment. An 
`env.dist` file is provided which has some defaults, which can be copied to
`.env`, or you can manually create the file.

The following variables are used from the environment:

| Config           | Default           | Description              |
| :---             | :---              | :---                     |
| P4D_SUPER        | super             | Name of the super user   |
| P4D_SUPER_PASSWD | HelixDockerBay94  | Super user password      |
| P4D_PORT         | ssl:perforce:1666 | Port for the P4D server  |
| SWARM_USER       | swarm             | Name of the swarm user   |
| SWARM_PASSWD     | HelixDockerBay94  | Swarm user password      |
| SWARM_MAILHOST   | localhost         | Mail server address      |
| SWARM_HOST       | helix.swarm       | Hostname of Swarm server |
| PUBLIC_HTTP      | 80                | Port Swarm is exposed on |
| SWARM_FORCE_EXT  | n                 | Set to 'y' to overwrite extensions |
| SWARM_VER        | latest            | Only 'latest' supported  |

Once these have been set, then the Docker containers can be built and
started with the following commands:

```
docker-compose build
docker-compose up -d
```

Or alternatively, you can use the Makefile to do the same:

```
make clean build up
```

This will clean down the system, build the base Docker images, then
bring them up. You can then use `make log` to see how the configuration
is progressing.

### Configuration steps

If there is an existing `config.php` file in the data directory, then
configuration will be skipped, and we assume that Swarm is already
configured.

The following steps are followed when Swarm is configured:

* Check for a running P4D server against {P4D_PORT}.
* Check that we can log into it with {P4D_SUPER} and {P4D_SUPER_PASSWD}.
* Check to see that there is a {SWARM_USER}. If there is, we don't create
  one, otherwise we will create one with the given {SWARM_PASSWD}


Once the Swarm container is up and running, and Swarm is working, the
only entry in the .env file that is still needed is `PUBLIC_HTTP`. At the
very least, you may want to remove the passwords from this file.

If the P4D server is a Linux server, and there are no Swarm triggers and
no Swarm extensions are configured on it, then Swarm extensions will be 
automatically installed.

Server side extensions are a new feature of P4D which are more efficient
than triggers, and don't require an external language environment such
as Perl. They are not currently supported on Windows versions of P4D.

If the SWARM_FORCE_EXT environment variable is set to "y", then any existing
Swarm extensions will be removed, and new ones always installed.

You can check to see what extensions are already installed by running the
following command as a super user or admin:

p4 extension --list --type extensions


### Managing the Container

You can stop and start the container with:

```
docker-compose stop
docker-compose up -d
```

Alternatively, using the included Makefile:

```
make stop
make up
```

You can also gain access to a running Swarm container with `make bash`

Since the container will not perform any reconfiguration if the config.php
file already exists, if a new container is started after the previous has
been stopped or even deleted then it will simply pick up the previous
configuration and continue from where it left off.

The exception is that if there is a perforce-swarm-site.conf in the external
data/etc directory, then this will be copied into place for use by the
running Apache server if it isn't there already.

  

## Migrate Swarm

If you already have a Swarm installation, then you may want to just move
it into Docker. We don't recommend this for production servers at the moment
(by this, we mean that we haven't yet performed extensive testing of Swarm
in Docker, and we don't have built in support for HTTPS).

* Copy the contents of the `data` directory into the `swarm-data` directory.
* Start the docker containers

Swarm will automatically pick up the `config.php` and use it 'as is'. No 
changes will be made to it. This may mean that you need to configure the Redis
configuration if you want to use the Dockerised Redis server. In which case
point the Swarm redis configuration at helix.redis:

```
    'redis' => [
        'options' => [
            'server' => [
                'host' => 'helix.redis',
            ],
        ],
    ],
```

You may also need to change the host name in the env file.

If you have triggers already installed on your P4D, then you will need to 
make sure that they are configured to point at the new Swarm location.

As above, if there is a perforce-swarm-site.conf file in the data/etc 
directory, then this will be copied and used by Apache. Otherwise a new 
Apache config will be created using the SWARM_HOST from the env file.


---

 @copyright   2021 Perforce Software. All rights reserved.

---
 @license     Please see LICENSE in top-level folder of this distribution.



