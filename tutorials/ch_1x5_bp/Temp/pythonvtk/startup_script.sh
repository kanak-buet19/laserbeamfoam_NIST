#!/bin/bash

# Easy startup script for automated melt pool monitoring
# This script provides different modes of operation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default configuration
PROCESSOR_DIR="/users/PNS0496/badhon19/nist_am/ch06_5x5_bareplate/processor1"
VTK_DIR="/users/PNS0496/badhon19/nist_am/ch06_5x5_bareplate/testing/vtk"
RESULTS_DIR="./melt_pool_results"

show_help() {
    echo "Automated Melt Pool Analyzer - Startup Script"
    echo "============================================="
    echo ""
    echo "Usage: $0 [MODE] [OPTIONS]"
    echo ""
    echo "MODES:"
    echo "  auto        - Start automated monitoring (default)"
    echo "  manual      - Run single analysis on latest VTK file"
    echo "  test        - Test environment and dependencies"
    echo "  summary     - Generate summary report of existing results"
    echo "  submit      - Submit automated job to SLURM queue"
    echo ""
    echo "OPTIONS:"
    echo "  -h, --help           Show this help message"
    echo "  --processor-dir DIR  Set processor directory (default: $PROCESSOR_DIR)"
    echo "  --vtk-dir DIR        Set VTK directory (default: $VTK_DIR)"
    echo "  --results-dir DIR    Set results directory (default: $RESULTS_DIR)"
    echo "  --check-interval SEC Set monitoring check interval (default: 30)"
    echo "  --max-time HOURS     Set maximum runtime hours (default: 24)"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                   # Start automated monitoring"
    echo "  $0 manual            # Run single analysis"
    echo "  $0 test              # Test environment"
    echo "  $0 submit            # Submit to SLURM queue"
    echo "  $0 auto --check-interval 60 --max-time 48"
}

