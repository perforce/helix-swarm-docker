#!/bin/bash
#
# Configure Swarm in the docker environment. Will try to configure the connection to
# P4D, and also install server side extensions on P4D if possible.
#

SWARM_HOME="/opt/perforce/swarm"

LOG="${SWARM_HOME}/data/docker.log"

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
    # Install Extensions / Triggers
    
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
                log "Deleting existing Swarm extension to force re-configuration."
                NEEDCONFIG=1
            else
                log "You will need to re-configure them with token ${SWARM_TOKEN} to point at this Swarm instance."
            fi
            
        fi
    else
        log "Detected Swarm triggers already installed."
        log "You will need to re-configure them with token ${SWARM_TOKEN} to point at this Swarm instance"
    fi
    
    if [ $NEEDCONFIG -ne 0 ]
    then
        $P4D info | grep -q P4D/LINUX
        # shellcheck disable=SC2181
        if [ $? -eq 0 ]
        then
            log "Configure ${P4D_PORT} to use Swarm extensions"
            echo "${P4D_SUPER_PASSWD}" | $P4D login
            $P4D extension --yes --allow-unsigned --install ${SWARM_HOME}/p4-bin/helix-swarm.p4-extension
            
            $P4D extension --configure Perforce::helix-swarm -o > /tmp/global.txt
            sed -i "s#... SWARM-TOKEN#${SWARM_TOKEN}#g" /tmp/global.txt
            # shellcheck disable=SC2153
            sed -i "s#/localhost/#/${SWARM_HOST}/#g" /tmp/global.txt
            sed -i "s#sampleExtensionsUser#${P4D_SUPER}#g" /tmp/global.txt
            $P4D extension --configure Perforce::helix-swarm -i < /tmp/global.txt
            rm -f /tmp/global.txt
            
            $P4D extension --configure Perforce::helix-swarm --name swarm -o | $P4D extension --configure Perforce::helix-swarm --name swarm -i
            log "Configured Swarm extensions against ${P4D_PORT}"
        else
            log "The server at ${P4D_PORT} is not a Linux server, so cannot configure Swarm extensions"
            log "You will need to configure Triggers on this server yourself using the token ${SWARM_TOKEN}"
        fi
    else
        log "Swarm extensions have not been configured."
    fi
}

function configureSwarm {
    log "Swarm does not appear to be configured, configuring it against '${P4D_PORT}'."
    
    # Give p4d a bit of time to startup
    waitForP4D || die "Unable to contact P4D server at '${P4D_PORT}'"
    
    log "Connected to P4D, beginning configuration check."
    
    P4D="p4 -p${P4D_PORT} -u${P4D_SUPER}"
        
    $P4D -ztag info | grep -q "unicode enabled" || log "*** The P4D server at '${P4D_PORT}' is not unicode enabled. We STRONGLY recommend using a Unicode server with Swarm ***"
    
    
    # Login to the server as the super user
    echo "${P4D_SUPER_PASSWD}" | $P4D login || die "Unable to login to '${P4D_PORT}' as user '${P4D_SUPER}' with '${P4D_SUPER_PASSWD}'"

    log "Logged in"

    # Does the Swarm user already exist?
    CREATE=""
    $P4D users | grep "${SWARM_USER} <" >> $LOG
    $P4D users | grep -q "${SWARM_USER} <" || CREATE="-c"

    # Base Swarm configuration
    /opt/perforce/swarm/sbin/configure-swarm.sh -n \
        -p "${P4D_PORT}" -U "${P4D_SUPER}" -W "${P4D_SUPER_PASSWD}" \
        -u "${SWARM_USER}" -w "${SWARM_PASSWD}" $CREATE -g \
        -H "${SWARM_HOST}" -e "${SWARM_MAILHOST}" >> $LOG
    
    # shellcheck disable=SC2181
    if [ $? -ne 0 ]
    then
        log "configure-swarm.sh failed, using the following parameters:"
        log "-p \"${P4D_PORT}\" -U \"${P4D_SUPER}\" -W \"${P4D_SUPER_PASSWD}\""
        log "-u \"${SWARM_USER}\" -w \"${SWARM_PASSWD}\" $CREATE -g"
        log "-H \"${SWARM_HOST}\" -e \"${SWARM_MAILHOST}\""
        exit 1
    fi
    
    log "Successfully configured Swarm"
    
    # Get a ticket that stays valid if the container restarts
    SWARM_TICKET=$(echo "${SWARM_PASSWD}" | p4 -p "${P4D_PORT}" -u "${SWARM_USER}" login -ap | grep -v word)
    sed -i "s/\('password' => '\)[0-9A-F]*/\1${SWARM_TICKET}/" "${SWARM_HOME}/data/config.php"

    # Create a new Swarm token
    mkdir -p ${SWARM_HOME}/data/queue/tokens
    mkdir -p ${SWARM_HOME}/data/queue/workers
    SWARM_TOKEN=$(uuid)
    touch "${SWARM_HOME}/data/queue/tokens/${SWARM_TOKEN}"
    
    log "Generated a swarm token of ${SWARM_TOKEN}"
    
    sed -i "s/);/    'log' => [\n        'priority' => 7,\n    ],\n    'redis' => [\n        'options' => [\n            'server' => [\n                'host' => '$SWARM_REDIS',\n            ],\n        ],\n    ],\n);/" ${SWARM_HOME}/data/config.php
    
    rm -f ${SWARM_HOME}/data/cache/*
    rm -f ${SWARM_HOME}/data/p4trust
    chown -R www-data:www-data ${SWARM_HOME}/data
}

function configureApacheOnly {
    log "Need to configure Apache"
    if [ -f ${SWARM_HOME}/data/etc/perforce-swarm-site.conf ]
    then
        cp ${SWARM_HOME}/data/etc/perforce-swarm-site.conf /etc/apache2/sites-available/perforce-swarm-site.conf
    else
        sed -e 's#APACHE_LOG_DIR#/var/log/apache2#' -e "s#REPLACE_WITH_SERVER_NAME#${SWARM_HOST}#" /opt/perforce/etc/perforce-swarm-site.conf > /etc/apache2/sites-available/perforce-swarm-site.conf
    fi
    a2ensite perforce-swarm-site
    a2enmod  rewrite
}

# Only configure swarm if the perforce-swarm-site is not already defined
if  [ -f ${SWARM_HOME}/data/config.php ]
then
    if apachectl -S | grep -q "swarm"
    then
        log "Everything seems to be configured."        
    else
        configureApacheOnly
    fi
    if [ -f ${SWARM_HOME}/data/etc/swarm-cron-hosts.conf ]
    then
        cp ${SWARM_HOME}/data/etc/swarm-cron-hosts.conf /opt/perforce/etc/swarm-cron-hosts.conf
    fi
else
    configureSwarm
    configureP4D
fi

# Make sure that we have a copy of the configuration files.
mkdir -p ${SWARM_HOME}/data/etc
cp /opt/perforce/etc/swarm-cron-hosts.conf ${SWARM_HOME}/data/etc
cp /etc/apache2/sites-available/perforce-swarm-site.conf ${SWARM_HOME}/data/etc

log "Swarm setup finished."


# We need Cron running, but we want Apache to run as a foreground process so that Docker can track it.
# Since the configuration script starts Apache, we need to ensure it is stopped.
service cron start
apache2ctl stop

exec apache2ctl -D FOREGROUND
