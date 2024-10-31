#!/bin/bash

BASE_DIR="./out"
OUTPUT_DIR="./abis"

mkdir -p "$OUTPUT_DIR"

find "$BASE_DIR" -type f -name "*.json" | while read -r json_file; do
    if jq -e '.rawMetadata | fromjson | .devdoc."custom:export" == "abi"' "$json_file" > /dev/null 2>&1; then
        abi=$(jq -r '.rawMetadata | fromjson | .output.abi' "$json_file")

        if [[ "$abi" != "null" && -n "$abi" ]]; then
            output_file="$OUTPUT_DIR/$(basename "$json_file" .json)_abi.json"
            echo "$abi" > "$output_file"
            echo "Extracted ABI from $json_file to $output_file"
        else
            echo "No ABI found in $json_file"
        fi
    else
        echo "No ABI found in $json_file"
    fi
done
