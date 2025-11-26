#!/bin/bash
#SBATCH --job-name=automated_melt_pool_monitor
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=24:00:00
#SBATCH --output=automated_monitor_%j.out
#SBATCH --error=automated_monitor_%j.err
#SBATCH --account=PNS0496

echo "Starting automated melt pool monitoring system..."
echo "Job ID: $SLURM_JOB_ID"
echo "Date: $(date)"
echo "User: $USER"
echo "Submit directory: $SLURM_SUBMIT_DIR"

# Configuration
PROCESSOR_DIR="/users/PNS0496/badhon19/nist_am/ch06_5x5_bareplate/processor1"
RECON_DIR="/users/PNS0496/badhon19/nist_am/ch06_5x5_bareplate"
VTK_DIR="/users/PNS0496/badhon19/nist_am/ch06_5x5_bareplate/testing/vtk"
RESULTS_DIR="$SLURM_SUBMIT_DIR/melt_pool_results_automated"  # Use absolute path
RECON_EXECUTABLE="./recon_test"
CHECK_INTERVAL=30  # seconds between checks
MAX_RUNTIME=86400  # Maximum runtime in seconds (24 hours)

# Analysis parameters
Z_SLICE=0.00046
Y_REFERENCE=-0.0003
THRESHOLD=1000

# Create results directory with absolute path
mkdir -p "$RESULTS_DIR"
echo "Results directory created: $RESULTS_DIR"

# Log file for tracking processed files
PROCESSED_LOG="$RESULTS_DIR/processed_files.log"
touch "$PROCESSED_LOG"

# Function to log messages with timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$RESULTS_DIR/monitoring.log"
}

# Function to check if file is new (not in processed log)
is_new_file() {
    local file_path="$1"
    local file_basename=$(basename "$file_path")
    if grep -q "^$file_basename$" "$PROCESSED_LOG"; then
        return 1  # File already processed
    else
        return 0  # File is new
    fi
}

# Function to mark file as processed
mark_as_processed() {
    local file_path="$1"
    local file_basename=$(basename "$file_path")
    echo "$file_basename" >> "$PROCESSED_LOG"
    log_message "Marked as processed: $file_basename"
}

# Function to run reconstruction - FIXED VERSION
run_reconstruction() {
    local current_dir=$(pwd)
    log_message "Running reconstruction from directory: $RECON_DIR"
    
    # CRITICAL FIX: Change to correct directory
    cd "$RECON_DIR" || {
        log_message "ERROR: Cannot change to reconstruction directory: $RECON_DIR"
        return 1
    }
    
    # Check if recon_test exists
    if [ ! -f "$RECON_EXECUTABLE" ]; then
        log_message "ERROR: $RECON_EXECUTABLE not found in $RECON_DIR"
        cd "$current_dir"
        return 1
    fi
    
    # Create log file with absolute path
    local recon_log="$RESULTS_DIR/recon_output_$(date +%s).log"
    
    log_message "Running: $RECON_EXECUTABLE from $(pwd)"
    log_message "Output log: $recon_log"
    
    # Run reconstruction with timeout (30 minutes max)
    timeout 1800 "$RECON_EXECUTABLE" > "$recon_log" 2>&1
    local recon_exit_code=$?
    
    # Return to original directory
    cd "$current_dir"
    
    if [ $recon_exit_code -eq 0 ]; then
        log_message "Reconstruction completed successfully"
        return 0
    elif [ $recon_exit_code -eq 124 ]; then
        log_message "ERROR: Reconstruction timed out after 30 minutes"
        log_message "Check log: $recon_log"
        return 1
    else
        log_message "ERROR: Reconstruction failed with exit code $recon_exit_code"
        log_message "Check log: $recon_log"
        # Show last few lines of error for immediate feedback
        log_message "Last 5 lines of reconstruction log:"
        tail -5 "$recon_log" 2>/dev/null | while read line; do
            log_message "  $line"
        done
        return 1
    fi
}

