#!/bin/bash
#SBATCH --job-name=khorasani_100um
#SBATCH --time=144:00:00
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=96
#SBATCH --account=PNS0496
#SBATCH --output=particle_100_%j.out
#SBATCH --error=particle_100_%j.err
#SBATCH --mail-type=END,FAIL,TIME_LIMIT
#SBATCH --mail-user=badhonmondol44@gmail.com

# Change to the job directory
cd $SLURM_SUBMIT_DIR

# Clean any inherited MPI settings
module purge
unset OMPI_MCA_*
unset MPI_HOME

# Load GCC 13.2.0
module load gcc/13.2.0
module unload mvapich 2>/dev/null || true

# Point to your local OpenMPI install
export PATH="$HOME/openmpi/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/openmpi/lib:$LD_LIBRARY_PATH"

# Source OpenFOAM
export WM_PROJECT_DIR=$HOME/OpenFOAM/OpenFOAM-10
source "$WM_PROJECT_DIR/etc/bashrc"
export FOAM_SIGFPE=0

# Verify setup
echo "=== Environment Check ==="
gcc --version | head -1
which mpirun
mpirun --version | head -1
echo "========================"

# Source tutorial run functions
. $WM_PROJECT_DIR/bin/tools/RunFunctions

echo "Job started at: $(date)"
echo "Running on node: $(hostname)"
echo "Job ID: $SLURM_JOB_ID"
echo "Number of tasks: $SLURM_NTASKS"

# --- Logic to handle first run vs. restart ---
# Check if the 'processor0' directory exists. If it does NOT, then this is the first run.
if [ ! -d "processor0" ]; then
    echo "This is the first run. Performing initial setup..."
    
    echo "Copying 'initial' to 0"
    cp -r initial 0
    
    echo "Running blockMesh"
    runApplication blockMesh
    
    echo "Running setSolidFraction"
    runApplication setSolidFraction
    
    echo "Running transformPoints with rotation"
    runApplication transformPoints "rotate=((0 1 0) (0 0 1))"
    
    echo "Decomposing domain for parallel run"
    runApplication decomposePar
    
    # Verify decomposition succeeded
    if [ ! -d "processor0" ]; then
        echo "ERROR: decomposePar failed! Exiting."
        exit 1
    fi
else
    echo "Restarting from latest time. Skipping initial setup."
fi

# --- Main Simulation Run ---
echo "Starting parallel laserbeamFoam simulation with $SLURM_NTASKS cores"
mpirun -np $SLURM_NTASKS laserbeamFoam -parallel

# Capture the exit status of the solver
solver_exit_code=$?
echo "Solver finished with exit code: $solver_exit_code"

# --- MODIFICATION: Automated Post-Processing on Successful Completion ---
# Get the configured endTime from controlDict
endTime=$(foamDictionary system/controlDict -entry endTime -value 2>/dev/null)
echo "Configured endTime: $endTime"

# Get the latest time directory created by the solver in processor directories
latestTime=$(foamListTimes -processor -latestTime 2>/dev/null)
echo "Latest time in processor directories: $latestTime"

# Check if we have valid values
if [ -z "$endTime" ] || [ -z "$latestTime" ]; then
    echo "WARNING: Could not read endTime or latestTime. Skipping post-processing."
    echo "Job completed at: $(date)"
    exit 0
fi

# Get the deltaT for tolerance calculation
deltaT=$(foamDictionary system/controlDict -entry deltaT -value 2>/dev/null)
if [ -z "$deltaT" ]; then
    deltaT=1e-6  # Fallback to small value
fi
tolerance=$(awk -v dt="$deltaT" 'BEGIN {printf "%.10e", dt / 2}')

echo "Using tolerance: $tolerance"

# Check if the simulation is complete using awk for floating point comparison
simulation_complete=$(awk -v latest="$latestTime" -v end="$endTime" -v tol="$tolerance" \
    'BEGIN {
        diff = end - latest
        if (latest >= end || diff < tol) {
            print "yes"
        } else {
            print "no"
        }
    }')

echo "Simulation complete check: $simulation_complete (latestTime=$latestTime, endTime=$endTime)"

if [ "$simulation_complete" = "yes" ]; then
    echo "Simulation has reached endTime. Running automatic post-processing..."
    
    echo "Reconstructing fields from parallel run"
    reconstructPar
    
    if [ $? -eq 0 ]; then
        echo "Reconstruction successful. Converting to VTK format"
        foamToVTK
        
        if [ $? -eq 0 ]; then
            echo "Post-processing completed successfully!"
        else
            echo "WARNING: foamToVTK failed!"
        fi
    else
        echo "WARNING: reconstructPar failed!"
    fi
else
    echo "Simulation did not reach endTime ($latestTime < $endTime)."
    echo "This is likely due to walltime limit. Skipping post-processing."
    echo "You can restart this job to continue the simulation."
fi

echo "Job completed at: $(date)"