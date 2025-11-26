# Enhanced HPC-compatible melt pool analyzer with automation support
# FIXED: Encoding issues and improved error handling for VTK processing
# Modified to work better with automated monitoring system
# ADDED: Bead height measurement functionality

import sys
import os
import glob
import argparse
import time
import json
import locale
from pathlib import Path
from datetime import datetime

# Set UTF-8 encoding to handle special characters
os.environ['PYTHONIOENCODING'] = 'utf-8'
locale.setlocale(locale.LC_ALL, 'C')

# For HPC environments without display
import matplotlib
matplotlib.use('Agg')  # Use non-interactive backend

try:
    import vtk
    import numpy as np
    from vtk.util.numpy_support import vtk_to_numpy
    import matplotlib.pyplot as plt
    from scipy import ndimage
    from skimage import measure
    print("All imports successful!")
except ImportError as e:
    print(f"Import error: {e}")
    print("Please install missing packages:")
    print("pip install vtk numpy matplotlib scipy scikit-image")
    sys.exit(1)

class NumpyEncoder(json.JSONEncoder):
    """Custom JSON encoder for numpy types"""
    def default(self, obj):
        if isinstance(obj, np.integer):
            return int(obj)
        elif isinstance(obj, np.floating):
            return float(obj)
        elif isinstance(obj, np.ndarray):
            return obj.tolist()
        return super(NumpyEncoder, self).default(obj)