# Function to run analysis - FIXED VERSION
run_analysis() {
    local current_dir=$(pwd)
    log_message "Running melt pool analysis from: $SLURM_SUBMIT_DIR"
    
    # Change to submit directory where Python scripts are
    cd "$SLURM_SUBMIT_DIR" || {
        log_message "ERROR: Cannot change to submit directory: $SLURM_SUBMIT_DIR"
        return 1
    }
    
    # Check if analyzer exists
    local analyzer_script=""
    if [ -f "enhanced_analyzer.py" ]; then
        analyzer_script="enhanced_analyzer.py"
    elif [ -f "enhanced_vtk_analyzer.py" ]; then
        analyzer_script="enhanced_vtk_analyzer.py"
    elif [ -f "latest_vtk_analyzer.py" ]; then
        analyzer_script="latest_vtk_analyzer.py"
    else
        log_message "ERROR: No analyzer script found in $SLURM_SUBMIT_DIR"
        cd "$current_dir"
        return 1
    fi
    
    log_message "Using analyzer: $analyzer_script"
    
    # Create analysis log with absolute path
    local analysis_log="$RESULTS_DIR/analysis_output_$(date +%s).log"
    
    # Run analysis with absolute paths
    python "$analyzer_script" \
        --vtk_dir "$VTK_DIR" \
        --output_dir "$RESULTS_DIR" \
        --z_slice "$Z_SLICE" \
        --y_reference "$Y_REFERENCE" \
        --threshold "$THRESHOLD" \
        --quiet > "$analysis_log" 2>&1
    
    local analysis_exit_code=$?
    
    # Return to original directory
    cd "$current_dir"
    
    if [ $analysis_exit_code -eq 0 ]; then
        log_message "Analysis completed successfully"
        log_message "Analysis log: $analysis_log"
        return 0
    else
        log_message "ERROR: Analysis failed with exit code $analysis_exit_code"
        log_message "Check log: $analysis_log"
        # Show last few lines of error for immediate feedback
        log_message "Last 5 lines of analysis log:"
        tail -5 "$analysis_log" 2>/dev/null | while read line; do
            log_message "  $line"
        done
        return 1
    fi
}

# Function to get numerical part of directory name for sorting
get_numeric_value() {
    local dirname="$1"
    # Extract number from scientific notation (e.g., 5e-05 -> 0.00005)
    if [[ $dirname =~ ^[0-9]+\.?[0-9]*e-[0-9]+$ ]]; then
        # Use Python to convert scientific notation to decimal
        python -c "print(float('$dirname'))" 2>/dev/null || echo "0"
    elif [[ $dirname =~ ^[0-9]+\.?[0-9]*$ ]]; then
        echo "$dirname"
    else
        echo "0"
    fi
}

# Setup environment (same as before but with better logging)
setup_environment() {
    log_message "Setting up environment..."
    log_message "Current working directory: $(pwd)"
    log_message "Submit directory: $SLURM_SUBMIT_DIR"
    log_message "Results directory: $RESULTS_DIR"
    
    # Clear any existing environment
    unset PYTHONPATH
    unset PYTHON_PATH
    
    # Load system modules
    module purge
    
    # Load Python
    if module load python/3.12; then
        log_message "Loaded python/3.12"
    elif module load python/3.11; then
        log_message "Loaded python/3.11"  
    elif module load python/3.10; then
        log_message "Loaded python/3.10"
    elif module load python; then
        log_message "Loaded default python"
    else
        log_message "WARNING: Could not load python module"
    fi
    
    # Try to load scientific computing modules if available
    if module load scipy-stack 2>/dev/null; then
        log_message "scipy-stack loaded"
    else
        log_message "scipy-stack not available"
    fi
    
    if module load vtk 2>/dev/null; then
        log_message "VTK module loaded"
    else
        log_message "VTK module not available"
    fi
    
    # Test and install missing packages
    log_message "Checking required packages..."
    missing_packages=""
    
    python -c "import vtk" 2>/dev/null || missing_packages="$missing_packages vtk"
    python -c "import numpy" 2>/dev/null || missing_packages="$missing_packages numpy"
    python -c "import matplotlib" 2>/dev/null || missing_packages="$missing_packages matplotlib"
    python -c "import scipy" 2>/dev/null || missing_packages="$missing_packages scipy"
    python -c "import skimage" 2>/dev/null || missing_packages="$missing_packages scikit-image"
    
    if [ -n "$missing_packages" ]; then
        log_message "Installing missing packages:$missing_packages"
        python -m pip install --user --upgrade pip
        python -m pip install --user $missing_packages
    else
        log_message "All required packages available"
    fi
    
    log_message "Environment setup completed"
}

