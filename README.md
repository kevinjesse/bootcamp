# Project Repository Overview

This repository is designed as a comprehensive suite for a machine learning bootcamp course, containing a range of training exercises, capstone projects, and related resources. Below is a detailed overview of the repository contents, structured to facilitate a hands-on learning experience with diverse tools and techniques in machine learning.

## Table of Contents
1. [Daily Exercises](#daily-exercises)
2. [Capstone Projects](#capstone-projects)
3. [Supporting Files and Directories](#supporting-files-and-directories)
4. [Setup and Configuration](#setup-and-configuration)
5. [License](#license)
6. [Contact Information](#contact-information)

## Daily Exercises
This section provides practical experience with different machine learning tasks and tools through various exercises.

### Day 1
- **Transformers Exercise**: Understand and apply model encodings for prediction tasks.

### Day 2
- **Cosine Similarity Exercise**: Sample calculation of cosine similarity
- **Vector Database Exercise**: Setting up simple Vector DB example.

### Day 3
- **Langchain Exercise**: Tutorial resources including images and notebooks on Langchain basics.
- **Synthetic Data Exercise**: Tools and datasets for synthetic data manipulation.

## Capstone Projects
Designed to integrate skills from the course into substantial, real-world data science tasks.

### 2.1 Vector Database
- **Notebooks**: Guides on document embeddings and vector databases.
- **Scripts**: Tools for embedding generation and database queries.

### 2.2 RAG Prompt Engineering
- **Data and Notebooks**: Advanced exercises on RAG for prompt engineering.
- **Scripts**: Support scripts for RAG operations.

### 2.3 Finetuning for RAG
- **Notebooks**: Comprehensive guides on fine-tuning for retrieval-augmented tasks.
- **Scripts**: Training and operational scripts.

### 2.4 Inference Methods
- **Notebooks and Scripts**: Resources on various inference methods, including practical applications.

## Supporting Files and Directories
- **`data/`**: Datasets for multiple projects.
- **`docker-compose.yml`**: Setup for required Docker containers.
- **`environment.yml`, `locked-environment.yml`**: Environment setup files.
- **`setup.sh`**: Script for initializing the development environment.

## Setup and Configuration

### Setup.py
Automates the environment setup necessary for the machine learning course. **This has already been done for you**.
1. **Loads Configurations**: Reads `company.yml` if available, to set environment variables.
2. **Updates and Installs**: Installs essential tools and updates software lists.
3. **Sets Up Python and Jupyter Notebook**: Installs Miniconda and configures Jupyter.
4. **Docker Services**: Details the setup of a PGVector database via Docker Compose. For more information on integrating PGVector with Langchain, visit the [Langchain PGVector integration documentation](https://python.langchain.com/docs/integrations/vectorstores/pgvector/).

## License
This project is released under the [Apache 2.0 License](https://www.apache.org/licenses/LICENSE-2.0), which details how the materials can be used, modified, and shared.

## Contact Information
For support or questions, please contact us at Henderson dot Johnson dot i i at Accenture dot com.

This repository is equipped with everything from basic exercises to complex projects to help users grasp complex concepts through practical implementation.