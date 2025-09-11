#!/bin/bash

JUNIT_DIR="./junit_files"

if [ ! -d "$JUNIT_DIR" ]; then
    echo "Directory $JUNIT_DIR does not exist."
    exit 1
fi

for file in "$JUNIT_DIR"/*; do
    if [ -f "$file" ]; then
        echo "Processing $file..."
        # Both files have the same name but different extensions, metada is json and junit is xml
        metada_file="metada_json/$(basename "${file%.*}").json"
        if [ ! -f "$metada_file" ]; then
            echo "Metadata file $metada_file does not exist. Skipping $file."
            continue
        fi
        echo "Using metadata file $metada_file"
        droute send --metadata "$metada_file" \
        --results "$file" \
        --username ossm-oidc-sa \
        --password b71a69cc-880e-432f-8d6e-cd2a4c89d8e4 \
        --url  https://datarouter.ccitredhat.com \
        --verbose
    fi
done