class EnhancedMeltPoolAnalyzer:
    def __init__(self, vtk_file_path, verbose=True):
        self.vtk_file_path = vtk_file_path
        self.reader = None
        self.data = None
        self.verbose = verbose
        
    def log(self, message):
        """Log message with timestamp if verbose mode is on"""
        if self.verbose:
            timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            try:
                print(f"[{timestamp}] {message}")
            except UnicodeEncodeError:
                # If there are encoding issues, print without special characters
                safe_message = message.encode('ascii', errors='ignore').decode('ascii')
                print(f"[{timestamp}] {safe_message}")
        
    def load_vtk_file(self):
        """Load VTK file and extract data with proper error handling"""
        try:
            # Set VTK to handle encoding issues
            vtk.vtkObject.GlobalWarningDisplayOff()
            
            if self.vtk_file_path.endswith('.vtu'):
                self.reader = vtk.vtkXMLUnstructuredGridReader()
            elif self.vtk_file_path.endswith('.vtk'):
                self.reader = vtk.vtkUnstructuredGridReader()
            elif self.vtk_file_path.endswith('.vti'):
                self.reader = vtk.vtkXMLImageDataReader()
            else:
                raise ValueError("Unsupported file format. Use .vtk, .vtu, or .vti")
            
            # Set file name with proper error handling
            try:
                self.reader.SetFileName(self.vtk_file_path.encode('utf-8').decode('utf-8'))
            except (UnicodeDecodeError, UnicodeEncodeError):
                # If encoding issues, try with the original path
                self.reader.SetFileName(self.vtk_file_path)
            
            # Update reader with error checking
            self.reader.Update()
            
            # Check if reader has errors
            if self.reader.GetErrorCode() != 0:
                raise RuntimeError(f"VTK reader error code: {self.reader.GetErrorCode()}")
            
            self.data = self.reader.GetOutput()
            
            if self.data is None:
                raise RuntimeError("Failed to load VTK data - output is None")
            
            self.log(f"Loaded VTK file: {os.path.basename(self.vtk_file_path)}")
            self.log(f"Number of points: {self.data.GetNumberOfPoints()}")
            self.log(f"Number of cells: {self.data.GetNumberOfCells()}")
            
            # List available arrays with safe handling
            point_data = self.data.GetPointData()
            self.log(f"Available point data arrays:")
            for i in range(point_data.GetNumberOfArrays()):
                try:
                    array_name = point_data.GetArrayName(i)
                    if array_name is None:
                        array_name = f"Array_{i}"
                    array = point_data.GetArray(i)
                    if array is not None:
                        self.log(f"  - {array_name}: {array.GetNumberOfTuples()} values")
                    else:
                        self.log(f"  - {array_name}: No data")
                except Exception as e:
                    self.log(f"  - Array {i}: Error reading ({str(e)})")
                    
        except Exception as e:
            raise RuntimeError(f"Failed to load VTK file {self.vtk_file_path}: {str(e)}")
    
    def get_available_arrays(self):
        """Get list of available data arrays with error handling"""
        if self.data is None:
            self.load_vtk_file()
            
        arrays = []
        point_data = self.data.GetPointData()
        for i in range(point_data.GetNumberOfArrays()):
            try:
                array_name = point_data.GetArrayName(i)
                if array_name is not None:
                    arrays.append(array_name)
                else:
                    arrays.append(f"Array_{i}")
            except:
                arrays.append(f"Array_{i}")
        return arrays
    
    def convert_to_structured_grid(self, array_name, grid_resolution=(100, 100, 50)):
        """Convert unstructured grid to structured grid with improved error handling"""
        if self.data is None:
            self.load_vtk_file()
        
        try:
            bounds = self.data.GetBounds()
            self.log(f"Data bounds: x=[{bounds[0]:.6f}, {bounds[1]:.6f}], "
                    f"y=[{bounds[2]:.6f}, {bounds[3]:.6f}], "
                    f"z=[{bounds[4]:.6f}, {bounds[5]:.6f}]")
            
            x_res, y_res, z_res = grid_resolution
            x = np.linspace(bounds[0], bounds[1], x_res)
            y = np.linspace(bounds[2], bounds[3], y_res)
            z = np.linspace(bounds[4], bounds[5], z_res)
            
            # Create probe filter with error handling
            probe = vtk.vtkProbeFilter()
            
            # Create image data
            image_data = vtk.vtkImageData()
            image_data.SetDimensions(x_res, y_res, z_res)
            image_data.SetOrigin(bounds[0], bounds[2], bounds[4])
            image_data.SetSpacing((bounds[1]-bounds[0])/(x_res-1),
                                 (bounds[3]-bounds[2])/(y_res-1),
                                 (bounds[5]-bounds[4])/(z_res-1))
            
            probe.SetInputData(image_data)
            probe.SetSourceData(self.data)
            
            # Update with error checking
            probe.Update()
            
            result = probe.GetOutput()
            if result is None:
                raise RuntimeError("Probe filter returned None")
            
            # Try to get array data
            array_data = result.GetPointData().GetArray(array_name)
            
            if array_data is None:
                # Try alternative array names or indices
                available_arrays = self.get_available_arrays()
                self.log(f"Array '{array_name}' not found. Available arrays: {available_arrays}")
                
                # Try to find array by partial name match
                for arr_name in available_arrays:
                    if array_name.lower() in arr_name.lower() or arr_name.lower() in array_name.lower():
                        self.log(f"Using array '{arr_name}' instead of '{array_name}'")
                        array_data = result.GetPointData().GetArray(arr_name)
                        break
                
                if array_data is None:
                    # Use the first available array
                    if available_arrays:
                        first_array = available_arrays[0]
                        self.log(f"Using first available array '{first_array}' instead of '{array_name}'")
                        array_data = result.GetPointData().GetArray(first_array)
                    
                if array_data is None:
                    raise ValueError(f"No suitable array found. Requested: '{array_name}', Available: {available_arrays}")
            
            np_array = vtk_to_numpy(array_data)
            if np_array is None:
                raise RuntimeError("Failed to convert VTK array to numpy")
            
            structured_data = np_array.reshape((z_res, y_res, x_res))
            
            return structured_data, (x, y, z)
            
        except Exception as e:
            raise RuntimeError(f"Failed to convert to structured grid: {str(e)}")
    
    def analyze_melt_pool_xy_plane(self, array_name='meltHistory', z_slice=0.46e-3, 
                                   y_reference=-0.3e-3, threshold=1000, 
                                   grid_resolution=(200, 200, 100)):
        """Analyze melt pool in XY plane with comprehensive error handling and bead height measurement"""
        try:
            self.log(f"Starting analysis with array: {array_name}")
            
            data_3d, coords = self.convert_to_structured_grid(array_name, grid_resolution)
            x, y, z = coords
            
            self.log(f"Data shape: {data_3d.shape} (z, y, x)")
            self.log(f"Data range: [{np.min(data_3d):.3f}, {np.max(data_3d):.3f}]")
            
            # Find closest Z index
            z_idx = np.argmin(np.abs(z - z_slice))
            actual_z = z[z_idx]
            self.log(f"Analyzing XY plane at Z = {actual_z:.6f} m")
            
            # Extract XY slice
            xy_slice = data_3d[z_idx, :, :]
            
            # Find Y reference index
            y_ref_idx = np.argmin(np.abs(y - y_reference))
            actual_y_ref = y[y_ref_idx]
            
            # Measure width
            width_profile = xy_slice[y_ref_idx, :]
            width_mask = width_profile > threshold
            
            if np.any(width_mask):
                x_indices = np.where(width_mask)[0]
                width_start_x = x[np.min(x_indices)]
                width_end_x = x[np.max(x_indices)]
                width = width_end_x - width_start_x
            else:
                width = 0
                width_start_x = width_end_x = actual_y_ref
            
            # Measure depth (existing functionality)
            depth_found = False
            depth_end_y = y_reference
            
            for i in range(y_ref_idx, len(y)):
                current_y = y[i]
                y_profile = xy_slice[i, :]
                if not np.any(y_profile > threshold):
                    depth_end_y = current_y
                    depth_found = True
                    break
            
            if not depth_found:
                depth_end_y = y[-1]
            
            depth = abs(y_reference - depth_end_y)
            
            # Measure bead height (NEW FUNCTIONALITY)
            height_found = False
            height_end_y = y_reference
            
            # Search upward from reference line (decreasing index since y decreases with index)
            for i in range(y_ref_idx, -1, -1):
                current_y = y[i]
                y_profile = xy_slice[i, :]
                if not np.any(y_profile > threshold):
                    height_end_y = current_y
                    height_found = True
                    break
            
            if not height_found:
                height_end_y = y[0]  # Top of the domain
            
            height = abs(y_reference - height_end_y)
            
            self.log(f"Bead height measurement:")
            self.log(f"  Reference Y: {actual_y_ref*1000:.3f} mm")
            self.log(f"  Height end Y: {height_end_y*1000:.3f} mm")
            self.log(f"  Height: {height*1000:.3f} mm")
            
            # Calculate center of mass
            melted_mask = xy_slice > threshold
            if np.any(melted_mask):
                y_indices, x_indices = np.where(melted_mask)
                center_x = np.mean(x[x_indices])
                center_y = np.mean(y[y_indices])
                area = np.sum(melted_mask) * (x[1] - x[0]) * (y[1] - y[0])
            else:
                center_x = center_y = area = 0
            
            # Get file timestamp
            file_stat = os.stat(self.vtk_file_path)
            file_mtime = datetime.fromtimestamp(file_stat.st_mtime)
            
            results = {
                'width': float(width),
                'depth': float(depth),
                'height': float(height),  # NEW: Bead height
                'area': float(area),
                'center_x': float(center_x),
                'center_y': float(center_y),
                'z_slice': float(actual_z),
                'y_reference': float(actual_y_ref),
                'width_start_x': float(width_start_x),
                'width_end_x': float(width_end_x),
                'depth_end_y': float(depth_end_y),
                'height_end_y': float(height_end_y),  # NEW: Height end position
                'threshold': float(threshold),
                'xy_slice': xy_slice,
                'melted_mask': melted_mask,
                'width_profile': width_profile,
                'width_mask': width_mask,
                'coordinates': {'x': x, 'y': y, 'z': z},
                'max_melt_history': float(np.max(xy_slice)),
                'vtk_file': os.path.basename(self.vtk_file_path),
                'vtk_full_path': self.vtk_file_path,
                'file_modification_time': file_mtime.isoformat(),
                'analysis_timestamp': datetime.now().isoformat(),
                'file_size_mb': float(file_stat.st_size / (1024 * 1024)),
                'array_used': array_name
            }
            
            return results
            
        except Exception as e:
            self.log(f"Error in analysis: {str(e)}")
            raise RuntimeError(f"Analysis failed: {str(e)}")
    
    def visualize_xy_analysis(self, results, output_dir='./output'):
        """Visualize results and save to files with improved error handling and bead height visualization"""
        if results is None:
            self.log("No results to visualize")
            return None
        
        try:
            # Create output directory
            os.makedirs(output_dir, exist_ok=True)
            
            # Set matplotlib to handle any potential encoding issues
            plt.rcParams['font.family'] = 'DejaVu Sans'
            
            # Create a 2x3 subplot layout to accommodate the new height profile
            fig, axes = plt.subplots(2, 3, figsize=(20, 12))
            
            x = results['coordinates']['x']
            y = results['coordinates']['y']
            xy_slice = results['xy_slice']
            melted_mask = results['melted_mask']
            
            # Plot 1: Original melt history
            im1 = axes[0,0].imshow(xy_slice, 
                                  extent=[x[0], x[-1], y[-1], y[0]],
                                  cmap='hot', aspect='equal', origin='upper')
            axes[0,0].set_title(f'Melt History - XY Plane\n(Z = {results["z_slice"]*1000:.3f} mm)')
            axes[0,0].set_xlabel('X (m)')
            axes[0,0].set_ylabel('Y (m)')
            axes[0,0].axhline(y=results['y_reference'], color='cyan', linestyle='--', 
                             linewidth=2, label=f'Ref line: Y = {results["y_reference"]*1000:.3f} mm')
            axes[0,0].legend()
            plt.colorbar(im1, ax=axes[0,0], label='Melt History')
            
            # Plot 2: Measurements (updated to include height)
            axes[0,1].imshow(melted_mask, 
                            extent=[x[0], x[-1], y[-1], y[0]],
                            cmap='binary', aspect='equal', origin='upper')
            
            if results['width'] > 0:
                axes[0,1].plot([results['width_start_x'], results['width_end_x']], 
                              [results['y_reference'], results['y_reference']], 
                              'r-', linewidth=3, 
                              label=f'Width: {results["width"]*1000:.3f} mm')
            
            if results['depth'] > 0:
                axes[0,1].plot([results['center_x'], results['center_x']], 
                              [results['y_reference'], results['depth_end_y']], 
                              'g-', linewidth=3,
                              label=f'Depth: {results["depth"]*1000:.3f} mm')
            
            # NEW: Plot height measurement
            if results['height'] > 0:
                axes[0,1].plot([results['center_x'], results['center_x']], 
                              [results['y_reference'], results['height_end_y']], 
                              'orange', linewidth=3,
                              label=f'Height: {results["height"]*1000:.3f} mm')
            
            axes[0,1].plot(results['center_x'], results['center_y'], 'ko', 
                          markersize=8, label='Center of mass')
            axes[0,1].set_title('Melt Pool Measurements')
            axes[0,1].set_xlabel('X (m)')
            axes[0,1].set_ylabel('Y (m)')
            axes[0,1].legend()
            
            # Plot 3: Width profile
            axes[0,2].plot(x, results['width_profile'], 'b-', linewidth=2)
            axes[0,2].axhline(y=results['threshold'], color='r', linestyle='--')
            axes[0,2].fill_between(x, 0, results['width_profile'], 
                                  where=results['width_mask'], alpha=0.3, color='red')
            axes[0,2].set_title(f'Width Profile at Y = {results["y_reference"]*1000:.3f} mm')
            axes[0,2].set_xlabel('X (m)')
            axes[0,2].set_ylabel('Melt History')
            axes[0,2].grid(True, alpha=0.3)
            
            # Plot 4: Depth profile (existing)
            center_x_idx = np.argmin(np.abs(x - results['center_x']))
            depth_profile = xy_slice[:, center_x_idx]
            depth_mask = depth_profile > results['threshold']
            
            axes[1,0].plot(y, depth_profile, 'g-', linewidth=2, label='Profile')
            axes[1,0].axhline(y=results['threshold'], color='r', linestyle='--', label='Threshold')
            axes[1,0].fill_between(y, 0, depth_profile, 
                                  where=depth_mask, alpha=0.3, color='green')
            axes[1,0].axvline(x=results['y_reference'], color='cyan', linestyle='-', 
                             linewidth=2, label='Reference')
            if results['depth'] > 0:
                axes[1,0].axvline(x=results['depth_end_y'], color='orange', 
                                 linestyle='-', label='Depth end')
            axes[1,0].set_title(f'Depth Profile at X = {results["center_x"]*1000:.3f} mm')
            axes[1,0].set_xlabel('Y (m)')
            axes[1,0].set_ylabel('Melt History')
            axes[1,0].grid(True, alpha=0.3)
            axes[1,0].legend()
            
            # Plot 5: NEW - Height profile (same profile as depth, but highlighting upward direction)
            axes[1,1].plot(y, depth_profile, 'orange', linewidth=2, label='Profile')
            axes[1,1].axhline(y=results['threshold'], color='r', linestyle='--', label='Threshold')
            axes[1,1].fill_between(y, 0, depth_profile, 
                                  where=depth_mask, alpha=0.3, color='orange')
            axes[1,1].axvline(x=results['y_reference'], color='cyan', linestyle='-', 
                             linewidth=2, label='Reference')
            if results['height'] > 0:
                axes[1,1].axvline(x=results['height_end_y'], color='red', 
                                 linestyle='-', label='Height end')
            axes[1,1].set_title(f'Height Profile at X = {results["center_x"]*1000:.3f} mm')
            axes[1,1].set_xlabel('Y (m)')
            axes[1,1].set_ylabel('Melt History')
            axes[1,1].grid(True, alpha=0.3)
            axes[1,1].legend()
            
            # Plot 6: NEW - Combined measurements summary
            axes[1,2].bar(['Width', 'Depth', 'Height'], 
                         [results['width']*1000, results['depth']*1000, results['height']*1000],
                         color=['red', 'green', 'orange'], alpha=0.7)
            axes[1,2].set_title('Melt Pool Dimensions Summary')
            axes[1,2].set_ylabel('Dimension (mm)')
            axes[1,2].grid(True, alpha=0.3)
            
            # Add text annotations
            for i, (dim, val) in enumerate(zip(['Width', 'Depth', 'Height'], 
                                             [results['width']*1000, results['depth']*1000, results['height']*1000])):
                axes[1,2].text(i, val + 0.01, f'{val:.2f}', ha='center', va='bottom', fontweight='bold')
            
            plt.tight_layout()
            
            # Save figure with timestamp - use safe filename
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            vtk_name = os.path.splitext(results['vtk_file'])[0]
            # Remove any problematic characters from filename
            safe_vtk_name = "".join(c for c in vtk_name if c.isalnum() or c in ('-', '_', '.'))
            plot_filename = os.path.join(output_dir, f'{timestamp}_{safe_vtk_name}_melt_pool_analysis.png')
            
            plt.savefig(plot_filename, dpi=300, bbox_inches='tight')
            plt.close()  # Close figure to free memory
            
            # Print summary (updated to include height)
            self.log(f"\n=== MELT POOL ANALYSIS - XY PLANE ===")
            self.log(f"File: {results['vtk_file']}")
            self.log(f"Array used: {results.get('array_used', 'Unknown')}")
            self.log(f"File modified: {results['file_modification_time']}")
            self.log(f"Analysis time: {results['analysis_timestamp']}")
            self.log(f"Width: {results['width']*1000:.3f} mm")
            self.log(f"Depth: {results['depth']*1000:.3f} mm")
            self.log(f"Height: {results['height']*1000:.3f} mm")  # NEW
            self.log(f"Area: {results['area']*1000000:.3f} mm²")
            self.log(f"Plot saved: {plot_filename}")
            
            # Save detailed results to JSON file with custom encoder (updated to include height)
            json_filename = os.path.join(output_dir, f'{timestamp}_{safe_vtk_name}_results.json')
            json_data = {k: v for k, v in results.items() 
                        if k not in ['xy_slice', 'melted_mask', 'width_profile', 'width_mask', 'coordinates']}
            json_data['plot_filename'] = plot_filename
            
            # Use custom encoder to handle numpy types
            with open(json_filename, 'w', encoding='utf-8') as f:
                json.dump(json_data, f, indent=2, cls=NumpyEncoder, ensure_ascii=False)
            
            # Save results to text file (human-readable, updated to include height)
            txt_filename = os.path.join(output_dir, f'{timestamp}_{safe_vtk_name}_results.txt')
            with open(txt_filename, 'w', encoding='utf-8') as f:
                f.write(f"MELT POOL ANALYSIS RESULTS\n")
                f.write(f"==========================\n")
                f.write(f"File: {results['vtk_file']}\n")
                f.write(f"Full path: {results['vtk_full_path']}\n")
                f.write(f"Array used: {results.get('array_used', 'Unknown')}\n")
                f.write(f"File modified: {results['file_modification_time']}\n")
                f.write(f"Analysis time: {results['analysis_timestamp']}\n")
                f.write(f"File size: {results['file_size_mb']:.2f} MB\n")
                f.write(f"Analysis plane: Z = {results['z_slice']*1000:.3f} mm\n")
                f.write(f"Reference line: Y = {results['y_reference']*1000:.3f} mm\n")
                f.write(f"Threshold: {results['threshold']}\n\n")
                f.write(f"MEASUREMENTS:\n")
                f.write(f"Width: {results['width']*1000:.3f} mm\n")
                f.write(f"Depth: {results['depth']*1000:.3f} mm\n")
                f.write(f"Height: {results['height']*1000:.3f} mm\n")  # NEW
                f.write(f"Area: {results['area']*1000000:.3f} mm²\n")
                f.write(f"Center X: {results['center_x']*1000:.3f} mm\n")
                f.write(f"Center Y: {results['center_y']*1000:.3f} mm\n")
                f.write(f"Max melt history: {results['max_melt_history']:.3f}\n")
                f.write(f"Height end Y: {results['height_end_y']*1000:.3f} mm\n")  # NEW
            
            self.log(f"Results saved: {txt_filename}")
            self.log(f"JSON data saved: {json_filename}")
            
            return {
                'width_mm': results['width']*1000,
                'depth_mm': results['depth']*1000,
                'height_mm': results['height']*1000,  # NEW
                'area_mm2': results['area']*1000000,
                'plot_file': plot_filename,
                'results_file': txt_filename,
                'json_file': json_filename,
                'analysis_timestamp': results['analysis_timestamp']
            }
            
        except Exception as e:
            self.log(f"Error in visualization: {str(e)}")
            raise RuntimeError(f"Visualization failed: {str(e)}")

