#!/usr/bin/env fish
# run_build_flash.fish
# Script to apply sdkconfig.defaults, build, flash and capture monitor log for the project.
# Usage: edit IDF_PATH and optionally PORT at top of script, then run: ./tools/run_build_flash.fish

# --- User configuration ----------------------------------------------------
# Set your ESP-IDF path here if you want hardcoded; otherwise export IDF_PATH in your shell before running.
set -l DEFAULT_IDF_PATH "/home/pci_iot/esp/v5.5-rc1/esp-idf"
# Set serial port here if known, otherwise script will try to auto-detect
set -l DEFAULT_PORT ""
# Output files
set -l BUILD_LOG "$HOME/idf_build_log.txt"
set -l MONITOR_LOG "$HOME/ble_prov_log.txt"
# --------------------------------------------------------------------------

# Helper: print and run
function rr
    echo ">> $argv"
    eval $argv
end

# Determine IDF_PATH
if test -z "$IDF_PATH"
    if test -d "$DEFAULT_IDF_PATH"
        set -x IDF_PATH $DEFAULT_IDF_PATH
        echo "Using default IDF_PATH: $IDF_PATH"
    else
        echo "IDF_PATH not set and default path not found. Export IDF_PATH or edit script." 
        exit 1
    end
else
    echo "Using IDF_PATH from environment: $IDF_PATH"
end

# Source IDF env for fish
if test -f "$IDF_PATH/export.fish"
    source "$IDF_PATH/export.fish"
else
    echo "Could not find export.fish in $IDF_PATH. Make sure ESP-IDF is installed correctly." 
    exit 1
end

# Change to project dir
set -l PROJ_DIR (pwd)
cd "$PROJ_DIR"

echo "Applying sdkconfig.defaults (idf.py defconfig)..."
# Apply sdkconfig.defaults
echo "Applying sdkconfig.defaults (idf.py defconfig)..."
rr idf.py defconfig
if test $status -ne 0
    echo "Warning: 'idf.py defconfig' failed or is not supported in this IDF installation.";
    if test -f sdkconfig.defaults
        echo "Falling back to copying sdkconfig.defaults -> sdkconfig (you may still want to run 'idf.py menuconfig' to adjust options)";
        cp sdkconfig.defaults sdkconfig
    else
        echo "sdkconfig.defaults not found; please run 'idf.py menuconfig' manually to create sdkconfig.";
        exit 1
    end
end

# Optional: give user chance to inspect menuconfig
echo "You can press ENTER to run 'idf.py menuconfig' to verify NimBLE/BLE settings, or Ctrl-C to skip." 
read
idf.py menuconfig

# Build
echo "Building project (logs -> $BUILD_LOG)..."
# Use tee to save build output
idf.py build -j 8 2>&1 | tee "$BUILD_LOG"
if test $status -ne 0
    echo "Build failed. See $BUILD_LOG. Exiting."; exit 1
end

# Determine port if not set
if test -z "$PORT"
    if test -n "$DEFAULT_PORT"
        set -x PORT $DEFAULT_PORT
    else
        # Try to auto-detect common serial devices
        set -l devs (ls /dev/ttyACM* /dev/ttyUSB* /dev/serial/by-id/* ^/dev/null 2>/dev/null)
        if test (count $devs) -eq 1
            set -x PORT $devs[1]
            echo "Auto-detected serial port: $PORT"
        else
            echo "Multiple or no serial devices found. Please set PORT environment variable or edit script." 
            echo "Detected devices:"; for d in $devs; echo "  $d"; end
            exit 1
        end
    end
end

# Flash and capture monitor
echo "Flashing to $PORT and capturing monitor log to $MONITOR_LOG ..."
# Run flash+monitor and save output
idf.py -p $PORT flash monitor 2>&1 | tee "$MONITOR_LOG"

# End
echo "Done. Build log: $BUILD_LOG , Monitor log: $MONITOR_LOG"
echo "If BLE provisioning still doesn't appear, paste $MONITOR_LOG here (or the relevant sections)."
