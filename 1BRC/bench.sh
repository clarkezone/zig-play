#!/bin/bash

# Define the name of the file and the executable
file_to_check="./data/measurements_1B.txt"
executable_to_run="./fast/zig-out/bin/fast"

# Check if the file exists
if [ -f "$file_to_check" ]; then
    # Call the executable passing the file as an argument
    $executable_to_run "$file_to_check"
    hyperfine --warmup=3 --show-output --command-name="$executable_to_run $file_to_check" "$executable_to_run $file_to_check"
else
    # Print an error message and exit with status code 1
    echo "File not found: $file_to_check"
    exit 1
fi