def find_latest_vtk_file(directory_path):
    """Find the most recently modified VTK file in the given directory"""
    vtk_files = []
    
    # Try different extensions
    patterns = ["*.vtk", "*.vtu", "*.vti"]
    
    for pattern in patterns:
        try:
            files = glob.glob(os.path.join(directory_path, pattern))
            vtk_files.extend(files)
        except Exception:
            continue
    
    if not vtk_files:
        return None
    
    # Get the most recently modified file
    try:
        latest_file = max(vtk_files, key=os.path.getmtime)
        return latest_file
    except Exception:
        return vtk_files[0] if vtk_files else None

def wait_for_new_vtk_file(directory_path, last_file=None, timeout=300, check_interval=5):
    """Wait for a new VTK file to appear or be modified"""
    start_time = time.time()
    
    while time.time() - start_time < timeout:
        try:
            current_latest = find_latest_vtk_file(directory_path)
            
            if current_latest is None:
                time.sleep(check_interval)
                continue
                
            # If no previous file, return current
            if last_file is None:
                return current_latest
                
            # Check if file is newer than last processed file
            if current_latest != last_file:
                current_mtime = os.path.getmtime(current_latest)
                last_mtime = os.path.getmtime(last_file) if os.path.exists(last_file) else 0
                
                if current_mtime > last_mtime:
                    return current_latest
            
            time.sleep(check_interval)
            
        except Exception:
            time.sleep(check_interval)
            continue
    
    return None  # Timeout reached

