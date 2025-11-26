#!/usr/bin/env python
# Enhanced Temperature Analysis with Melt Line Analysis
# Tracks time above melting temperature (1571.15K)

import sys
import os
import glob
import numpy as np
import re
import locale
from pathlib import Path
from datetime import datetime
from scipy import interpolate

# Set UTF-8 encoding to handle special characters
os.environ['PYTHONIOENCODING'] = 'utf-8'
locale.setlocale(locale.LC_ALL, 'C')

# For HPC environments without display
import matplotlib
matplotlib.use('Agg')  # Use non-interactive backend

try:
    import matplotlib.pyplot as plt
    import pyvista as pv
    print("✅ All imports successful!")
except ImportError as e:
    print(f"❌ Import error: {e}")
    print("Installing missing packages...")
    os.system("python -m pip install --user pyvista matplotlib pandas numpy scipy")
    try:
        import matplotlib.pyplot as plt
        import pyvista as pv
        from scipy import interpolate
        print("✅ Packages installed and imported successfully!")
    except ImportError as e2:
        print(f"❌ Still failed after installation: {e2}")
        sys.exit(1)

# Melting temperature constant
MELT_TEMPERATURE = 1571.15  # Kelvin

def log_message(message):
    """Log message with timestamp"""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    try:
        print(f"[{timestamp}] {message}")
    except UnicodeEncodeError:
        safe_message = message.encode('ascii', errors='ignore').decode('ascii')
        print(f"[{timestamp}] {safe_message}")

def find_melt_line_crossings(time_data, temp_data, melt_temp=MELT_TEMPERATURE):
    """
    Find where temperature curve crosses the melt line
    Returns crossing times and calculates time above melt
    """
    log_message(f"🔍 Analyzing crossings with melt line at {melt_temp}K...")
    
    # Create interpolation function for smooth crossing detection
    if len(time_data) < 2:
        log_message("❌ Not enough data points for interpolation")
        return [], [], []
    
    # Sort data by time to ensure proper interpolation
    sorted_indices = np.argsort(time_data)
    sorted_time = time_data[sorted_indices]
    sorted_temp = temp_data[sorted_indices]
    
    # Create high-resolution interpolation
    time_interp = np.linspace(sorted_time[0], sorted_time[-1], len(sorted_time) * 10)
    temp_interp_func = interpolate.interp1d(sorted_time, sorted_temp, kind='linear', fill_value='extrapolate')
    temp_interp = temp_interp_func(time_interp)
    
    # Find crossings by looking for sign changes in (temp - melt_temp)
    diff = temp_interp - melt_temp
    crossings = []
    
    for i in range(len(diff) - 1):
        # Check for sign change (crossing)
        if (diff[i] <= 0 and diff[i+1] > 0) or (diff[i] > 0 and diff[i+1] <= 0):
            # Linear interpolation to find exact crossing time
            if diff[i+1] != diff[i]:  # Avoid division by zero
                crossing_time = time_interp[i] + (melt_temp - temp_interp[i]) * (time_interp[i+1] - time_interp[i]) / (temp_interp[i+1] - temp_interp[i])
                crossing_type = "up" if diff[i] <= 0 and diff[i+1] > 0 else "down"
                crossings.append((crossing_time, crossing_type))
    
    log_message(f"✅ Found {len(crossings)} crossings with melt line")
    
    # Calculate time above melt for each spike
    time_above_melt_periods = []
    
    # Pair up crossings (up crossing followed by down crossing)
    i = 0
    while i < len(crossings) - 1:
        current_crossing = crossings[i]
        next_crossing = crossings[i + 1]
        
        # Look for up-down pairs
        if current_crossing[1] == "up" and next_crossing[1] == "down":
            time_above = next_crossing[0] - current_crossing[0]
            time_above_melt_periods.append({
                'start_time': current_crossing[0],
                'end_time': next_crossing[0],
                'duration': time_above,
                'spike_number': len(time_above_melt_periods) + 1
            })
            log_message(f"🔥 Spike {len(time_above_melt_periods)}: {time_above:.4f} ms above melt (from {current_crossing[0]:.4f} to {next_crossing[0]:.4f})")
            i += 2  # Skip both crossings since we used them
        else:
            i += 1  # Move to next crossing
    
    crossing_times = [c[0] for c in crossings]
    crossing_types = [c[1] for c in crossings]
    
    return crossing_times, crossing_types, time_above_melt_periods

