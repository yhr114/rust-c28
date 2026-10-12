#!/usr/bin/env bash
# Template only. Adjust SDK_ROOT/CASE/BOOT for FPGA build flow.
set -euo pipefail
SDK_ROOT=${SDK_ROOT:-/path/to/s03_sdk}
CASE=${1:?usage: run_one_template.sh <case_name>}
BOOT=${BOOT:-sram}
VERSION=${VERSION:-28035}

echo "[FPGA] build case=${CASE} version=${VERSION} boot=${BOOT}"
# Example placeholder:
# make -C "$SDK_ROOT" fpga-package CASE="$CASE" VERSION="$VERSION" BOOT="$BOOT"
# ./download_to_fpga.sh "$SDK_ROOT/build/${CASE}/${CASE}.elf"
# ./wait_case_done.sh "$CASE"
