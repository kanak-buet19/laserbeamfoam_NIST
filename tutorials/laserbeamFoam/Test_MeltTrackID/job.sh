#!/bin/bash
#SBATCH --job-name=5x5_160um
#SBATCH --time=12:00:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=96
#SBATCH --account=PNS0496
#SBATCH --output=particle_5x5_%j.out
#SBATCH --error=particle_5x5_%j.err

# Change to the job directory
cd $SLURM_SUBMIT_DIR

# Clean any inherited MPI settings

module purge

unset OMPI_MCA_*

unset MPI_HOME



# Load the same Intel version used to compile OpenMPI

module load intel/2021.10.0



# Point to your local OpenMPI install

export PATH="$HOME/openmpi/bin:$PATH"

export LD_LIBRARY_PATH="$HOME/openmpi/lib:$LD_LIBRARY_PATH"



# Add the correct Intel library path (2021.10.0 version)

export LD_LIBRARY_PATH="/apps/spack/0.21/cardinal/linux-rhel9-sapphirerapids/intel-oneapi-compilers-classic/gcc/11.3.1/2021.10.0-6xj4c3p/compiler/lib/intel64:$LD_LIBRARY_PATH"



# Source OpenFOAM

export WM_PROJECT_DIR=$HOME/OpenFOAM/OpenFOAM-10

source "$WM_PROJECT_DIR/etc/bashrc"

export FOAM_SIGFPE=0

# Verify it's picking your local mpirun
which mpirun
mpirun --version

# Source tutorial run functions
. $WM_PROJECT_DIR/bin/tools/RunFunctions

echo "Job started at: $(date)"
echo "Running on node: $(hostname)"
echo "Job ID: $SLURM_JOB_ID"
echo "Number of tasks: $SLURM_NTASKS"

echo "Copying 'initial' to 0"
cp -r initial 0

echo "Running blockMesh"
runApplication blockMesh

echo "Running setSolidFraction"
runApplication setSolidFraction

echo "Running transformPoints with rotation"
runApplication transformPoints "rotate=((0 1 0) (0 0 1))"

echo "Decomposing domain for parallel run"
decomposePar

echo "Starting parallel laserbeamFoam simulation with $SLURM_NTASKS cores"
mpirun -np $SLURM_NTASKS laserbeamFoam -parallel

echo "Reconstructing fields from parallel run"
reconstructPar

echo "Converting to VTK format"
foamToVTK -useTimeName 

echo "Job completed at: $(date)"