test_environment() {
    echo "Testing environment and dependencies..."
    echo ""
    
    # Check if required files exist
    echo "Checking required files..."
    if [ -f "automated_monitor.sh" ]; then
        echo "✓ automated_monitor.sh found"
    else
        echo "❌ automated_monitor.sh not found"
        return 1
    fi
    
    if [ -f "enhanced_vtk_analyzer.py" ]; then
        echo "✓ enhanced_vtk_analyzer.py found"
    elif [ -f "latest_vtk_analyzer.py" ]; then
        echo "✓ latest_vtk_analyzer.py found (will be used)"
    else
        echo "❌ VTK analyzer script not found"
        return 1
    fi
    
    # Check directories
    echo ""
    echo "Checking directories..."
    if [ -d "$PROCESSOR_DIR" ]; then
        echo "✓ Processor directory exists: $PROCESSOR_DIR"
        echo "  Contents: $(ls "$PROCESSOR_DIR" 2>/dev/null | wc -l) items"
    else
        echo "❌ Processor directory not found: $PROCESSOR_DIR"
        return 1
    fi
    
    if [ -d "$(dirname "$VTK_DIR")" ]; then
        echo "✓ VTK parent directory exists: $(dirname "$VTK_DIR")"
        if [ -d "$VTK_DIR" ]; then
            echo "✓ VTK directory exists: $VTK_DIR"
            vtk_count=$(ls "$VTK_DIR"/*.vtk "$VTK_DIR"/*.vtu "$VTK_DIR"/*.vti 2>/dev/null | wc -l)
            echo "  VTK files: $vtk_count"
        else
            echo "⚠ VTK directory will be created: $VTK_DIR"
        fi
    else
        echo "❌ VTK parent directory not found: $(dirname "$VTK_DIR")"
        return 1
    fi
    
    # Check recon_test
    recon_dir="/users/PNS0496/badhon19/nist_am/ch06_5x5_bareplate"
    if [ -f "$recon_dir/recon_test" ]; then
        echo "✓ recon_test found: $recon_dir/recon_test"
    else
        echo "❌ recon_test not found: $recon_dir/recon_test"
        return 1
    fi
    
    # Test Python and modules
    echo ""
    echo "Testing Python environment..."
    if command -v python &> /dev/null; then
        echo "✓ Python found: $(which python)"
        python_version=$(python --version 2>&1)
        echo "  Version: $python_version"
        
        # Test imports
        echo "Testing Python packages..."
        python -c "import sys; print(f'Python path: {sys.executable}')"
        
        packages=("numpy" "matplotlib" "scipy" "vtk")
        for pkg in "${packages[@]}"; do
            if python -c "import $pkg" 2>/dev/null; then
                version=$(python -c "import $pkg; print(getattr($pkg, '__version__', 'unknown'))" 2>/dev/null)
                echo "  ✓ $pkg: $version"
            else
                echo "  ❌ $pkg: not available"
            fi
        done
        
        # Test skimage
        if python -c "import skimage" 2>/dev/null; then
            version=$(python -c "import skimage; print(skimage.__version__)" 2>/dev/null)
            echo "  ✓ scikit-image: $version"
        else
            echo "  ❌ scikit-image: not available"
        fi
        
    else
        echo "❌ Python not found"
        return 1
    fi
    
    # Check SLURM
    echo ""
    echo "Checking SLURM environment..."
    if command -v sbatch &> /dev/null; then
        echo "✓ SLURM found: $(which sbatch)"
    else
        echo "⚠ SLURM not found (manual execution only)"
    fi
    
    echo ""
    echo "Environment test completed!"
    return 0
}

run_manual_analysis() {
    echo "Running manual analysis on latest VTK file..."
    
    # Create results directory
    mkdir -p "$RESULTS_DIR"
    
    # Choose which analyzer to use
    if [ -f "enhanced_vtk_analyzer.py" ]; then
        analyzer_script="enhanced_vtk_analyzer.py"
    else
        analyzer_script="latest_vtk_analyzer.py"
    fi
    
    python "$analyzer_script" \
        --vtk_dir "$VTK_DIR" \
        --output_dir "$RESULTS_DIR" \
        --z_slice 0.0003 \
        --y_reference -0.0003 \
        --threshold 1000
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "✓ Manual analysis completed successfully!"
        echo "Results saved to: $RESULTS_DIR"
    else
        echo "❌ Manual analysis failed"
        return 1
    fi
}

generate_summary() {
    echo "Generating summary report..."
    
    if [ -f "enhanced_vtk_analyzer.py" ]; then
        python enhanced_vtk_analyzer.py --output_dir "$RESULTS_DIR" --summary_report --quiet
    else
        echo "Enhanced analyzer not found. Listing existing results..."
        if [ -d "$RESULTS_DIR" ]; then
            echo "Results in $RESULTS_DIR:"
            ls -la "$RESULTS_DIR"/*.txt "$RESULTS_DIR"/*.json 2>/dev/null || echo "No result files found"
        else
            echo "No results directory found: $RESULTS_DIR"
        fi
    fi
}

submit_to_slurm() {
    echo "Submitting automated monitoring job to SLURM..."
    
    if ! command -v sbatch &> /dev/null; then
        echo "❌ SLURM not available. Use manual mode instead."
        return 1
    fi
    
    if [ ! -f "automated_monitor.sh" ]; then
        echo "❌ automated_monitor.sh not found"
        return 1
    fi
    
    # Make sure the script is executable
    chmod +x automated_monitor.sh
    
    # Submit job
    job_output=$(sbatch automated_monitor.sh 2>&1)
    
    if [ $? -eq 0 ]; then
        job_id=$(echo "$job_output" | grep -o '[0-9]\+')
        echo "✓ Job submitted successfully!"
        echo "Job ID: $job_id"
        echo ""
        echo "Monitor job status with: squeue -u $USER"
        echo "View output with: tail -f automated_monitor_${job_id}.out"
        echo "Cancel job with: scancel $job_id"
    else
        echo "❌ Job submission failed:"
        echo "$job_output"
        return 1
    fi
}

run_automated_monitoring() {
    local check_interval=30
    local max_hours=24
    
    echo "Starting automated monitoring (local execution)..."
    echo "Processor directory: $PROCESSOR_DIR"
    echo "VTK directory: $VTK_DIR"
    echo "Results directory: $RESULTS_DIR"
    echo "Check interval: ${check_interval}s"
    echo "Max runtime: ${max_hours}h"
    echo ""
    echo "Press Ctrl+C to stop monitoring"
    echo ""
    
    # Set up environment similar to the SLURM script
    export PYTHONPATH=""
    export PYTHON_PATH=""
    
    # Create results directory
    mkdir -p "$RESULTS_DIR"
    
    # Start monitoring (simplified version)
    local start_time=$(date +%s)
    local max_runtime=$((max_hours * 3600))
    local processed_log="$RESULTS_DIR/processed_files.log"
    touch "$processed_log"
    
    echo "Monitoring started at: $(date)"
    
    while true; do
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        
        if [ $elapsed_time -ge $max_runtime ]; then
            echo "Maximum runtime reached. Stopping."
            break
        fi
        
        # Check for new directories
        if [ -d "$PROCESSOR_DIR" ]; then
            new_dirs=($(ls -1 "$PROCESSOR_DIR" 2>/dev/null | grep -v '^0$\|^constant$' | sort))
            
            for dir in "${new_dirs[@]}"; do
                if ! grep -q "^$dir$" "$processed_log"; then
                    echo "[$(date)] New directory detected: $dir"
                    
                    # Run reconstruction
                    echo "[$(date)] Running reconstruction..."
                    cd "/users/PNS0496/badhon19/nist_am/ch06_5x5_bareplate"
                    if timeout 1800 ./recon_test > "$RESULTS_DIR/recon_${dir}_$(date +%s).log" 2>&1; then
                        echo "[$(date)] Reconstruction successful"
                        
                        # Wait and run analysis
                        sleep 5
                        cd "$SCRIPT_DIR"
                        
                        if [ -f "enhanced_vtk_analyzer.py" ]; then
                            analyzer="enhanced_vtk_analyzer.py"
                        else
                            analyzer="latest_vtk_analyzer.py"
                        fi
                        
                        echo "[$(date)] Running analysis..."
                        if python "$analyzer" --vtk_dir "$VTK_DIR" --output_dir "$RESULTS_DIR" --quiet; then
                            echo "[$(date)] Analysis successful for $dir"
                            echo "$dir" >> "$processed_log"
                        else
                            echo "[$(date)] Analysis failed for $dir"
                        fi
                    else
                        echo "[$(date)] Reconstruction failed for $dir"
                    fi
                fi
            done
        fi
        
        sleep $check_interval
    done
    
    echo "Automated monitoring completed at: $(date)"
}

# Parse command line arguments
MODE="auto"
CHECK_INTERVAL=30
MAX_HOURS=24

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        auto|manual|test|summary|submit)
            MODE="$1"
            shift
            ;;
        --processor-dir)
            PROCESSOR_DIR="$2"
            shift 2
            ;;
        --vtk-dir)
            VTK_DIR="$2"
            shift 2
            ;;
        --results-dir)
            RESULTS_DIR="$2"
            shift 2
            ;;
        --check-interval)
            CHECK_INTERVAL="$2"
            shift 2
            ;;
        --max-time)
            MAX_HOURS="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Execute based on mode
case $MODE in
    test)
        test_environment
        exit $?
        ;;
    manual)
        run_manual_analysis
        exit $?
        ;;
    summary)
        generate_summary
        exit $?
        ;;
    submit)
        submit_to_slurm
        exit $?
        ;;
    auto)
        run_automated_monitoring
        exit $?
        ;;
    *)
        echo "Invalid mode: $MODE"
        show_help
        exit 1
        ;;
esac