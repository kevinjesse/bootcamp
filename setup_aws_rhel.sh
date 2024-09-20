#!/bin/bash

# Set the default user; if root, switch to 'ec2-user'
DEFAULT_USER=$(whoami)
if [ "$DEFAULT_USER" == "root" ]; then
    DEFAULT_USER="ec2-user"
fi

REPO_DIR="/home/$DEFAULT_USER/bootcamp"
ENV_NAME="course-env"
CONDA_DIR="/home/$DEFAULT_USER/miniconda"
CONDA_PATH="$CONDA_DIR/bin/conda"
JUPYTER_BIN="$CONDA_DIR/envs/$ENV_NAME/bin/jupyter"

# Function to run command as a specific user using sudo
function run_as_user {
    local user=$1
    shift
    sudo -H -u $user bash -c "$*"
}

function setup_repository {
    if [ ! -d "$REPO_DIR" ]; then
        run_as_user $DEFAULT_USER "git clone https://github.com/kevinjesse/bootcamp.git $REPO_DIR"
    fi
}

# Update package lists and install essential packages
function update_system {
    sudo yum -y update
    sudo yum -y install curl unzip wget git yum-utils

    # Install EPEL repository
    sudo amazon-linux-extras install epel -y

    # Install Git LFS
    sudo yum -y install git-lfs

    # Install Docker using Amazon's extras
    sudo amazon-linux-extras install docker -y

    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker

    # Add user to docker group
    sudo usermod -aG docker $DEFAULT_USER

    # Install Docker Compose
    sudo curl -L "https://github.com/docker/compose/releases/download/v2.2.3/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose

    # Verify Docker Compose installation
    /usr/local/bin/docker-compose --version
}

# Install Python tools and environment
function install_python_tools {
    run_as_user $DEFAULT_USER "mkdir -p /home/$DEFAULT_USER"
    if [ ! -d "$CONDA_DIR" ]; then
        run_as_user $DEFAULT_USER "wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /home/$DEFAULT_USER/Miniconda3.sh"
        run_as_user $DEFAULT_USER "bash /home/$DEFAULT_USER/Miniconda3.sh -b -p $CONDA_DIR"
        run_as_user $DEFAULT_USER "rm /home/$DEFAULT_USER/Miniconda3.sh"
    else
        echo "Miniconda directory already exists."
    fi

    # Add conda initialization to .bashrc
    local conda_init_script="$CONDA_DIR/etc/profile.d/conda.sh"
    run_as_user $DEFAULT_USER "echo '. $conda_init_script' >> /home/$DEFAULT_USER/.bashrc"
    run_as_user $DEFAULT_USER "echo 'conda activate base' >> /home/$DEFAULT_USER/.bashrc"

    # Create the environment using the environment.yml file
    local env_file="$REPO_DIR/environment.yml"

    # Use conda commands with the environment properly initialized
    run_as_user $DEFAULT_USER "source $conda_init_script && conda env create -f $env_file"

    # Install Jupyter and the kernel in the created environment
    run_as_user $DEFAULT_USER "source $conda_init_script && conda activate $ENV_NAME && \
        conda install jupyterlab ipykernel --yes && \
        python -m ipykernel install --user --name $ENV_NAME --display-name 'Python 3.11 ($ENV_NAME)'"
}

# Update Jupyter configuration and start Jupyter Lab
function start_jupyter {
    local JUPYTER_CONFIG_DIR="/home/$DEFAULT_USER/.jupyter"
    run_as_user $DEFAULT_USER "mkdir -p $JUPYTER_CONFIG_DIR"
    local JUPYTER_CONFIG_FILE="$JUPYTER_CONFIG_DIR/jupyter_lab_config.py"

    if [ ! -f "$JUPYTER_CONFIG_FILE" ]; then
        run_as_user $DEFAULT_USER "source $CONDA_DIR/etc/profile.d/conda.sh && conda activate $ENV_NAME && $JUPYTER_BIN lab --generate-config"
    fi

    if ! run_as_user $DEFAULT_USER "grep -q 'c.MultiKernelManager.default_kernel_name' $JUPYTER_CONFIG_FILE"; then
        run_as_user $DEFAULT_USER "echo \"c.MultiKernelManager.default_kernel_name = '$ENV_NAME'\" >> $JUPYTER_CONFIG_FILE"
    fi

    local jupyter_token=$(run_as_user $DEFAULT_USER "openssl rand -hex 32")
    run_as_user $DEFAULT_USER "tmux new-session -d -s jupyter \"cd $REPO_DIR && source $CONDA_DIR/etc/profile.d/conda.sh && conda activate $ENV_NAME && $JUPYTER_BIN lab --ip=0.0.0.0 --no-browser --log-level=INFO --NotebookApp.token='$jupyter_token'\""
    sleep 10

    public_hostname="localhost"
    local access_url="http://$public_hostname:8888/lab?token=$jupyter_token"
    echo "Jupyter Lab is accessible at: $access_url"

    local filename="/home/$DEFAULT_USER/${public_hostname}_access_details.txt"
    run_as_user $DEFAULT_USER "echo -e 'DNS: $public_hostname\nUsername: $DEFAULT_USER\nAccess Token: $jupyter_token\nAccess URL: $access_url' > \"$filename\""
}

# Start Docker Compose
function start_docker {
    # Run docker-compose as root to avoid permission issues
    cd $REPO_DIR
    sudo /usr/local/bin/docker-compose up -d
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
