#!/bin/bash

# Load company-specific information from company.yml if it exists
COMPANY_FILE="company.yml"

# Check if the company.yml file exists
if [ -f "$COMPANY_FILE" ]; then
    # Read the YAML file and set variables
    eval "$(yaml2json < "$COMPANY_FILE" | jq -r 'to_entries|map("export \(.key|ascii_upcase)='\''\(.value)'\''")|.[]')"
else
    echo "Warning: company.yml not found. Skipping company-specific configurations."
fi

# Update package lists
sudo apt-get update

# Check if the public hostname is available
public_hostname=$(curl -s --max-time 1 http://169.254.169.254/latest/meta-data/public-hostname)

# If the public hostname is not available, set a placeholder
if [ -z "$public_hostname" ]; then
    public_hostname="not-on-ec2"
fi

# Install AWS CLI if not already installed
if ! command -v aws &> /dev/null
then
    # Download the AWS CLI
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    # Unzip the installer
    unzip awscliv2.zip
    # Install AWS CLI
    sudo ./aws/install
    # Cleanup AWS CLI installer files
    rm -rf awscliv2.zip ./aws
fi

# Install Miniconda if not already installed
if [ ! -d "$HOME/miniconda" ]; then
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O $HOME/Miniconda3-latest-Linux-x86_64.sh
    bash $HOME/Miniconda3-latest-Linux-x86_64.sh -b -p $HOME/miniconda
    rm $HOME/Miniconda3-latest-Linux-x86_64.sh
fi

# Set PATH directly in the script
export PATH="$HOME/miniconda/bin:$PATH"

# Verify Conda is in the PATH
if ! command -v conda &> /dev/null
then
    echo "Conda installation failed or Conda executable not found in PATH."
    exit 1
fi

# Check if git is installed, install if not
if ! command -v git &> /dev/null
then
    sudo apt-get install -y git
fi

# Clone the course repository if it does not already exist
if [ ! -d "$HOME/genai-bootcamp-curriculum" ]; then
    git clone https://github.com/kevinjesse/genai-bootcamp-curriculum.git $HOME/genai-bootcamp-curriculum
fi
cd $HOME/genai-bootcamp-curriculum

# Create Conda environment from environment.yml if it doesn't exist
if ! conda info --envs | grep 'course-env'; then
    conda env create -f environment.yml
fi

# Activate environment
source $HOME/miniconda/bin/activate course-env

# Download data from S3 to the local file system before starting Jupyter
if [ -n "$COMPANY_S3" ]; then
    aws s3 cp s3://$COMPANY_S3 $HOME/genai-bootcamp-curriculum/call_notes --recursive
fi

# Install Jupyter Lab if not already installed
if ! command -v jupyter-lab &> /dev/null
then
    conda install -y jupyterlab
fi

# Install additional Python packages with pip
pip install packaging ninja
pip install flash-attn --no-build-isolation

# Start Jupyter Lab in a detached tmux session
tmux new-session -d -s jupyter_session 'jupyter lab --ip=0.0.0.0 --no-browser'

# Wait for Jupyter to start
sleep 5

# Extract Jupyter security token
jupyter_token=$(grep -Po 'token=\K[^&]+' $HOME/.jupyter/jupyter_server_config.json)

# If the public hostname is available, set up SSH port forwarding
if [ "$public_hostname" != "not-on-ec2" ]; then
    # SSH port forwarding to localhost:8888
    if [ -n "$COMPANY_PROXY" ]; then
        if [ -n "$COMPANY_PROXY" ]; then
            ssh -o "ProxyCommand=nc -X connect -x $COMPANY_PROXY %h %p" -nNT -L 8888:localhost:8888 -i ~/.ssh/bootcamp.pem ubuntu@$public_hostname
        else
            ssh -nNT -L 8888:localhost:8888 -i ~/.ssh/bootcamp.pem ubuntu@$public_hostname
        fi
    else
        ssh -nNT -L 8888:localhost:8888 -i ~/.ssh/bootcamp.pem ubuntu@$public_hostname
    fi
else
    echo "Not on EC2. SSH port forwarding not configured."
fi

# Dump the address of Jupyter instance with token
echo "Jupyter Lab is accessible at: http://localhost:8888/?token=$jupyter_token"

# Disconnect from the tmux session
tmux detach -s jupyter_session
