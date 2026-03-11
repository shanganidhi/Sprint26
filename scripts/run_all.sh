#!/usr/bin/env bash
###############################################################
# run_all.sh — Full Automation Script
# Generates data → Simulates (dense & sparse) → Synthesizes → Summarizes
#
# Prerequisites:
#   - Python 3 with numpy
#   - Cadence Xcelium (xrun) for simulation
#   - Cadence Genus for synthesis
#   - Source your Cadence environment before running
#
# Usage:
#   chmod +x scripts/run_all.sh
#   cd POWERFUL_SYSTOLIC_ARRAY
#   ./scripts/run_all.sh
###############################################################
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "============================================="
echo " POWERFUL SYSTOLIC ARRAY — Full Run"
echo " Project root: $ROOT"
echo "============================================="

# Create output directories
mkdir -p data waves reports netlist

###############################################################
# STEP 1: Generate test datasets
###############################################################
echo ""
echo "[STEP 1] Generating test datasets..."

# Dense (0% sparsity)
echo "  → Dense dataset (0% zeros)..."
python3 scripts/generate_sparse_test_data.py --sparsity 0.0 --outdir data/dense --seed 42

# Sparse 50%
echo "  → Sparse-50 dataset (50% zeros)..."
python3 scripts/generate_sparse_test_data.py --sparsity 0.5 --outdir data/sparse50 --seed 42

# Sparse 80%
echo "  → Sparse-80 dataset (80% zeros)..."
python3 scripts/generate_sparse_test_data.py --sparsity 0.8 --outdir data/sparse80 --seed 42

# Sparse 90%
echo "  → Sparse-90 dataset (90% zeros)..."
python3 scripts/generate_sparse_test_data.py --sparsity 0.9 --outdir data/sparse90 --seed 42

# Blackout (100% zeros)
echo "  → Blackout dataset (100% zeros)..."
python3 scripts/generate_sparse_test_data.py --sparsity 1.0 --outdir data/blackout --seed 42

echo "[STEP 1] Done."

###############################################################
# Helper function: Run simulation for a given dataset
###############################################################
run_sim() {
    local DATASET_NAME=$1
    local DATASET_DIR=$2

    echo ""
    echo "[SIM] Running simulation: $DATASET_NAME"

    # Copy dataset files to working data/ directory
    cp "$DATASET_DIR/activations.hex" data/activations.hex
    cp "$DATASET_DIR/weights.hex"     data/weights.hex
    cp "$DATASET_DIR/golden.hex"      data/golden.hex

    # Run Xcelium simulation
    xrun -64bit -access +rwc \
        +define+XCELIUM \
        rtl/pe_ws_pro.v \
        rtl/localized_controller_pro.v \
        rtl/wavefront_controller.v \
        rtl/systolic_array_4x4_pro.v \
        tb/tb_systolic_array.sv \
        -top tb_systolic_array \
        -log reports/sim_${DATASET_NAME}.log \
        +incdir+rtl/ \
        2>&1 | tail -20

    # Move output files
    if [ -f "waves/systolic.vcd" ]; then
        mv waves/systolic.vcd "waves/${DATASET_NAME}.vcd"
        echo "  → VCD: waves/${DATASET_NAME}.vcd"
    fi
    if [ -f "waves/activity.saif" ]; then
        mv waves/activity.saif "waves/${DATASET_NAME}.saif"
        echo "  → SAIF: waves/${DATASET_NAME}.saif"
    fi

    echo "[SIM] $DATASET_NAME simulation complete."
}

###############################################################
# Helper function: Run Genus synthesis with SAIF
###############################################################
run_synth() {
    local DATASET_NAME=$1
    local SAIF_PATH=$2

    echo ""
    echo "[SYNTH] Running Genus synthesis: $DATASET_NAME"

    if [ -n "$SAIF_PATH" ] && [ -f "$SAIF_PATH" ]; then
        export SAIF_FILE="$ROOT/$SAIF_PATH"
        echo "  → Using SAIF: $SAIF_FILE"
    else
        unset SAIF_FILE
        echo "  → No SAIF file (functional synthesis only)"
    fi

    cd scripts
    genus -f synth.tcl > ../reports/genus_${DATASET_NAME}.log 2>&1
    cd "$ROOT"

    # Save reports with dataset prefix
    for rpt in area_report timing_report power_report power_by_hierarchy; do
        if [ -f "reports/${rpt}.rpt" ]; then
            cp "reports/${rpt}.rpt" "reports/${rpt}_${DATASET_NAME}.rpt"
        fi
    done

    echo "[SYNTH] $DATASET_NAME synthesis complete."
}

###############################################################
# STEP 2: Run simulations
###############################################################
echo ""
echo "============================================="
echo "[STEP 2] Running simulations..."
echo "============================================="

run_sim "dense"    "data/dense"
run_sim "sparse50" "data/sparse50"
run_sim "sparse80" "data/sparse80"
run_sim "sparse90" "data/sparse90"
run_sim "blackout" "data/blackout"

###############################################################
# STEP 3: Run synthesis (dense & sparse90 — key comparison)
###############################################################
echo ""
echo "============================================="
echo "[STEP 3] Running synthesis..."
echo "============================================="

run_synth "dense"    "waves/dense.saif"
run_synth "sparse90" "waves/sparse90.saif"

###############################################################
# STEP 4: Summary
###############################################################
echo ""
echo "============================================="
echo "[STEP 4] RESULTS SUMMARY"
echo "============================================="

echo ""
echo "--- Dense Power Report ---"
grep -i "total" reports/power_report_dense.rpt 2>/dev/null || echo "  (not available)"

echo ""
echo "--- Sparse-90 Power Report ---"
grep -i "total" reports/power_report_sparse90.rpt 2>/dev/null || echo "  (not available)"

echo ""
echo "--- Area Report (dense) ---"
grep -i "total" reports/area_report_dense.rpt 2>/dev/null || echo "  (not available)"

echo ""
echo "--- Timing Report (dense) ---"
grep -i "slack" reports/timing_report_dense.rpt 2>/dev/null || echo "  (not available)"

echo ""
echo "--- Clock Gating ---"
if [ -f "reports/clock_gating.rpt" ]; then
    cat reports/clock_gating.rpt
else
    echo "  (clock gating report not available)"
fi

echo ""
echo "============================================="
echo " ALL DONE!"
echo " Reports: $ROOT/reports/"
echo " Netlists: $ROOT/netlist/"
echo " Waves: $ROOT/waves/"
echo "============================================="
echo ""
echo "To extract power reduction percentage, run:"
echo "  python3 scripts/parse_power.py reports/power_report_dense.rpt reports/power_report_sparse90.rpt"