def extract_temperature_at_point(vtk_file_path, target_point):
    """Extract temperature at a specific point from a VTK file"""
    try:
        log_message(f"Processing: {os.path.basename(vtk_file_path)}")
        
        pv.set_error_output_file("vtk_errors.log")
        mesh = pv.read(vtk_file_path)
        
        if mesh is None:
            log_message(f"❌ Failed to load VTK data from {vtk_file_path}")
            return None
            
        target_point_m = [coord / 1000.0 for coord in target_point]
        closest_point_id = mesh.find_closest_point(target_point_m)
        
        point_data = mesh.point_data
        available_arrays = list(point_data.keys())
        
        temp_field_names = ['T', 'Temperature', 'temperature', 'TEMPERATURE', 'temp', 'Temp']
        temperature = None
        
        for field_name in temp_field_names:
            if field_name in point_data:
                temperature = point_data[field_name][closest_point_id]
                break
        
        if temperature is None:
            if available_arrays:
                first_field = available_arrays[0]
                temperature = point_data[first_field][closest_point_id]
            else:
                return None
            
        return float(temperature)
        
    except Exception as e:
        log_message(f"❌ Error reading {vtk_file_path}: {str(e)}")
        return None

def extract_timestep_from_filename(filename):
    """Extract timestep number from filename"""
    patterns = [
        r'test_small_(\d+)\.vtk',
        r'test_small_(\d+)\.vtu',
        r'test_small_(\d+)\.vti',
        r'(\d+)\.vtk',
        r'(\d+)\.vtu',
        r'(\d+)\.vti'
    ]
    
    for pattern in patterns:
        match = re.search(pattern, filename)
        if match:
            return int(match.group(1))
    
    return 0

