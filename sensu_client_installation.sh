#!/bin/bash

#=================================================================================
# This shell script install Sensu client to current server host
# Functionality:
#   1. Find out which OS version current host has
#   2. Download related OS specific installation script from the file server.
#   3. Run the script to install Sensu client with given parameters.  
#
#   Copyright 2014 Cybercom Finland Oy
#==================================================================================

SENSU_VERSION="latest"

# Cloud type: cybercom, AWS, ...
CLIENT_CLOUD_TYPE="cybercom"

# Possibility to set SSL ON or OFF
# SSL mode on/off
#
# Currently SSL is not used
SENSU_SSL_MODE="OFF"

# Parameters for running the installation script.
# Please check that these are up to date and update them if needed.
RABBITMQ_HOST=""
RABBITMQ_PORT=5672
RABBITMQ_VHOST=""
RABBITMQ_USER=""
RABBITMQ_PASSWORD=""

# Configuration parameters related to Sensu client functionality
# These affect to configuration file client.json 
# Multiple subscriptions or handlers should be given separeted
# by comma, like "base, webservers".
SENSU_SUBSCRIPTIONS="base"
SENSU_KEEPALIVE_WARNING_THRESHOLD=30
SENSU_KEEPALIVE_CRITICAL_THRESHOLD=60
SENSU_KEEPALIVE_HANDLERS="keepalive"
SENSU_KEEPALIVE_REFRESH=1800

Help_Text()
{
    echo " Usage of sensu_client_installation.sh script"
    echo " Parameters:"
    echo " --rh <value>= set rabbitmq host
    --rvh <value>= set rabbitmq vhost
    --ru <value>= set rabbitmq user
    --rpass <value>= set rabbitmq password
    --sub <value>= sensu subcripted groups as subgroup1,subgroup2 etc..
    --cloudtype <value>= cloud type: cybercom, AWS, ...
    --help = help and this text"
}

# Some of the configuration parameters can be overridden by the user
# Default values given above are used otherwise.
#
# Example of usage:
#   <script name> --host 1.2.3.4 --password xyz --subscriptions generic,webservers
while [ "$1" != "" ]; do
    case $1 in
        --rh )                  shift
                                RABBITMQ_HOST=$1
                                ;;
        --rp )                  shift
                                RABBITMQ_PORT=$1
                                ;;
        --rvh )                 shift
                                RABBITMQ_VHOST=$1
                                ;;
        --ru )                  shift
                                RABBITMQ_USER=$1
                                ;;
        --rpass )               shift
                                RABBITMQ_PASSWORD=$1
                                ;;
        --sub)                  shift
                                SENSU_SUBSCRIPTIONS=$1
                                ;;
        --cloudtype)            shift
                                CLIENT_CLOUD_TYPE=$1
                                ;;                            
        --help)                 shift
                                Help_Text
                                exit 0
                                ;;

        * )                     echo "Unsupported parameter $1"
    esac
    shift
done

# Direct script output and errors into console and into a file 
exec &> >(tee -a /tmp/SensuClientInstall.log) 

system=unknown
if [ -f /etc/redhat-release ]; then
    system=redhat
elif [ -f /etc/system-release ]; then
    system=redhat
elif [ -f /etc/debian_version ]; then
    system=debian
fi

echo ""
echo "=============================================================="
echo "AUTOINSTALL"
echo $(date)
echo ""
echo "This script installs Sensu client into  your server"
echo "Your OS type is $system"
echo ""
echo "Parameters:"
echo "Sensu version: $SENSU_VERSION"
echo "File server IP: $FILESERVER_ADDRESS"
echo "RabbitMQ server IP: $RABBITMQ_HOST"
echo "RabbitMQ server port: $RABBITMQ_PORT"
echo "RabbitMQ virtual host: $RABBITMQ_VHOST"
echo "RabbitMQ user name: $RABBITMQ_USER"
echo "RabbitMQ password: *********"
echo "Sensu subscriptions: $SENSU_SUBSCRIPTIONS"
echo "Sensu keepalive warning threshold: $SENSU_KEEPALIVE_WARNING_THRESHOLD"
echo "Sensu keepalive critical threshold: $SENSU_KEEPALIVE_CRITICAL_THRESHOLD"
echo "Sensu keepalive handlers: $SENSU_KEEPALIVE_HANDLERS"
echo "Sensu keepalive refresh: $SENSU_KEEPALIVE_REFRESH"
echo "Sensu SSL mode: $SENSU_SSL_MODE"
echo "=============================================================="
echo ""

