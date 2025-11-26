#!/usr/bin/env python3
import pyvista as pv
import numpy as np
from pathlib import Path
import re

vtk_dir = Path("/users/PNS0496/badhon19/nist_am/test_melthistory/VTK")

# Collect and sort by numeric timestep instead of filename
def timestep_key(path):
    # Extract number after 'test_melthistory_'
    match = re.search(r"test_melthistory_(\d*\.?\d*)\.vtk", path.name)
    return float(match.group(1)) if match else -1

vtk_files = sorted(vtk_dir.glob("*.vtk"), key=timestep_key)
if not vtk_files:
    raise FileNotFoundError(f"No .vtk files found in {vtk_dir}")

# Pick the last one (highest timestep)
vtk_file = vtk_files[-1]
print(f"\n📂 Using last VTK file: {vtk_file.name}")

# Load dataset
mesh = pv.read(vtk_file)

target = "melt_count"

if target in mesh.point_data:
    values = mesh.point_data[target]
    print(f"\n🔹 Unique {target} values in point_data:")
    print(np.unique(values))
elif target in mesh.cell_data:
    values = mesh.cell_data[target]
    print(f"\n🔹 Unique {target} values in cell_data:")
    print(np.unique(values))
else:
    print(f"\n⚠️ '{target}' not found in point_data or cell_data.")
