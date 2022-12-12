#!/bin/bash
#
# Configure Swarm in the docker environment. Will try to configure the connection to
# P4D, and also install server side extensions on P4D if possible.
#

export SWARM_HOME="/opt/perforce/swarm"
if [ -z "$SWARM_HOST" ]
then
    export SWARM_HOST="localhost"
fi
export DOCKER_DIR=${SWARM_HOME}/data/docker
export LOG="${SWARM_HOME}/data/docker.log"
export P4D="p4 -p${P4D_PORT} -u${P4D_SUPER}"

function log {
    echo "$(date +"%Y/%m/%d %H:%M:%S") - $*"
}

log "--"
log "Starting swarm-docker-setup.sh"


function die {
    log "$@"
    exit 1
}


#
# Wait for P4D to startup.
#
function waitForP4D {
    log "Checking P4D '${P4D_PORT}' to make sure it is running."

    local ATTEMPTS=0;
    while [ "${ATTEMPTS}" -lt "${P4D_GRACE:-30}" ]
    do
        if [[ "${P4D_PORT}" =~ ssl:.* ]]
        then
            p4 -p"${P4D_PORT}" trust -fy || log "Failed to trust SSL on '${P4D_PORT}'"
        fi
        if p4 -p "${P4D_PORT:-1666}" -ztag info -s
        then
            log "Contact!"
            return 0
        fi
        log "Waiting after ${ATTEMPTS}"
        ATTEMPTS=$((ATTEMPTS + 1))
        sleep 1
    done
    
    # Failed
    return 1
}

function configureP4D {
    # Check to see if Swarm triggers or extensions are already installed
    NEEDCONFIG=0
    $P4D triggers -o | grep -q "swarm"
    NEEDCONFIG=$?
    if [ $NEEDCONFIG -ne 0 ]
    then
        $P4D extension --list --type extensions | grep -q "swarm"
        NEEDCONFIG=$?
        if [ $NEEDCONFIG -eq 0 ]
        then
            log "Detected Swarm extensions already installed."
            
            if [ "${SWARM_FORCE_EXT}" = "y" ]
            then
                $P4D extension --delete Perforce::helix-swarm -y
                log "Deleted existing Swarm extension to force re-configuration."
                return 0
            else
                log "You will need to re-configure them to point at this Swarm instance."
                return 1
            fi
        fi
        return 0
    else
        log "Detected Swarm triggers already installed."
        log "You will need to re-configure them to point at this Swarm instance"
        return 1
    fi
    
}

function writeConfig {
    local indents=$1
    local property=$2
    local value=$3

    if [ -z "$value" ]
    then
        printf "%${indents}s'%s' => [\n" ' ' "${property}"
    else
        printf "%${indents}s'%s' => %s,\n" ' ' "${property}" "${value}"
    fi
}

function writeClose {
    local indents=$1

    printf "%${indents}s],\n" ' '
}