if [ -z "$RABBITMQ_HOST" ] || [ -z "$RABBITMQ_USER" ] || [ -z "$RABBITMQ_PASSWORD" ] || [ -z "$RABBITMQ_VHOST" ]; then
    echo ""
    echo "You need to give RabbitMQ connection details!"
    echo "--rh, --ru, --rpass and --rvh needed."
    echo ""
    echo "Exiting."
    exit 1
fi

Run_Command()
{
  # Check if need sudo
  # Note: set -x activates debugging by directing command input to log file 
   if ([ $system == *"debian"* ] || [ $EUID -ne 0 ]); then
      echo "Need sudo"
      set -x
      sudo $1
   else
      set -x
      $1
   fi

   # Stop debugging
   set +x
}

function get_fact() {
    FACTVARIABLE=`grep -e "^$1 " </tmp/facts.$$.txt | sed -e 's/.* => //'`
}

Set_Config_Files()
{
    echo ""
    echo "=============================================================="
    echo "AUTOINSTALL"
    echo $(date)
    echo "Configuring sensu client"
    echo "=============================================================="
    echo ""
    echo "This may take a while...please wait"

# Two configuration files are needed: rabbitmq.json and client.json
# Let's first create file templates for them using Python 
python <<END
import json
import os

rabbitmq_data = {
  "rabbitmq": {
    "host": "RABBITMQ_HOST_TAG",
    "port": "RABBITMQ_PORT_TAG",
    "vhost": "RABBITMQ_VHOST_TAG",
    "user": "RABBITMQ_USER_TAG",
    "password": "RABBITMQ_PASSWORD_TAG"
  }
  
}
if os.environ['SENSU_SSL_MODE']=="ON" :
    rabbitmq_data['rabbitmq']['ssl'] = {
     "cert_chain_file": "/etc/sensu/ssl/cert.pem",
     "private_key_file": "/etc/sensu/ssl/key.pem"
     };
      
rabbitmq_file = open('rabbitmq.json', 'w')
json.dump(rabbitmq_data, rabbitmq_file, indent=4)

client_data = {
  "client": {
    "name": "SENSU_CLIENT_HOST_NAME_TAG",
    "address": "SENSU_CLIENT_IP_ADDRESS_TAG",
    "uuid": "SENSU_CLIENT_UUID_TAG",
    "tenant": "SENSU_CLIENT_TENANT_TAG",
    "cloud": "SENSU_CLIENT_CLOUD_TAG",
    "architecture": "SENSU_CLIENT_ARCHITECTURE_TAG",
    "cpu_cnt": "SENSU_CLIENT_CPU_CNT_TAG",
    "memory": "SENSU_CLIENT_MEMORY_TAG",
    "storage": "SENSU_CLIENT_STORAGE_TAG",
    "os": "SENSU_CLIENT_OS_TAG",
    "subscriptions": [ "SENSU_SUBSCRIPTIONS_TAG" ],
    "keepalive": {
      "thresholds": {
        "warning": "SENSU_KEEPALIVE_WARNING_TAG",
        "critical": "SENSU_KEEPALIVE_CRITICAL_TAG"
      },
      "handlers": [ "SENSU_KEEPALIVE_HANDLERS_TAG" ],
      "refresh": "SENSU_KEEPALIVE_REFRESH_TAG"
    }
  }
}
client_file = open('client.json', 'w')
json.dump(client_data, client_file, indent=4)

END

    # Then replace tagged fields with correct values.

    # Rabbitmq fields are hard coded at the beginning of this script
    sed -i -e s,RABBITMQ_HOST_TAG,$RABBITMQ_HOST,\
        -e s,\"RABBITMQ_PORT_TAG\",$RABBITMQ_PORT,\
        -e s,RABBITMQ_VHOST_TAG,$RABBITMQ_VHOST,\
        -e s,RABBITMQ_USER_TAG,$RABBITMQ_USER,\
        -e s,RABBITMQ_PASSWORD_TAG,$RABBITMQ_PASSWORD, rabbitmq.json

    Run_Command "mv rabbitmq.json /etc/sensu/conf.d/"

    # Install facter if it is not installed already
    if ! type -p facter > /dev/null; then
        echo "Installing facter"
        if [[ $system == *"debian"* ]]; then
            Run_Command "apt-get install -y facter"
        elif [[ $system == *"redhat"* ]]; then
            Run_Command "yum install -y facter"
        else
            echo "OS version not supported, installation cancelled"
            exit 1
        fi  
    fi   

    # Read client information
    Run_Command "facter -p" >/tmp/facts.$$.txt
    # Read local IP address and host name
    get_fact ipaddress
    LOCAL_IP_ADDRESS=$FACTVARIABLE
    LOCAL_HOST_NAME=$(hostname)
    # Read other client information
    if [ "$CLIENT_CLOUD_TYPE" = "cybercom" ]; then
        echo "Using Cybercom cloud"
        get_fact tenant
        SENSU_CLIENT_TENANT=$FACTVARIABLE
        get_fact uuid
        SENSU_CLIENT_UUID=`echo $FACTVARIABLE | tr [A-F] [a-f]`
        get_fact cloud
        SENSU_CLIENT_CLOUD=$FACTVARIABLE
        get_fact hardwaremodel
        SENSU_CLIENT_ARCHITECTURE=$FACTVARIABLE
        get_fact processorcount
        SENSU_CLIENT_CPU_CNT=$FACTVARIABLE
        get_fact memorysize
        SENSU_CLIENT_MEMORY=$FACTVARIABLE
        get_fact blockdevice_vda_size
        SENSU_CLIENT_STORAGE=$FACTVARIABLE
        get_fact operatingsystem
        TEMP=$FACTVARIABLE
        get_fact operatingsystemrelease
        SENSU_CLIENT_OS="$TEMP $FACTVARIABLE"
    else
        echo "Using $CLIENT_CLOUD_TYPE cloud"
        SENSU_CLIENT_TENANT=$CLIENT_CLOUD_TYPE
        get_fact domain
        SENSU_CLIENT_UUID=$FACTVARIABLE
        SENSU_CLIENT_TENANT=$CLIENT_CLOUD_TYPE
        get_fact uniqueid
        SENSU_CLIENT_CLOUD=$FACTVARIABLE
        SENSU_CLIENT_ARCHITECTURE=$CLIENT_CLOUD_TYPE
        SENSU_CLIENT_CPU_CNT=$CLIENT_CLOUD_TYPE
        SENSU_CLIENT_MEMORY=$CLIENT_CLOUD_TYPE
        SENSU_CLIENT_STORAGE=$CLIENT_CLOUD_TYPE
        SENSU_CLIENT_OS=$CLIENT_CLOUD_TYPE
    fi

    rm /tmp/facts.$$.txt

    # Fill in client.json parameter fields

    # First parse subscriptions and handlers separated by comma to required format
    # So these are assumed to be given in format like for example "generic,webservers"
    SENSU_SUBSCRIPTIONS=$(echo $SENSU_SUBSCRIPTIONS | sed 's/,/","/g')
    SENSU_KEEPALIVE_HANDLERS=$(echo $SENSU_KEEPALIVE_HANDLERS | sed 's/,/","/g')

    # Then fill the parameters
    sed -i -e s,SENSU_CLIENT_HOST_NAME_TAG,$LOCAL_HOST_NAME,\
        -e s,SENSU_CLIENT_IP_ADDRESS_TAG,$LOCAL_IP_ADDRESS,\
        -e s/SENSU_SUBSCRIPTIONS_TAG/$SENSU_SUBSCRIPTIONS/\
        -e s/\"SENSU_KEEPALIVE_WARNING_TAG\"/$SENSU_KEEPALIVE_WARNING_THRESHOLD/\
        -e s/\"SENSU_KEEPALIVE_CRITICAL_TAG\"/$SENSU_KEEPALIVE_CRITICAL_THRESHOLD/\
        -e s/SENSU_KEEPALIVE_HANDLERS_TAG/$SENSU_KEEPALIVE_HANDLERS/\
        -e s/\"SENSU_KEEPALIVE_REFRESH_TAG\"/$SENSU_KEEPALIVE_REFRESH/\
        -e s/SENSU_CLIENT_UUID_TAG/$SENSU_CLIENT_UUID/\
        -e s/SENSU_CLIENT_ARCHITECTURE_TAG/$SENSU_CLIENT_ARCHITECTURE/\
        -e s/SENSU_CLIENT_CPU_CNT_TAG/$SENSU_CLIENT_CPU_CNT/\
        -e "s/SENSU_CLIENT_MEMORY_TAG/$SENSU_CLIENT_MEMORY/"\
        -e s/SENSU_CLIENT_STORAGE_TAG/$SENSU_CLIENT_STORAGE/\
        -e "s/SENSU_CLIENT_OS_TAG/$SENSU_CLIENT_OS/"\
        -e s/SENSU_CLIENT_TENANT_TAG/$SENSU_CLIENT_TENANT/\
        -e s/SENSU_CLIENT_CLOUD_TAG/$SENSU_CLIENT_CLOUD/ client.json 

    Run_Command "mv client.json /etc/sensu/conf.d/"

}