def plot_temperature_history_with_melt_analysis(vtk_directory, target_point, file_pattern="test_small_*.vtk", output_dir=None):
    """
    Enhanced plot with melt line analysis
    """
    if output_dir is None:
        output_dir = os.getcwd()
    
    os.makedirs(output_dir, exist_ok=True)
    
    log_message(f"🔍 Searching for VTK files in: {vtk_directory}")
    
    # Find VTK files
    patterns = [file_pattern, "*.vtk", "*.vtu", "*.vti"]
    vtk_files = []
    
    for pattern in patterns:
        files = glob.glob(os.path.join(vtk_directory, pattern))
        vtk_files.extend(files)
    
    vtk_files = list(set(vtk_files))
    
    if not vtk_files:
        log_message(f"❌ No VTK files found")
        return None
    
    log_message(f"✅ Found {len(vtk_files)} VTK files")
    
    # Sort and process files
    vtk_files.sort(key=lambda x: extract_timestep_from_filename(os.path.basename(x)))
    
    timesteps = []
    temperatures = []
    
    log_message(f"🌡️ Extracting temperature data at point ({target_point[0]}, {target_point[1]}, {target_point[2]}) mm...")
    
    for vtk_file in vtk_files:
        timestep = extract_timestep_from_filename(os.path.basename(vtk_file))
        temperature = extract_temperature_at_point(vtk_file, target_point)
        
        if temperature is not None:
            timesteps.append(timestep)
            temperatures.append(temperature)
    
    if not temperatures:
        log_message("❌ No temperature data extracted")
        return None
    
    # Convert to arrays and time units
    timesteps = np.array(timesteps)
    temperatures = np.array(temperatures)
    time_milliseconds = timesteps * 1e-4  # Convert to milliseconds
    
    # **🔥 MELT LINE ANALYSIS 🔥**
    crossing_times, crossing_types, time_above_melt_periods = find_melt_line_crossings(time_milliseconds, temperatures)
    
    # Create enhanced plot
    plt.figure(figsize=(14, 10))
    
    # Main temperature curve
    plt.plot(time_milliseconds, temperatures, 'b-o', linewidth=2, markersize=3, label='Temperature', alpha=0.8)
    
    # **Add horizontal melt line**
    plt.axhline(y=MELT_TEMPERATURE, color='red', linestyle='--', linewidth=2, 
                label=f'Melt Temperature ({MELT_TEMPERATURE}K)', alpha=0.8)
    
    # Mark crossing points
    if crossing_times:
        crossing_temps = [MELT_TEMPERATURE] * len(crossing_times)
        up_times = [t for t, type_val in zip(crossing_times, crossing_types) if type_val == "up"]
        down_times = [t for t, type_val in zip(crossing_times, crossing_types) if type_val == "down"]
        
        plt.plot(up_times, [MELT_TEMPERATURE] * len(up_times), 'go', markersize=8, 
                label=f'Melt Start ({len(up_times)} points)', alpha=0.8)
        plt.plot(down_times, [MELT_TEMPERATURE] * len(down_times), 'ro', markersize=8, 
                label=f'Melt End ({len(down_times)} points)', alpha=0.8)
    
    # Highlight time above melt periods
    for period in time_above_melt_periods:
        plt.axvspan(period['start_time'], period['end_time'], alpha=0.3, color='orange', 
                   label=f'Above Melt' if period['spike_number'] == 1 else "")
    
    plt.xlabel('Time (milliseconds)', fontsize=12)
    plt.ylabel('Temperature (K)', fontsize=12)
    plt.title(f'Temperature History with Melt Analysis\nPoint ({target_point[0]}, {target_point[1]}, {target_point[2]}) mm', fontsize=14)
    plt.grid(True, alpha=0.3)
    plt.legend(bbox_to_anchor=(1.05, 1), loc='upper left')
    
    # Enhanced statistics box
    max_temp = np.max(temperatures)
    min_temp = np.min(temperatures)
    avg_temp = np.mean(temperatures)
    
    # Calculate melt analysis results
    total_crossings = len(crossing_times)
    total_spikes = len(time_above_melt_periods)
    if time_above_melt_periods:
        max_time_above_melt = max([p['duration'] for p in time_above_melt_periods])
        total_time_above_melt = sum([p['duration'] for p in time_above_melt_periods])
    else:
        max_time_above_melt = 0
        total_time_above_melt = 0
    
    stats_text = f'''Temperature Stats:
Max: {max_temp:.2f} K
Min: {min_temp:.2f} K  
Avg: {avg_temp:.2f} K

Melt Analysis:
Crossings: {total_crossings}
Spikes: {total_spikes}
Max Time Above Melt: {max_time_above_melt:.4f} ms
Total Time Above Melt: {total_time_above_melt:.4f} ms'''
    
    plt.text(0.02, 0.98, stats_text, transform=plt.gca().transAxes, verticalalignment='top',
             bbox=dict(boxstyle='round', facecolor='lightblue', alpha=0.8), fontsize=10)
    
    plt.tight_layout()
    
    # Save plot
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    plot_filename = os.path.join(output_dir, f"{timestamp}_melt_analysis_x{target_point[0]}_y{target_point[1]}_z{target_point[2]}.png")
    plt.savefig(plot_filename, dpi=300, bbox_inches='tight')
    plt.close()
    
    log_message(f"📊 Enhanced plot saved: {plot_filename}")
    
    # **🔥 MELT ANALYSIS SUMMARY 🔥**
    log_message(f"\n🔥 MELT LINE ANALYSIS RESULTS:")
    log_message(f"🌡️  Melt temperature: {MELT_TEMPERATURE}K")
    log_message(f"📊 Total crossings with melt line: {total_crossings}")
    log_message(f"🚀 Number of temperature spikes: {total_spikes}")
    
    if time_above_melt_periods:
        log_message(f"\n⏱️  Time above melt for each spike:")
        for i, period in enumerate(time_above_melt_periods, 1):
            log_message(f"   Spike {i}: {period['duration']:.4f} ms ({period['start_time']:.4f} - {period['end_time']:.4f})")
        
        log_message(f"\n🏆 HIGHEST TIME ABOVE MELT: {max_time_above_melt:.4f} ms")
        log_message(f"📈 Total cumulative time above melt: {total_time_above_melt:.4f} ms")
        
        # Find which spike had the maximum time above melt
        max_spike = max(time_above_melt_periods, key=lambda x: x['duration'])
        log_message(f"🥇 Peak spike: #{max_spike['spike_number']} with {max_spike['duration']:.4f} ms above melt")
    else:
        log_message(f"❄️  Temperature never exceeded melt point!")
    
    return time_milliseconds, temperatures, crossing_times, crossing_types, time_above_melt_periods

