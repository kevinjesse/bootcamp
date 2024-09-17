#!/bin/bash

DEFAULT_USER="ubuntu"
REPO_DIR="/home/$DEFAULT_USER/bootcamp"

# Function to run command as a specific user
function run_as_user {
    local user=$1
    shift
    sudo -u $user "$@"
}

function setup_repository {
    REPO_DIR="$HOME/bootcamp"
    if [ ! -d "$REPO_DIR" ]; then
        git clone https://github.com/kevinjesse/bootcamp.git $REPO_DIR
    fi
    cd $REPO_DIR
}

# Function to wait until the apt-get locks are released
function wait_apt_locks_released {
    echo 'Waiting for apt locks to be released...'
    while sudo fuser /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        sleep 1
    done
}

# Update package lists and install essential packages
function update_system {
    sudo apt-get update
    sudo apt-get install -y curl unzip wget git git-lfs docker-compose-plugin
}

# Install Python tools and environment
function install_python_tools {
    run_as_user $DEFAULT_USER mkdir -p /home/$DEFAULT_USER
    if [ ! -d "/home/$DEFAULT_USER/miniconda" ]; then
        run_as_user $DEFAULT_USER wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /home/$DEFAULT_USER/Miniconda3-latest-Linux-x86_64.sh
        run_as_user $DEFAULT_USER bash /home/$DEFAULT_USER/Miniconda3-latest-Linux-x86_64.sh -b -p /home/$DEFAULT_USER/miniconda
        run_as_user $DEFAULT_USER rm /home/$DEFAULT_USER/Miniconda3-latest-Linux-x86_64.sh
    else
        echo "Directory Exists"
    fi

    local CONDA_PATH="/home/$DEFAULT_USER/miniconda/bin/conda"
    run_as_user $DEFAULT_USER $CONDA_PATH init bash
    run_as_user $DEFAULT_USER bash -c "source /home/$DEFAULT_USER/.bashrc"


    local env_file="/home/$DEFAULT_USER/bootcamp/environment-versions.txt"
    local env_name="course-env"


    #conda create --name <env> --file <this file>
    run_as_user $DEFAULT_USER $CONDA_PATH create --name  $env_name --file $env_file
    run_as_user $DEFAULT_USER bash -c "source /home/$DEFAULT_USER/miniconda/bin/activate $env_name && $CONDA_PATH install ipykernel --yes && python -m ipykernel install --user --name $env_name --display-name 'Python 3.11 ($env_name)'"
}


# Update Jupyter configuration and start Jupyter Lab
function start_jupyter {
    local JUPYTER_CONFIG_DIR="/home/$DEFAULT_USER/.jupyter"
    run_as_user $DEFAULT_USER mkdir -p $JUPYTER_CONFIG_DIR
    local JUPYTER_CONFIG_FILE="$JUPYTER_CONFIG_DIR/jupyter_lab_config.py"

    if [ ! -f "$JUPYTER_CONFIG_FILE" ]; then
        run_as_user $DEFAULT_USER jupyter lab --generate-config
    fi

    if ! grep -q "c.MultiKernelManager.default_kernel_name" $JUPYTER_CONFIG_FILE; then
        echo "c.MultiKernelManager.default_kernel_name = 'course-env'" | run_as_user $DEFAULT_USER tee -a $JUPYTER_CONFIG_FILE
    fi

    local jupyter_token=$(run_as_user $DEFAULT_USER openssl rand -hex 32)
    run_as_user $DEFAULT_USER tmux new-session -d -s jupyter "cd /home/$DEFAULT_USER/bootcamp/ && source /home/$DEFAULT_USER/miniconda/bin/activate course-env && jupyter lab --ip=0.0.0.0 --no-browser --log-level=INFO --NotebookApp.token='$jupyter_token'"
    sleep 10

    public_hostname="localhost"
    local access_url="http://$public_hostname:8888/lab?token=$jupyter_token"
    echo "Jupyter Lab is accessible at: $access_url"

    local filename="/home/$DEFAULT_USER/${public_hostname}_access_details.txt"
    echo -e "DNS: $public_hostname\nUsername: $DEFAULT_USER\nAccess Token: $jupyter_token\nAccess URL: $access_url" | run_as_user $DEFAULT_USER tee "$filename"
}

function start_docker {
    run_as_user $DEFAULT_USER bash -c "cd $REPO_DIR && docker compose up -d"
}


# Main function to run all setups
function main {
    update_system
    setup_repository
    install_python_tools
    start_jupyter
    start_docker
}

main "$@"