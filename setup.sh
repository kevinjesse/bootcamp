#!/bin/bash

# Load company-specific information from company.yml if it exists
function setup_env_variables {
    COMPANY_FILE="company.yml"
    if [ -f "$COMPANY_FILE" ]; then
        export $(python3 -c "import yaml; env_vars = yaml.safe_load(open('$COMPANY_FILE')); print(' '.join([f'{k.upper()}={v}' for k, v in env_vars.items()]))")
    else
        echo "Warning: company.yml not found. Skipping company-specific configurations."
    fi
}

# Update package lists and install essential packages
function update_system {
    sudo apt-get update
    sudo apt-get install -y curl unzip wget git
    # Install AWS CLI if not installed
    if ! command -v aws &> /dev/null; then
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip awscliv2.zip
        sudo ./aws/install
        rm -rf awscliv2.zip aws
    fi
}

function install_python_tools {
    if [ ! -d "$HOME/miniconda" ]; then
        wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O Miniconda3-latest-Linux-x86_64.sh
        bash Miniconda3-latest-Linux-x86_64.sh -b -p $HOME/miniconda
        rm Miniconda3-latest-Linux-x86_64.sh
    fi
    export PATH="$HOME/miniconda/bin:$PATH"
    source $HOME/miniconda/bin/activate
    conda activate course-env  # Make sure to activate the environment

    if ! command -v conda &> /dev/null; then
        echo "Conda installation failed or Conda executable not found in PATH."
        exit 1
    fi

    conda install ipykernel
    python -m ipykernel install --user --name course-env --display-name "Python 3.12 (course-env)"
    
    # Ensure all Conda operations are done before using pip
    conda install torch  # Ensure torch is installed
    pip install packaging ninja
    pip install --verbose flash-attn --no-build-isolation
}


# Clone and set up the course repository
function setup_repository {
    REPO_DIR="$HOME/genai-bootcamp-curriculum"
    if [ ! -d "$REPO_DIR" ]; then
        git clone https://github.com/kevinjesse/genai-bootcamp-curriculum.git $REPO_DIR
    fi
    cd $REPO_DIR
    local env_name="course-env"
    if conda env list | grep -qw "$env_name"; then
        conda env update -n $env_name -f environment.yml
    else
        conda env create -f environment.yml
    fi
}

# Download data from S3 based on TASK
function download_data {
    if [ -n "$COMPANY_S3" ] && [ -n "$TASK" ]; then
        local target_path="$HOME/genai-bootcamp-curriculum/data/${TASK,,}"
        mkdir -p "$target_path"
        aws s3 cp "s3://$COMPANY_S3/$TASK" "$target_path" --recursive
    fi
}

# Update Jupyter configuration to use the custom environment
function update_jupyter_config {
    JUPYTER_CONFIG_DIR="$HOME/.jupyter"
    mkdir -p $JUPYTER_CONFIG_DIR
    JUPYTER_CONFIG_FILE="$JUPYTER_CONFIG_DIR/jupyter_lab_config.py"

    if [ ! -f "$JUPYTER_CONFIG_FILE" ]; then
        jupyter lab --generate-config
    fi

    if ! grep -q "c.MultiKernelManager.default_kernel_name" $JUPYTER_CONFIG_FILE; then
        echo "c.MultiKernelManager.default_kernel_name = 'course-env'" >> $JUPYTER_CONFIG_FILE
    fi
}

# Start Jupyter Lab in a detached tmux session
function start_jupyter {
    update_jupyter_config
    tmux new-session -d -s jupyter "source $HOME/miniconda/bin/activate course-env; jupyter lab --ip=0.0.0.0 --no-browser --log-level=INFO"
    sleep 10  # Wait for Jupyter to start
    jupyter_token=$(tmux capture-pane -p -t jupyter | grep -oP 'token=\K[\w]+')
    if [ -z "$jupyter_token" ]; then
        echo "Failed to capture Jupyter Lab token."
        exit 1
    else
        public_hostname=$(curl -s --max-time 2 http://169.254.169.254/latest/meta-data/public-hostname)
        if [ -z "$public_hostname" ]; then
            public_hostname="not-on-ec2"
        fi
        echo "Jupyter Lab is accessible at: http://$public_hostname:8888/lab?token=$jupyter_token"
        echo "http://$public_hostname:8888/lab?token=$jupyter_token" > "$HOME/jupyter_access.txt"
        if [ -n "$COMPANY_S3" ]; then
            aws s3 cp "$HOME/jupyter_access.txt" "s3://$COMPANY_S3/jupyter_access.txt"
        fi
    fi
}

# Start Docker Compose services
function start_docker {
    docker compose up -d
}

# Main execution function
function main {
    setup_env_variables
    update_system
    install_python_tools
    setup_repository
    download_data
    start_jupyter
    start_docker
}

main