function configureSwarm {
    log "Swarm does not appear to be configured, configuring it against '${P4D_PORT}'."
    
    if [ "${SWARM_PASSWD}" == "" ]
    then
        die "SWARM_PASSWD is not set. Failing."
    fi

    if [ "${P4D_SUPER_PASSWD}" == "" ]
    then
        die "P4D_SUPER_PASSWD is not set. Failing."
    fi
    
    log "Using super user [${P4D_SUPER}] with [${P4D_SUPER_PASSWD//[A-Za-z0-9]/X}]"
    log "Swarm user [${SWARM_USER}] with [${SWARM_PASSWD//[A-Za-z0-9]/X}]"

    # Give p4d a bit of time to startup
    waitForP4D || die "Unable to contact P4D server at '${P4D_PORT}'"
    
    log "Connected to P4D, beginning configuration check."
    
    P4D="p4 -p${P4D_PORT} -u${P4D_SUPER}"
        
    $P4D -ztag info | grep -q "unicode enabled" || log "*** The P4D server at '${P4D_PORT}' is not unicode enabled. We STRONGLY recommend using a Unicode server with Swarm ***"
    
    
    # Login to the server as the super user
    echo "${P4D_SUPER_PASSWD}" | $P4D login || die "Unable to login to '${P4D_PORT}' as user '${P4D_SUPER}' with '${P4D_SUPER_PASSWD}'"

    log "Logged in"
    EXTENSIONS="-x"
    configureP4D && EXTENSIONS="-X"
    
    # Does the Swarm user already exist?
    CREATE=""
    $P4D users | grep "${SWARM_USER} <" >> $LOG
    $P4D users | grep -q "${SWARM_USER} <" || CREATE="-c"

    # Base Swarm configuration
    /opt/perforce/swarm/sbin/configure-swarm.sh -n \
        -p "${P4D_PORT}" -U "${P4D_SUPER}" -W "${P4D_SUPER_PASSWD}" \
        -u "${SWARM_USER}" -w "${SWARM_PASSWD}" $CREATE -g \
        -H "${SWARM_HOST}" -e "${SWARM_MAILHOST}" ${EXTENSIONS} >> $LOG
    
    # shellcheck disable=SC2181
    if [ $? -ne 0 ]
    then
        log "configure-swarm.sh failed, using the following parameters:"
        log "-p \"${P4D_PORT}\" -U \"${P4D_SUPER}\" -W \"${P4D_SUPER_PASSWD}\""
        log "-u \"${SWARM_USER}\" -w \"${SWARM_PASSWD}\" $CREATE -g"
        log "-H \"${SWARM_HOST}\" -e \"${SWARM_MAILHOST}\" -X"
        exit 1
    fi
    
    log "Successfully configured Swarm"
    
    # Get a ticket that stays valid if the container restarts
    SWARM_TICKET=$(echo "${SWARM_PASSWD}" | p4 -p "${P4D_PORT}" -u "${SWARM_USER}" login -ap | grep -v word)
    sed -i "s/\('password' => '\)[0-9A-F]*/\1${SWARM_TICKET}/" "${SWARM_HOME}/data/config.php"

    # Create a new Swarm token
    mkdir -p "${SWARM_HOME}/data/queue/tokens"
    mkdir -p "${SWARM_HOME}/data/queue/workers"
    
    pushd ${SWARM_HOME}/data/queue/tokens || die "Unable to cd into tokens directory"
    SWARM_TOKEN=$(ls | head -1)
    if [ -z "$SWARM_TOKEN" ]
    then
        SWARM_TOKEN=$(uuid)
        touch "$SWARM_TOKEN"
    fi
    popd || die "Unable to return from tokens directory"
    log "Generated a swarm token of ${SWARM_TOKEN}"
    
    # Remove trailing close brackets.
    sed -i "s/);//g" ${SWARM_HOME}/data/config.php

    # Manually build up the configuration file with options.
    {
        writeConfig 4 log
        writeConfig 8 priority 7
        writeClose 4
        writeConfig 4 redis
        writeConfig 8 options
        [ ! -z "$SWARM_REDIS_PASSWD" ] && writeConfig 12 password "'$SWARM_REDIS_PASSWD'"
        [ ! -z "$SWARM_REDIS_NAMESPACE" ] && writeConfig 12 namespace "'$SWARM_REDIS_NAMESPACE'"
        writeConfig 12 server
        writeConfig 16 host "'$SWARM_REDIS'"
        [ ! -z "$SWARM_REDIS_PORT" ] && writeConfig 16 port "$SWARM_REDIS_PORT"
        writeClose 12
        writeClose 8
        writeClose 4
        echo ");"
    } >> ${SWARM_HOME}/data/config.php

    rm -f ${SWARM_HOME}/data/cache/*
    rm -f ${SWARM_HOME}/data/p4trust
    chown -R www-data:www-data ${SWARM_HOME}/data
}

function configureApacheOnly {
    log "Need to configure Apache"
    APACHE_CONF_DIR=/etc/apache2
    APACHE_SITES_DIR=${APACHE_CONF_DIR}/sites-available
    a2enmod rewrite
    a2enmod ssl
    a2enmod remoteip

    if [ ! -d "${DOCKER_DIR}/sites-available" ]
    then
        mkdir -p "${DOCKER_DIR}/sites-available"
        sed -e 's#APACHE_LOG_DIR#/var/log/apache2#' -e "s#REPLACE_WITH_SERVER_NAME#${SWARM_HOST}#" \
              /opt/perforce/etc/perforce-swarm-site.conf > "${DOCKER_DIR}/sites-available/perforce-swarm-site.conf"
    elif [ -f "${DOCKER_DIR}/sites-available" ]
    then
        log "Assuming Apache configured externally"
        find "${APACHE_SITES_DIR}/" -name "*.conf" -exec sh -c 'a2ensite $(basename {})' \;
        return
    fi
    rm -fr "${APACHE_SITES_DIR}" "${APACHE_CONF_DIR}/sites-enabled/*"
    ln -s "${DOCKER_DIR}/sites-available" "${APACHE_SITES_DIR}"
    find "${APACHE_SITES_DIR}/" -name "*.conf" -exec sh -c 'a2ensite $(basename {})' \;
}

# We copy some configuration files into a directory which will be part of the
# persistent volume. 
mkdir -p ${DOCKER_DIR}

# If there is already a config.php file, then we assume that we are running of a persisted volume, and
# do not run first time configuration. Instead we try to preserve configuration files between runs.
if  [ -f ${SWARM_HOME}/data/config.php ]
then
    if [ -d "${SWARM_HOME}/data/cache" ]
    then
        # Clear the module cache in case this is an upgrade
        rm -f ${SWARM_HOME}/data/cache/*.php
    fi
    if apachectl -S | grep -q "swarm"
    then
        log "Everything seems to be configured."
    else
        configureApacheOnly
    fi

    HOSTS_FILE="/opt/perforce/etc/swarm-cron-hosts.conf"
    if [ ! -f "${DOCKER_DIR}/swarm-cron-hosts.conf" ]
    then
        if [ ! -f "${HOSTS_FILE}" ]
        then
            echo "http://localhost:80" > "${HOSTS_FILE}"
        fi
        mv "${HOSTS_FILE}" "${DOCKER_DIR}/swarm-cron-hosts.conf"
    fi
    ln -fs "${DOCKER_DIR}/swarm-cron-hosts.conf" "${HOSTS_FILE}"

    CUSTOM_DIR="/opt/perforce/swarm/public/custom"
    if [ -d "${DOCKER_DIR}/custom" ]
    then
        rm -fr "${CUSTOM_DIR}"
    elif [ -d "${CUSTOM_DIR}" ]
    then
        mv "${CUSTOM_DIR}" "${DOCKER_DIR}/custom"
    else
        mkdir -p "${DOCKER_DIR}/custom"
    fi
    ln -s "${DOCKER_DIR}/custom" "${CUSTOM_DIR}"
    
    if [ ! -f "${DOCKER_DIR}/php.ini" ]
    then
        mv "/etc/php/7.4/apache2/php.ini" "${DOCKER_DIR}/php.ini"
    else
        rm -f "/etc/php/7.4/apache2/php.ini"
    fi
    ln -fs "${DOCKER_DIR}/php.ini" "/etc/php/7.4/apache2/php.ini"
else
    log "Configuring new instance of Swarm"
    configureSwarm
    cat /opt/perforce/swarm/data/config.php

    echo "http://localhost:80" > "${DOCKER_DIR}/swarm-cron-hosts.conf"
    ln -fs "${DOCKER_DIR}/swarm-cron-hosts.conf" "/opt/perforce/etc/swarm-cron-hosts.conf"
    mv "/etc/apache2/sites-available" "${DOCKER_DIR}"
    ln -s "${DOCKER_DIR}/sites-available" "/etc/apache2/sites-available"
    mkdir -p "${DOCKER_DIR}/custom"
    ln -s "${DOCKER_DIR}/custom" "/opt/perforce/swarm/public/custom"
    mv "/etc/php/7.4/apache2/php.ini" "${DOCKER_DIR}/php.ini"
    ln -fs "${DOCKER_DIR}/php.ini" "/etc/php/7.4/apache2/php.ini"
fi

# If the data directory is externally mounted, ensure the version is easily accessible.
cp /opt/perforce/etc/Docker-Version ${DOCKER_DIR}
cp /opt/perforce/swarm/Version ${DOCKER_DIR}

log "Swarm setup finished."


# We need Cron running, but we want Apache to run as a foreground process so that Docker can track it.
# Since the configuration script starts Apache, we need to ensure it is stopped.
service cron start
apache2ctl stop
sleep 2

exec apache2ctl -D FOREGROUND