# Main monitoring function with better error handling
monitor_and_process() {
    local start_time=$(date +%s)
    local last_file_count=0
    
    log_message "Starting monitoring of $PROCESSOR_DIR"
    
    # Check if processor directory exists
    if [ ! -d "$PROCESSOR_DIR" ]; then
        log_message "ERROR: Processor directory not found: $PROCESSOR_DIR"
        exit 1
    fi
    
    log_message "Initial files found: $(ls -la "$PROCESSOR_DIR" 2>/dev/null | wc -l)"
    
    while true; do
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        
        # Check if maximum runtime exceeded
        if [ $elapsed_time -ge $MAX_RUNTIME ]; then
            log_message "Maximum runtime reached. Stopping monitoring."
            break
        fi
        
        # Get all directories except 0 and constant, sorted by numeric value
        new_dirs=($(ls -1 "$PROCESSOR_DIR" 2>/dev/null | grep -v '^0$\|^constant$' | while read dir; do
            if [ -d "$PROCESSOR_DIR/$dir" ]; then
                numeric_val=$(get_numeric_value "$dir")
                echo "$numeric_val $dir"
            fi
        done | sort -n | cut -d' ' -f2))
        
        current_file_count=${#new_dirs[@]}
        
        if [ $current_file_count -gt $last_file_count ]; then
            log_message "New directory detected! Total directories: $current_file_count"
            log_message "Directories found: ${new_dirs[*]}"
            
            # Process each new directory
            for dir in "${new_dirs[@]}"; do
                if is_new_file "$dir"; then
                    log_message "Processing new directory: $dir"
                    
                    # Check if directory has content
                    dir_content=$(ls -la "$PROCESSOR_DIR/$dir" 2>/dev/null | wc -l)
                    log_message "Directory $dir contains $dir_content items"
                    
                    # Run reconstruction
                    if run_reconstruction; then
                        log_message "Reconstruction successful for $dir"
                        
                        # Wait a bit for VTK file to be fully written
                        sleep 5
                        
                        # Check if VTK files were created
                        vtk_count=$(ls "$VTK_DIR"/*.vtk "$VTK_DIR"/*.vtu "$VTK_DIR"/*.vti 2>/dev/null | wc -l)
                        log_message "VTK files found after reconstruction: $vtk_count"
                        
                        # Run analysis
                        if run_analysis; then
                            log_message "Analysis successful for $dir"
                            mark_as_processed "$dir"
                        else
                            log_message "Analysis failed for $dir"
                        fi
                    else
                        log_message "Reconstruction failed for $dir"
                    fi
                else
                    log_message "Directory $dir already processed, skipping"
                fi
            done
            
            last_file_count=$current_file_count
        else
            # Print status every 10 minutes
            if [ $((elapsed_time % 600)) -eq 0 ] && [ $elapsed_time -gt 0 ]; then
                log_message "Monitoring... Runtime: ${elapsed_time}s, Directories: $current_file_count"
            fi
        fi
        
        sleep $CHECK_INTERVAL
    done
}

# Main execution
log_message "=== AUTOMATED MELT POOL MONITORING STARTED ==="
log_message "Configuration:"
log_message "  Processor directory: $PROCESSOR_DIR"
log_message "  Reconstruction directory: $RECON_DIR"
log_message "  VTK directory: $VTK_DIR"
log_message "  Results directory: $RESULTS_DIR"
log_message "  Check interval: ${CHECK_INTERVAL}s"
log_message "  Max runtime: ${MAX_RUNTIME}s ($(($MAX_RUNTIME/3600))h)"

# Verify critical paths
if [ ! -d "$PROCESSOR_DIR" ]; then
    log_message "ERROR: Processor directory does not exist: $PROCESSOR_DIR"
    exit 1
fi

if [ ! -d "$RECON_DIR" ]; then
    log_message "ERROR: Reconstruction directory does not exist: $RECON_DIR"
    exit 1
fi

if [ ! -f "$RECON_DIR/$RECON_EXECUTABLE" ]; then
    log_message "ERROR: Reconstruction executable not found: $RECON_DIR/$RECON_EXECUTABLE"
    exit 1
fi

# Setup environment
setup_environment

# Start monitoring
monitor_and_process

log_message "=== AUTOMATED MONITORING COMPLETED ==="
echo "Monitoring completed at: $(date)"
echo "Results saved in: $RESULTS_DIR"
echo "Check monitoring.log for detailed logs"