def get_file_info(file_path):
    """Get file information including creation and modification times"""
    import time
    
    try:
        stat = os.stat(file_path)
        
        # Get modification time
        mod_time = time.ctime(stat.st_mtime)
        
        # Get file size
        file_size = stat.st_size / (1024 * 1024)  # MB
        
        return {
            'modification_time': mod_time,
            'size_mb': file_size,
            'mtime_timestamp': stat.st_mtime
        }
    except Exception as e:
        return {
            'modification_time': 'Unknown',
            'size_mb': 0,
            'mtime_timestamp': 0,
            'error': str(e)
        }

def create_summary_report(output_dir):
    """Create a summary report of all analyses in the output directory (updated to include height)"""
    try:
        json_files = glob.glob(os.path.join(output_dir, "*_results.json"))
        
        if not json_files:
            return None
        
        summary_data = []
        
        for json_file in sorted(json_files):
            try:
                with open(json_file, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    summary_data.append({
                        'timestamp': data.get('analysis_timestamp', ''),
                        'vtk_file': data.get('vtk_file', ''),
                        'width_mm': data.get('width', 0) * 1000,
                        'depth_mm': data.get('depth', 0) * 1000,
                        'height_mm': data.get('height', 0) * 1000,  # NEW
                        'area_mm2': data.get('area', 0) * 1000000,
                        'file_size_mb': data.get('file_size_mb', 0)
                    })
            except (json.JSONDecodeError, KeyError, UnicodeDecodeError):
                continue
        
        if not summary_data:
            return None
        
        # Create summary report
        summary_file = os.path.join(output_dir, f"analysis_summary_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt")
        
        with open(summary_file, 'w', encoding='utf-8') as f:
            f.write("MELT POOL ANALYSIS SUMMARY\n")
            f.write("=" * 60 + "\n\n")
            f.write(f"Total analyses: {len(summary_data)}\n")
            f.write(f"Report generated: {datetime.now().isoformat()}\n\n")
            
            f.write("INDIVIDUAL RESULTS:\n")
            f.write("-" * 95 + "\n")
            f.write(f"{'Timestamp':<20} {'VTK File':<25} {'Width(mm)':<12} {'Depth(mm)':<12} {'Height(mm)':<12} {'Area(mm²)':<12}\n")
            f.write("-" * 95 + "\n")
            
            for data in summary_data:
                timestamp_short = data['timestamp'][:19] if data['timestamp'] else 'N/A'
                f.write(f"{timestamp_short:<20} {data['vtk_file']:<25} {data['width_mm']:<12.3f} "
                       f"{data['depth_mm']:<12.3f} {data['height_mm']:<12.3f} {data['area_mm2']:<12.3f}\n")
            
            f.write("\n" + "=" * 60 + "\n")
            
            # Statistics (updated to include height)
            widths = [d['width_mm'] for d in summary_data if d['width_mm'] > 0]
            depths = [d['depth_mm'] for d in summary_data if d['depth_mm'] > 0]
            heights = [d['height_mm'] for d in summary_data if d['height_mm'] > 0]  # NEW
            areas = [d['area_mm2'] for d in summary_data if d['area_mm2'] > 0]
            
            if widths:
                f.write(f"Width statistics (mm):\n")
                f.write(f"  Mean: {np.mean(widths):.3f}\n")
                f.write(f"  Std:  {np.std(widths):.3f}\n")
                f.write(f"  Min:  {np.min(widths):.3f}\n")
                f.write(f"  Max:  {np.max(widths):.3f}\n\n")
            
            if depths:
                f.write(f"Depth statistics (mm):\n")
                f.write(f"  Mean: {np.mean(depths):.3f}\n")
                f.write(f"  Std:  {np.std(depths):.3f}\n")
                f.write(f"  Min:  {np.min(depths):.3f}\n")
                f.write(f"  Max:  {np.max(depths):.3f}\n\n")
            
            # NEW: Height statistics
            if heights:
                f.write(f"Height statistics (mm):\n")
                f.write(f"  Mean: {np.mean(heights):.3f}\n")
                f.write(f"  Std:  {np.std(heights):.3f}\n")
                f.write(f"  Min:  {np.min(heights):.3f}\n")
                f.write(f"  Max:  {np.max(heights):.3f}\n\n")
        
        return summary_file
        
    except Exception as e:
        print(f"Error creating summary report: {str(e)}")
        return None

def main():
    parser = argparse.ArgumentParser(description='Enhanced HPC Melt Pool Analyzer with Automation Support and Bead Height Measurement - UPDATED VERSION')
    parser.add_argument('--vtk_dir', type=str, 
                       default='/users/PNS0496/badhon19/nist_am/ch06_5x5_bareplate/testing/vtk',
                       help='Directory containing VTK files')
    parser.add_argument('--output_dir', type=str, default='./melt_pool_results',
                       help='Output directory for results')
    parser.add_argument('--z_slice', type=float, default=0.3e-3,
                       help='Z-coordinate of analysis plane (m)')
    parser.add_argument('--y_reference', type=float, default=-0.3e-3,
                       help='Y-coordinate reference line for width measurement (m)')
    parser.add_argument('--threshold', type=float, default=1000,
                       help='Threshold value for melt detection')
    parser.add_argument('--array_name', type=str, default='meltHistory',
                       help='Name of the VTK array to analyze')
    parser.add_argument('--wait_for_new', action='store_true',
                       help='Wait for new VTK files (for automation)')
    parser.add_argument('--timeout', type=int, default=300,
                       help='Timeout in seconds when waiting for new files')
    parser.add_argument('--summary_report', action='store_true',
                       help='Generate summary report of all analyses')
    parser.add_argument('--quiet', action='store_true',
                       help='Reduce output verbosity')
    parser.add_argument('--grid_resolution', type=int, nargs=3, default=[200, 200, 100],
                       help='Grid resolution for analysis (x, y, z)')
    
    args = parser.parse_args()
    
    verbose = not args.quiet
    
    # Set up better error handling
    try:
        if verbose:
            print(f"Enhanced Melt Pool Analyzer with Bead Height Measurement (UPDATED VERSION) starting...")
            print(f"Python encoding: {sys.stdout.encoding}")
            print(f"Searching for VTK files in: {args.vtk_dir}")
        
        # Check if directory exists
        if not os.path.exists(args.vtk_dir):
            print(f"Error: Directory does not exist: {args.vtk_dir}")
            sys.exit(1)
        
        # Create output directory
        os.makedirs(args.output_dir, exist_ok=True)
        
        # Generate summary report if requested
        if args.summary_report:
            summary_file = create_summary_report(args.output_dir)
            if summary_file:
                print(f"Summary report generated: {summary_file}")
            else:
                print("No analysis results found for summary report")
            return
        
        # Find VTK file
        if args.wait_for_new:
            if verbose:
                print(f"Waiting for new VTK files (timeout: {args.timeout}s)...")
            
            # Try to find existing file first
            existing_file = find_latest_vtk_file(args.vtk_dir)
            if existing_file and verbose:
                print(f"Existing file found: {os.path.basename(existing_file)}")
            
            # Wait for new file
            latest_vtk = wait_for_new_vtk_file(args.vtk_dir, existing_file, args.timeout)
            
            if latest_vtk is None:
                print(f"No new VTK files appeared within {args.timeout} seconds")
                sys.exit(1)
            
            if verbose:
                print(f"New VTK file detected: {os.path.basename(latest_vtk)}")
        else:
            latest_vtk = find_latest_vtk_file(args.vtk_dir)
            
            if latest_vtk is None:
                print(f"No VTK files found in {args.vtk_dir}")
                sys.exit(1)
        
        # Get file information
        file_info = get_file_info(latest_vtk)
        
        if verbose:
            print(f"\nVTK file to process:")
            print(f"  File: {os.path.basename(latest_vtk)}")
            print(f"  Full path: {latest_vtk}")
            print(f"  Last modified: {file_info.get('modification_time', 'Unknown')}")
            print(f"  Size: {file_info.get('size_mb', 0):.2f} MB")
        
        # Process the file
        if verbose:
            print(f"\n{'='*60}")
            print(f"Processing: {os.path.basename(latest_vtk)}")
            print(f"{'='*60}")
        
        analyzer = EnhancedMeltPoolAnalyzer(latest_vtk, verbose=verbose)
        
        # Try analysis with error handling for array names
        analysis_successful = False
        array_attempts = [args.array_name, 'meltHistory', 'Temperature', 'temp', 'T']
        
        for attempt_array in array_attempts:
            try:
                if verbose:
                    print(f"Attempting analysis with array: {attempt_array}")
                
                results = analyzer.analyze_melt_pool_xy_plane(
                    array_name=attempt_array,
                    z_slice=args.z_slice, 
                    y_reference=args.y_reference,
                    threshold=args.threshold,
                    grid_resolution=tuple(args.grid_resolution)
                )
                
                if results:
                    summary = analyzer.visualize_xy_analysis(results, args.output_dir)
                    analysis_successful = True
                    
                    if verbose:
                        print(f"\n✓ Analysis completed successfully with array: {attempt_array}")
                        print(f"✓ Results saved to: {args.output_dir}")
                        print(f"✓ Width: {summary['width_mm']:.3f} mm")
                        print(f"✓ Depth: {summary['depth_mm']:.3f} mm")
                        print(f"✓ Height: {summary['height_mm']:.3f} mm")  # NEW
                    
                    # Return success code
                    sys.exit(0)
                    
            except Exception as e:
                if verbose:
                    print(f"Failed with array '{attempt_array}': {str(e)}")
                continue
        
        if not analysis_successful:
            print(f"❌ Analysis failed with all attempted arrays: {array_attempts}")
            print(f"❌ Last error occurred while processing: {latest_vtk}")
            
            # Try to get available arrays for debugging
            try:
                analyzer_debug = EnhancedMeltPoolAnalyzer(latest_vtk, verbose=True)
                available_arrays = analyzer_debug.get_available_arrays()
                print(f"Available arrays in file: {available_arrays}")
            except:
                print("Could not determine available arrays")
            
            sys.exit(1)
            
    except KeyboardInterrupt:
        print("\n⚠️  Analysis interrupted by user")
        sys.exit(130)
    except Exception as e:
        print(f"❌ Unexpected error: {str(e)}")
        if verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()