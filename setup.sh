#!/bin/bash

# Load company-specific information from company.yml if it exists
function setup_env_variables {
    COMPANY_FILE="company.yml"
    if [ -f "$COMPANY_FILE" ]; then
        python3 -c "import yaml, os; [os.environ.update({k.upper(): v for k, v in yaml.safe_load(open('$COMPANY_FILE').read()).items()})]"
    else
        echo "Warning: company.yml not found. Skipping company-specific configurations."
    fi
}

# Update package lists and install essential packages
function update_system {
    sudo apt-get update
    # Install AWS CLI
    if ! command -v aws &> /dev/null; then
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip awscliv2.zip
        sudo ./aws/install
        rm -rf awscliv2.zip ./aws
    fi
    # Install Git if not installed
    if ! command -v git &> /dev/null; then
        sudo apt-get install -y git
    fi
}

# Install and configure Python environment
function install_python_tools {
    # Install Miniconda
    if [ ! -d "$HOME/miniconda" ]; then
        wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O $HOME/Miniconda3-latest-Linux-x86_64.sh
        bash $HOME/Miniconda3-latest-Linux-x86_64.sh -b -p $HOME/miniconda
        rm $HOME/Miniconda3-latest-Linux-x86_64.sh
    fi
    export PATH="$HOME/miniconda/bin:$PATH"
    if ! command -v conda &> /dev/null; then
        echo "Conda installation failed or Conda executable not found in PATH."
        exit 1
    fi

    # Install JupyterLab
    source $HOME/miniconda/bin/activate course-env
    conda install ipykernel
    python3 -m ipykernel install --user --name course-env --display-name "Python3.11 (course-env)"

    # Install additional Python packages that require specific cli args with pip
    pip install packaging ninja
    pip install flash-attn --no-build-isolation

}

# Clone and set up the course repository
function setup_repository {
    if [ ! -d "$HOME/genai-bootcamp-curriculum" ]; then
        git clone https://github.com/kevinjesse/genai-bootcamp-curriculum.git $HOME/genai-bootcamp-curriculum
    fi
    cd $HOME/genai-bootcamp-curriculum
    local env_name="course-env"
    if conda info --envs | grep "$env_name" > /dev/null; then
        conda env update -n $env_name -f environment.yml
    else
        conda env create -f environment.yml
    fi
}

# Download data from S3 based on TASK
function download_data {
    if [ -n "$COMPANY_S3" ] && [ -n "$TASK" ]; then
        case "$TASK" in
            "MCN")
                aws s3 cp s3://$COMPANY_S3 $HOME/genai-bootcamp-curriculum/data/mcn --recursive
                ;;
            # Additional cases can be added here
        esac
    fi
}

# Start Jupyter Lab and other services
function start_jupyter {
   # Start Jupyter Lab in a detached tmux session
    tmux new-session -d -s jupyter_session "jupyter lab --ip=0.0.0.0 --no-browser --NotebookApp.token='' --log-level=INFO"

    # Allow some time for Jupyter Lab to start
    sleep 10  # Adjust sleep as needed based on your system's performance

    # Send the 'jupyter lab list' command to the session to get the URL with the token
    tmux send-keys -t jupyter_session "jupyter lab list" C-m

    # Wait a moment for the output to stabilize
    sleep 2

    # Capture the output directly from tmux buffer and extract the token
    jupyter_url=$(tmux capture-pane -p -t jupyter_session | grep -oP 'http://127.0.0.1:8888/lab\?token=\K[\w]+')

    # Check if the token was successfully captured
    if [ -z "$jupyter_url" ]; then
        echo "Failed to capture Jupyter Lab token."
        exit 1
    else
        # Get public hostname
        public_hostname=$(curl -s --max-time 1 http://169.254.169.254/latest/meta-data/public-hostname)
        if [ -z "$public_hostname" ]; then
            public_hostname="not-on-ec2"
        fi
        
        # Construct the full URL
        login_info="Jupyter Lab is accessible at: http://localhost:8888/lab?token=$jupyter_url"
        echo "$login_info"
        
        # Save the login info to a file named after the public hostname
        filename="$HOME/${public_hostname}.txt"
        echo "$login_info" > $filename
        
        # Upload the file to S3
        if [ -n "$COMPANY_S3" ]; then
            aws s3 cp $filename s3://$COMPANY_S3/${public_hostname}.txt
        fi
    fi


}

function start_docker {
    # Start Docker Compose services
    docker compose up -d
}

# Main execution
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
