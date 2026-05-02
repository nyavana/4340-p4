#!/bin/bash
# Ablation sweep: runs 7 configurations, saves outputs to output/sweep_<tag>/
set -e

REPO=/user/stud/spring26/cy2822/4340/4340-p4-verify-merged-features
cd "$REPO"

declare -A SWEEPS
SWEEPS[all_on]=""
SWEEPS[no_etb]="+define+DISABLE_EARLY_TAG"
SWEEPS[no_gshare]="+define+DISABLE_GSHARE"
SWEEPS[no_ras]="+define+DISABLE_RAS"
SWEEPS[no_stlf]="+define+DISABLE_STLF"
SWEEPS[no_prefetch]="+define+DISABLE_PREFETCH"
SWEEPS[no_advanced]="+define+DISABLE_EARLY_TAG +define+DISABLE_GSHARE +define+DISABLE_RAS +define+DISABLE_STLF +define+DISABLE_PREFETCH"

TAGS="all_on no_etb no_gshare no_ras no_stlf no_prefetch no_advanced"

for TAG in $TAGS; do
    DEFINES="${SWEEPS[$TAG]}"
    OUTDIR="$REPO/output/sweep_${TAG}"
    mkdir -p "$OUTDIR"

    echo "===== Running sweep: $TAG ====="
    echo "  EXTRA_DEFINES: '$DEFINES'"

    # Clean executables (not programs)
    make clean_exe 2>/dev/null || true
    rm -rf output/*.out output/*.wb output/*.ppln 2>/dev/null || true

    # Build simv
    if [ -z "$DEFINES" ]; then
        make simv
    else
        make EXTRA_DEFINES="$DEFINES" simv
    fi

    # Run all programs in parallel
    if [ -z "$DEFINES" ]; then
        make simulate_all -j8 2>&1 | tee "$OUTDIR/make_log.txt" || true
    else
        make EXTRA_DEFINES="$DEFINES" simulate_all -j8 2>&1 | tee "$OUTDIR/make_log.txt" || true
    fi

    # Copy outputs
    cp output/*.out "$OUTDIR/" 2>/dev/null || true
    echo "  Saved to $OUTDIR"
done

echo "All sweeps done."