# Main execution
if __name__ == "__main__":
    vtk_directory = "/users/PNS0496/badhon19/nist_am/IN718_singletrack/testing/vtk"
    output_directory = "/users/PNS0496/badhon19/nist_am/IN718_singletrack/TimeTemp"
    target_coordinates = (0.26, -0.3, 0.5)  # x, y, z in mm
    file_pattern = "test_small_*.vtk"
    
    log_message("🚀 Enhanced Temperature Analysis with Melt Line Analysis Starting...")
    log_message(f"🔥 Melt temperature set to: {MELT_TEMPERATURE}K")
    
    os.makedirs(output_directory, exist_ok=True)
    
    if not os.path.exists(vtk_directory):
        log_message(f"❌ VTK directory not found: {vtk_directory}")
        sys.exit(1)
    
    # Run enhanced analysis
    result = plot_temperature_history_with_melt_analysis(vtk_directory, target_coordinates, file_pattern, output_directory)
    
    if result is not None:
        time_ms, temperatures, crossing_times, crossing_types, melt_periods = result
        
        # Save enhanced CSV with melt analysis
        try:
            import pandas as pd
            
            # Main temperature data
            df_temp = pd.DataFrame({
                'time_milliseconds': time_ms,
                'temperature_K': temperatures,
                'above_melt': temperatures > MELT_TEMPERATURE
            })
            
            # Melt analysis data
            df_melt = pd.DataFrame([
                {
                    'spike_number': p['spike_number'],
                    'start_time_ms': p['start_time'],
                    'end_time_ms': p['end_time'],
                    'duration_ms': p['duration']
                }
                for p in melt_periods
            ])
            
            # Save main data
            csv_filename = os.path.join(output_directory, f"enhanced_temp_analysis_x{target_coordinates[0]}_y{target_coordinates[1]}_z{target_coordinates[2]}.csv")
            df_temp.to_csv(csv_filename, index=False)
            
            # Save melt analysis data
            if not df_melt.empty:
                melt_csv = os.path.join(output_directory, f"melt_analysis_x{target_coordinates[0]}_y{target_coordinates[1]}_z{target_coordinates[2]}.csv")
                df_melt.to_csv(melt_csv, index=False)
                log_message(f"✅ Melt analysis CSV saved: {melt_csv}")
            
            log_message(f"✅ Enhanced CSV data saved: {csv_filename}")
            
        except ImportError:
            # Basic CSV fallback
            csv_filename = os.path.join(output_directory, f"enhanced_temp_analysis_x{target_coordinates[0]}_y{target_coordinates[1]}_z{target_coordinates[2]}.csv")
            with open(csv_filename, 'w') as f:
                f.write("time_milliseconds,temperature_K,above_melt\n")
                for t, temp in zip(time_ms, temperatures):
                    above_melt = "True" if temp > MELT_TEMPERATURE else "False"
                    f.write(f"{t:.6f},{temp:.6f},{above_melt}\n")
            log_message(f"✅ Basic CSV saved: {csv_filename}")
        
        log_message("🎉 Enhanced temperature analysis with melt line completed successfully!")
    else:
        log_message("❌ Enhanced temperature analysis failed!")
        sys.exit(1)
