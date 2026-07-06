#!/bin/sh
set -eu

ARTIFACT_DIR="${1:-release-artifacts}"
CHECKSUM_FILE="$ARTIFACT_DIR/SHA256SUMS.txt"

if [ ! -d "$ARTIFACT_DIR" ]; then
    echo "Artifact directory not found: $ARTIFACT_DIR" >&2
    exit 1
fi

tmp_file="$CHECKSUM_FILE.tmp"
list_file="$CHECKSUM_FILE.list.tmp"
find "$ARTIFACT_DIR" -maxdepth 1 -type f -name '*.zip' -print | sort > "$list_file"

if [ ! -s "$list_file" ]; then
    rm -f "$tmp_file" "$list_file"
    echo "No ZIP artifacts found in $ARTIFACT_DIR" >&2
    exit 1
fi

: > "$tmp_file"
while IFS= read -r file; do
    base="$(basename "$file")"
    (cd "$ARTIFACT_DIR" && shasum -a 256 "$base") >> "$tmp_file"
done < "$list_file"

rm -f "$list_file"

mv "$tmp_file" "$CHECKSUM_FILE"
echo "Wrote $CHECKSUM_FILE"
