#!/usr/bin/env bash
set -euo pipefail

ZIP_FILE="${1:-site.zip}"
DEST_DIR="${2:-docs}"

if [[ ! -f "$ZIP_FILE" ]]; then
  echo "Error: zip file not found: $ZIP_FILE"
  exit 1
fi

mkdir -p "$DEST_DIR"
rm -rf "$DEST_DIR"/*

if unzip -q "$ZIP_FILE" -d "$DEST_DIR"; then
  echo "Extracted '$ZIP_FILE' into '$DEST_DIR'"
  exit 0
fi

echo "unzip failed, falling back to raw ZIP recovery"
python3 - "$ZIP_FILE" "$DEST_DIR" <<'PY'
import os, struct, sys, zlib
zip_path = sys.argv[1]
dst_root = sys.argv[2]

with open(zip_path, 'rb') as f:
    data = f.read()
size = len(data)

PREFIX = b'vault555-apk/www/'

pos = 0
extracted = 0
while pos + 30 <= size:
    if data[pos:pos+4] != b'PK\x03\x04':
        break
    header = data[pos+4:pos+30]
    version, flags, comp, mtime, mdate, crc, csz, usz, nlen, xlen = struct.unpack('<HHHHHIIIHH', header)
    name_bytes = data[pos+30:pos+30+nlen]
    name = name_bytes.decode('utf-8', 'replace')
    data_off = pos + 30 + nlen + xlen
    if csz > 0:
        file_data = data[data_off:data_off+csz]
    else:
        file_data = b''

    rel = name
    if rel.startswith(PREFIX.decode()):
        rel = rel[len(PREFIX):]

    rel = rel.lstrip('/\\')
    target_path = os.path.normpath(os.path.join(dst_root, rel))
    if not target_path.startswith(os.path.abspath(dst_root)):
        raise SystemExit(f"Invalid archive entry path: {name}")

    if name.endswith('/'):
        os.makedirs(target_path, exist_ok=True)
    else:
        os.makedirs(os.path.dirname(target_path), exist_ok=True)
        if comp == 0:
            out_data = file_data
        elif comp == 8:
            try:
                out_data = zlib.decompress(file_data, -zlib.MAX_WBITS)
            except zlib.error:
                out_data = zlib.decompress(file_data.rstrip(b'\x00'), -zlib.MAX_WBITS)
        else:
            raise SystemExit(f"Unsupported compression method {comp} for {name}")
        with open(target_path, 'wb') as out_f:
            out_f.write(out_data)
    extracted += 1
    pos = data_off + csz

print(f"Recovered {extracted} entries into {dst_root}")
PY

echo "Completed fallback extraction into '$DEST_DIR'"