Get_Plugins()
{
    github_plugins="https://raw.githubusercontent.com/cybercom-finland/sensu-community-plugins/master/plugins"

    echo ""
    echo "=============================================================="
    echo "AUTOINSTALL"
    echo $(date)
    echo "Download sensu plugins from Github"
    echo "=============================================================="
    echo ""
    Run_Command "wget -O /etc/sensu/plugins/check-disk.rb $github_plugins/system/check-disk.rb"
    Run_Command "wget -O /etc/sensu/plugins/check-memory-pcnt.sh $github_plugins/system/check-memory-pcnt.sh"
    Run_Command "wget -O /etc/sensu/plugins/check-procs.rb $github_plugins/processes/check-procs.rb"
    Run_Command "wget -O /etc/sensu/plugins/check-tail.rb $github_plugins/files/check-tail.rb"
    Run_Command "wget -O /etc/sensu/plugins/check-cpu.rb $github_plugins/system/check-cpu.rb"
    Run_Command "chmod ugo+rx /etc/sensu/plugins/*"

    if [ "$SENSU_SSL_MODE" == "ON" ]; then
        echo "SSL is set ON"
        mkdir -p /etc/sensu/ssl
        wget -O /etc/sensu/ssl/cert.pem http://$1/ssl_certs/client/cert.pem
        wget -O /etc/sensu/ssl/key.pem http://$1/ssl_certs/client/key.pem
    else
        echo "SSL is set OFF"
    fi
}

