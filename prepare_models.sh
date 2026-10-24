#!/usr/bin/env bash
set -euo pipefail
# Runs on Codemagic macOS or GitHub Linux; caches downloads, never bypasses verification.
python3 -m pip install --user 'uv==0.9.5'
python3 -m uv venv --python 3.12 --allow-existing .visioncane/export-env
python3 -m uv pip install --python .visioncane/export-env/bin/python --torch-backend cpu -r tool/model-requirements.txt
if [ "${1:-android}" != android ]; then
  python3 -m uv pip install --python .visioncane/export-env/bin/python coremltools
fi
.visioncane/export-env/bin/python tool/build_indoor_model.py --platform "${1:-android}"
