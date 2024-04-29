#!/bin/bash

# Load company-specific information from company.yml if it exists
COMPANY_FILE="company.yml"

# Use Python to read the YAML file and set variables
if [ -f "$COMPANY_FILE" ]; then
    python3 -c "import yaml, os; [os.environ.update({k.upper(): v for k, v in yaml.safe_load(open('$COMPANY_FILE').read()).items()})]"
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
    aws s3 cp s3://$COMPANY_S3 $HOME/genai-bootcamp-curriculum/data/call_notes --recursive
fi

# Install Jupyter Lab if not already installed
if ! command -v jupyter-lab &> /dev/null
then
    conda install -y jupyterlab
fi

# Install additional Python packages with pip
pip install packaging ninja
pip install flash-attn --no-build-isolation

# Start PGVector DB
docker compose up -d

# Ensure log directory exists
mkdir -p $HOME/logs

# Start Jupyter Lab in a detached tmux session and log output
tmux new-session -d -s jupyter_session "jupyter lab --ip=0.0.0.0 --no-browser 2>&1 | tee $HOME/logs/jupyter_lab.log"

# Give Jupyter time to start and log the token
sleep 10

# Use Jupyter's list command to capture the running server's info
# Ensuring you execute the command in the same environment as Jupyter
tmux send-keys -t jupyter_session "jupyter lab list" Enter

# Wait a little for the command to execute
sleep 2

# Capture the output and extract the token
jupyter_token=$(grep -oP 'token=\K[\w]+' $HOME/logs/jupyter_lab.log)

# Check if the token was successfully captured
if [ -z "$jupyter_token" ]; then
    echo "Failed to capture Jupyter Lab token."
    exit 1
fi

#ssh
echo "SSH forwarding setup..."
echo "Jupyter Lab is accessible at: http://$public_hostname:8888/?token=$jupyter_token"

# Rest of your SSH forwarding setup...
echo "if using SSH forwarding, you can access your instance here:"
echo "Jupyter Lab is accessible at: http://localhost:8888/?token=$jupyter_token"

# Rest of your SSH forwarding setup...