Install_Gems()
{
    echo ""
    echo "=============================================================="
    echo "AUTOINSTALL"
    echo $(date)
    echo "Install requirements from Ruby gems"
    echo "=============================================================="
    echo ""
    Run_Command "gem install sensu-plugin"
    Run_Command "gem install fileutils"
}

Install_Requirements() {
    echo ""
    echo "=============================================================="
    echo "AUTOINSTALL"
    echo $(date)
    echo "Install requirements from repository"
    echo "=============================================================="
    echo ""

    if [[ $system == *"redhat"* ]]; then
        Run_Command "yum -y install rubygem-json ruby-devel"
        Run_Command "yum -y install ImageMagick ImageMagick-devel"
        Run_Command "yum -y install gcc make"
        gem --version >/dev/null 2>&1 ||  Run_Command "yum install -y rubygems"
    elif [[ $system == *"debian"* ]]; then
        Run_Command "apt-get install -y bc"
        Run_Command "apt-get install -y ruby-json ruby-dev"
        Run_Command "apt-get install -y imagemagick libmagickwand-dev"
        Run_Command "apt-get install -y gcc make"
        gem --version >/dev/null 2>&1 || Run_Command "apt-get install -y rubygems"
    fi
}

# Functions which handles Installation for different Os 1st Rhel installation function
Install_Sensu_Rhel()
{
    echo "[sensu]
name=sensu-main
baseurl=http://repos.sensuapp.org/yum/el/6/\$basearch/
gpgcheck=0
enabled=1" > sensu.repo

    Run_Command "mv sensu.repo /etc/yum.repos.d/sensu.repo"

    echo ""
    echo "=============================================================="
    echo "AUTOINSTALL"
    echo $(date)
    echo "Install Sensu for RedHat"
    echo "=============================================================="
    echo ""   
    # Run_Command "yum -y install sensu-$SENSU_VERSION --nogpgcheck"
    Run_Command "yum -y install sensu --nogpgcheck"

    Get_Plugins

    Set_Config_Files

    Install_Requirements

    Install_Gems

    echo ""
    echo "=============================================================="
    echo "AUTOINSTALL"
    echo $(date)
    echo "Start sensu client"
    echo "=============================================================="
    echo ""
    Run_Command "chkconfig sensu-client on"
}

