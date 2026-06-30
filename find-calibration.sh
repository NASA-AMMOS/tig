#!/bin/bash
# Helper script to locate MARS calibration files
# Checks multiple common locations and environment variables

# Priority order for calibration location:
# 1. MARS_CALIB_PATH environment variable
# 2. Relative to script location (for demos in repo)
# 3. User's home directory
# 4. /opt/mars_calib (system-wide)
# 5. Current directory

find_calibration() {
    local calib_dir=""
    
    # Check MARS_CALIB_PATH environment variable
    if [ -n "$MARS_CALIB_PATH" ] && [ -d "$MARS_CALIB_PATH" ]; then
        echo "$MARS_CALIB_PATH"
        return 0
    fi
    
    # Check relative to script location (for repo demos)
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -d "$script_dir/calibration" ]; then
        echo "$script_dir/calibration"
        return 0
    fi
    
    # Check user's home directory
    if [ -d "$HOME/.mars_calib" ]; then
        echo "$HOME/.mars_calib"
        return 0
    fi
    
    # Check system-wide location
    if [ -d "/opt/mars_calib" ]; then
        echo "/opt/mars_calib"
        return 0
    fi
    
    # Check current directory
    if [ -d "./mars_calibration_m20" ]; then
        echo "./mars_calibration_m20"
        return 0
    fi
    
    if [ -d "./mars_calib" ]; then
        echo "./mars_calib"
        return 0
    fi
    
    # Not found
    return 1
}

verify_calibration() {
    local calib_dir="$1"
    
    if [ ! -d "$calib_dir" ]; then
        return 1
    fi
    
    # Check for required subdirectories
    local has_cameras=false
    local has_params=false
    
    if [ -d "$calib_dir/camera_models" ] && [ -n "$(ls -A $calib_dir/camera_models 2>/dev/null)" ]; then
        has_cameras=true
    fi
    
    if [ -d "$calib_dir/param_files" ] && [ -n "$(ls -A $calib_dir/param_files 2>/dev/null)" ]; then
        has_params=true
    fi
    
    if $has_cameras && $has_params; then
        return 0
    else
        return 1
    fi
}

print_calibration_help() {
    cat << 'EOF'
ERROR: MARS calibration files not found.

The mesh generation tools require MARS calibration files containing:
  - camera_models/  (CAHV/CAHVOR/CAHVORE camera models)
  - param_files/    (camera mapping XML, flat field parameters)
  - flat_fields/    (optional, for radiometric correction)

To specify calibration location, use one of:

1. Environment variable (recommended for system-wide use):
   export MARS_CALIB_PATH=/path/to/mars_calibration_m20

2. User home directory:
   mkdir -p ~/.mars_calib
   cp -r /path/to/calibration/* ~/.mars_calib/

3. System-wide installation:
   sudo mkdir -p /opt/mars_calib
   sudo cp -r /path/to/calibration/* /opt/mars_calib/

4. Local directory:
   cp -r /path/to/calibration ./mars_calib

The script will check these locations in order:
  1. $MARS_CALIB_PATH
  2. ./calibration (repo structure)
  3. ~/.mars_calib
  4. /opt/mars_calib
  5. ./mars_calibration_m20
  6. ./mars_calib

For TIG repository users:
  Calibration is already in: ./calibration/

EOF
}

# Main execution when sourced or run directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # Script is being executed directly
    calib_path=$(find_calibration)
    if [ $? -eq 0 ]; then
        if verify_calibration "$calib_path"; then
            echo "Found calibration at: $calib_path"
            exit 0
        else
            echo "WARNING: Found directory at $calib_path but missing required subdirectories"
            print_calibration_help
            exit 1
        fi
    else
        print_calibration_help
        exit 1
    fi
fi
