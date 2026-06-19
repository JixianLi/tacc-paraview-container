#!/usr/bin/env bash
# Build a ParaView 6.1.1 Apptainer image (EGL or OSMesa) on TACC Lonestar6.
#
# Usage: install.sh [-b|--backend egl|osmesa] [-o|--output PATH]
#
# Recommended:
#     idev -p development -N 1 -n 128 -t 01:00:00
#     cd $WORK && /path/to/install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND="egl"
OUTPUT_SIF=""
export APPTAINER_CACHEDIR="${APPTAINER_CACHEDIR:-${SCRATCH:-$PWD}/.apptainer_cache}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -b|--backend)
            BACKEND="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_SIF="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [-b|--backend egl|osmesa] [-o|--output PATH]"
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

case "${BACKEND}" in
    egl|osmesa) ;;
    *)
        echo "ERROR: --backend must be 'egl' or 'osmesa' (got: ${BACKEND})" >&2
        exit 1
        ;;
esac

DEF_FILE="${SCRIPT_DIR}/paraview-${BACKEND}.def"
: "${OUTPUT_SIF:=$PWD/paraview-6.1.1-${BACKEND}.sif}"

command -v apptainer >/dev/null || { echo "ERROR: apptainer not on PATH" >&2; exit 1; }
[[ -f "${DEF_FILE}" ]] || { echo "ERROR: ${DEF_FILE} not found" >&2; exit 1; }

if [[ "$(hostname)" == login* ]]; then
    echo "WARNING: appears to be a login node — long builds may hit per-process CPU-time limits." >&2
    echo "         Run inside 'idev -p development -N 1 -n 128 -t 01:00:00' for safety." >&2
fi

mkdir -p "${APPTAINER_CACHEDIR}"

# Make OUTPUT_SIF absolute before we cd elsewhere, so a user-supplied
# relative --output keeps pointing at the original cwd.
case "${OUTPUT_SIF}" in
    /*) ;;
    *) OUTPUT_SIF="$(pwd)/${OUTPUT_SIF}" ;;
esac

echo "Building ${OUTPUT_SIF}"
echo "  from:  ${DEF_FILE}"
echo "  cache: ${APPTAINER_CACHEDIR}"
echo

# %files in the def references build-common.sh by relative path; apptainer
# resolves it from the cwd at build time, so build from the script's dir.
cd "${SCRIPT_DIR}"
time apptainer build --fakeroot "${OUTPUT_SIF}" "${DEF_FILE}"

echo
echo "Built: ${OUTPUT_SIF}"
apptainer exec "${OUTPUT_SIF}" pvbatch --version

echo
if [[ "${BACKEND}" == "egl" ]]; then
    echo "Run on a GPU node with:"
    echo "  apptainer exec --nv ${OUTPUT_SIF} pvbatch your_script.py"
else
    echo "Run on any partition (no --nv needed):"
    echo "  apptainer exec ${OUTPUT_SIF} pvbatch your_script.py"
fi