#2nd ubuntu installation function
Install_Sensu_Debian()
{
    set -x
    wget -q http://repos.sensuapp.org/apt/pubkey.gpg -O- | sudo apt-key add -
    echo "deb     http://repos.sensuapp.org/apt sensu main" > sensu.list
    set +x

    Run_Command "mv sensu.list /etc/apt/sources.list.d/"

    echo ""
    echo "=============================================================="
    echo "AUTOINSTALL"
    echo $(date)
    echo "Download latest OS updates"
    echo "=============================================================="
    echo ""   
    Run_Command "apt-get update"

    echo ""
    echo "=============================================================="
    echo "AUTOINSTALL"
    echo $(date)
    echo "Install Sensu for debian"
    echo "=============================================================="
    echo ""   
    # Run_Command "apt-get install sensu=$SENSU_VERSION"
    Run_Command "apt-get install sensu"

    Get_Plugins

    Set_Config_Files

    Install_Requirements

    Install_Gems

    echo ""
    echo "=============================================================="
    echo "AUTOINSTALL"
    echo $(date)
    echo "Start Sensu client"
    echo "=============================================================="
    echo ""
    Run_Command "update-rc.d sensu-client defaults"
}

if [[ $system == *"debian"* ]]; then
    LOCAL_OS_VERSION=$(lsb_release -d)
    echo $LOCAL_OS_VERSION
    if ! [[ $LOCAL_OS_VERSION == *"Ubuntu 14.04"* ]]; then
        echo "Warning: Installation script not tested with current OS version."
    fi  
    Install_Sensu_Debian
elif [[ $system == *"redhat"* ]]; then
    echo "Current OS version is RHEL"
    Install_Sensu_Rhel
else
    echo "OS version not supported, installation cancelled"
    exit 1
fi

# Start sensu-client
Run_Command "/etc/init.d/sensu-client start"

echo ""
echo "=============================================================="
echo "AUTOINSTALL"
echo $(date)
echo "Installation done...".
echo "Installation log can be found from /tmp/SensuClientInstall.log"
echo "=============================================================="
echo ""

exit 0
