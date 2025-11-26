#!/bin/bash

#SBATCH --job-name=temp_analysis
#SBATCH --time=02:00:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --account=PNS0496
#SBATCH --output=temp_analysis_%j.out
#SBATCH --error=temp_analysis_%j.err

echo "Starting temperature analysis..."
echo "Job ID: $SLURM_JOB_ID"
echo "Date: $(date)"
echo "Submit directory: $SLURM_SUBMIT_DIR"

# Clean environment (exactly like your working script)
unset PYTHONPATH
unset PYTHON_PATH
module purge

# Load Python (following your working pattern)
if module load python/3.12; then
    echo "✅ Loaded python/3.12"
elif module load python/3.11; then
    echo "✅ Loaded python/3.11"
elif module load python/3.10; then
    echo "✅ Loaded python/3.10"
elif module load python; then
    echo "✅ Loaded default python"
else
    echo "⚠️ Could not load python module"
fi

# Try to load scientific modules (like your working script)
if module load scipy-stack 2>/dev/null; then
    echo "✅ scipy-stack loaded"
else
    echo "ℹ️ scipy-stack not available"
fi

if module load vtk 2>/dev/null; then
    echo "✅ VTK module loaded"
else
    echo "ℹ️ VTK module not available"
fi

# Navigate to working directory
cd $SLURM_SUBMIT_DIR

echo "Working directory: $(pwd)"
echo "Python path: $(which python)"
echo "Python version: $(python --version)"

# Test environment before running
echo "Testing Python packages..."
python -c "import sys; print(f'Python executable: {sys.executable}')"

# Run the temperature analysis
echo "🚀 Starting temperature analysis..."
python temperature_analysis.py

# Check results
if [ $? -eq 0 ]; then
    echo "✅ Temperature analysis completed successfully!"
    echo "📁 Results location: /users/PNS0496/badhon19/nist_am/IN718_singletrack/TimeTemp"
    echo "📊 Generated files:"
    ls -la /users/PNS0496/badhon19/nist_am/IN718_singletrack/TimeTemp/*.png 2>/dev/null || echo "No PNG files found"
    ls -la /users/PNS0496/badhon19/nist_am/IN718_singletrack/TimeTemp/*.csv 2>/dev/null || echo "No CSV files found"
else
    echo "❌ Temperature analysis failed!"
    exit 1
fi

echo "Job completed at: $(date)"
