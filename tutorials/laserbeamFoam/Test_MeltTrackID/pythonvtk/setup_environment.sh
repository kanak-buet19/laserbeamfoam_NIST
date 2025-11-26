#!/bin/bash

# Environment setup script for melt pool analyzer on HPC

echo "Setting up environment for melt pool analyzer..."

# Method 1: Using pip (if you have Python available)
setup_with_pip() {
    echo "Setting up with pip..."
    
    # Create virtual environment (recommended)
    python -m venv melt_pool_env
    source melt_pool_env/bin/activate
    
    # Upgrade pip
    pip install --upgrade pip
    
    # Install required packages
    pip install vtk numpy matplotlib scipy scikit-image
    
    echo "Virtual environment created: melt_pool_env"
    echo "To activate: source melt_pool_env/bin/activate"
}

# Method 2: Using conda/miniconda (if available)
setup_with_conda() {
    echo "Setting up with conda..."
    
    # Create conda environment
    conda create -n melt_pool_env python=3.8 -y
    conda activate melt_pool_env
    
    # Install packages
    conda install -c conda-forge vtk numpy matplotlib scipy scikit-image -y
    
    echo "Conda environment created: melt_pool_env"
    echo "To activate: conda activate melt_pool_env"
}

# Method 3: Using module system (common on HPCs)
setup_with_modules() {
    echo "Using HPC modules..."
    echo "Add these lines to your job script:"
    echo "module load python/3.8"
    echo "module load vtk"
    echo "module load scipy-stack"
    echo "# or similar modules available on your HPC"
}

# Check what's available
echo "Checking available Python installations..."

if command -v python &> /dev/null; then
    echo "Python found: $(which python)"
    python --version
fi

if command -v python3 &> /dev/null; then
    echo "Python3 found: $(which python3)"
    python3 --version
fi

if command -v conda &> /dev/null; then
    echo "Conda found: $(which conda)"
    conda --version
fi

if command -v module &> /dev/null; then
    echo "Module system found"
    echo "Available Python modules:"
    module avail python 2>/dev/null || echo "No Python modules listed"
fi

echo ""
echo "Choose installation method:"
echo "1) pip (creates virtual environment)"
echo "2) conda (if available)"
echo "3) Use HPC modules (recommended for HPC systems)"
echo "4) Show package requirements only"

read -p "Enter choice (1-4): " choice

case $choice in
    1)
        setup_with_pip
        ;;
    2)
        if command -v conda &> /dev/null; then
            setup_with_conda
        else
            echo "Conda not found. Try option 1 or 3."
        fi
        ;;
    3)
        setup_with_modules
        ;;
    4)
        echo "Required packages:"
        echo "- vtk"
        echo "- numpy"
        echo "- matplotlib"
        echo "- scipy"
        echo "- scikit-image"
        ;;
    *)
        echo "Invalid choice"
        ;;
esac

echo ""
echo "After setting up the environment, you can run:"
echo "python melt_pool_analyzer_hpc.py --help"