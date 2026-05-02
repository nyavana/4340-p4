#!/usr/bin/env python3
"""
Parse ablation sweep output files and produce the per-feature-ablation table.
"""

import os
import re
import math

REPO = "/user/stud/spring26/cy2822/4340/4340-p4-verify-merged-features"

PROGRAMS = [
    "alexnet", "backtrack", "basic_malloc", "bfs", "btest1", "btest2",
    "copy", "copy_long", "dft", "evens", "evens_long", "fc_forward",
    "fib", "fib_long", "fib_rec", "graph", "haha", "halt",
    "insertion", "insertionsort", "matrix_mult_rec", "mergesort",
    "mult", "mult_no_lsq", "no_hazard", "omegalul",
    "outer_product", "parallel", "priority_queue", "quicksort",
    "sampler", "saxpy", "sort_search"
]

TAGS = ["all_on", "no_etb", "no_gshare", "no_ras", "no_stlf", "no_prefetch", "no_advanced"]

TAG_LABEL = {
    "all_on":       "all_on",
    "no_etb":       "no_etb (−ETB)",
    "no_gshare":    "no_gshare (−gshare)",
    "no_ras":       "no_ras (−RAS)",
    "no_stlf":      "no_stlf (−STLF)",
    "no_prefetch":  "no_prefetch (−prefetch)",
    "no_advanced":  "no_advanced (−all 5)",
}

CYC_RE  = re.compile(r'@@\s+(\d+)\s+cycles\s*/\s*(\d+)\s+instrs\s*=\s*([\d.]+)\s+CPI')

def parse_out(path):
    """Return (cycles, instrs, cpi) or None if halted but no CPI found, or raise on not-halt."""
    if not os.path.exists(path):
        return None
    with open(path) as f:
        content = f.read()
    # must see halt marker
    if "System halted" not in content and "WFI" not in content:
        return None  # did not halt
    m = CYC_RE.search(content)
    if not m:
        return None
    cycles = int(m.group(1))
    instrs = int(m.group(2))
    cpi    = float(m.group(3))
    return (cycles, instrs, cpi)


def load_all():
    data = {}  # data[tag][prog] = (cycles, instrs, cpi) or None
    for tag in TAGS:
        data[tag] = {}
        sweep_dir = os.path.join(REPO, "output", f"sweep_{tag}")
        for prog in PROGRAMS:
            out_path = os.path.join(sweep_dir, f"{prog}.out")
            data[tag][prog] = parse_out(out_path)
    return data


def delta_pct(new_val, base_val):
    if base_val is None or base_val == 0:
        return None
    return 100.0 * (new_val - base_val) / base_val


def geomean(values):
    """Geomean of a list of floats (all must be > 0)."""
    vals = [v for v in values if v is not None]
    if not vals:
        return None
    return math.exp(sum(math.log(v) for v in vals) / len(vals))


def main():
    data = load_all()

    # Check for missing/non-halted programs
    failed = []
    for tag in TAGS:
        for prog in PROGRAMS:
            if data[tag][prog] is None:
                failed.append((tag, prog))

    if failed:
        print("WARNING: Missing or non-halted programs:")
        for tag, prog in failed:
            print(f"  {tag} / {prog}")
        print()

    # Build the big table
    # Columns: program, cycles_all_on, cpi_all_on,
    #   for each non-all_on tag: cycles_X, Δ%_X
    feature_tags = [t for t in TAGS if t != "all_on"]

    # Print table
    # Header
    header = "| Program | cycles_all_on | cpi_all_on"
    for ft in feature_tags:
        header += f" | cycles_{ft} | Δ%_{ft}"
    header += " |"
    print(header)

    sep = "| --- | ---: | ---:"
    for _ in feature_tags:
        sep += " | ---: | ---:"
    sep += " |"
    print(sep)

    geomean_inputs = {ft: [] for ft in feature_tags}

    for prog in PROGRAMS:
        base = data["all_on"][prog]
        if base is None:
            row = f"| {prog} | N/A | N/A"
            for ft in feature_tags:
                row += " | N/A | N/A"
            row += " |"
            print(row)
            continue

        cyc0, ins0, cpi0 = base
        row = f"| {prog} | {cyc0:,} | {cpi0:.3f}"

        for ft in feature_tags:
            entry = data[ft][prog]
            if entry is None:
                row += " | N/A | N/A"
            else:
                cyc_ft, _, _ = entry
                dpct = delta_pct(cyc_ft, cyc0)
                row += f" | {cyc_ft:,} | {dpct:+.2f}%"
                if dpct is not None:
                    # Use ratio for geomean: cyc_ft/cyc0
                    geomean_inputs[ft].append(cyc_ft / cyc0)
        row += " |"
        print(row)

    # Geomean row
    print()
    gm_row = "| **geomean ratio** | | "
    for ft in feature_tags:
        vals = geomean_inputs[ft]
        if vals:
            gm = geomean(vals)
            dpct = (gm - 1.0) * 100.0
            gm_row += f" | | {dpct:+.2f}%"
        else:
            gm_row += " | | N/A"
    gm_row += " |"
    print(gm_row)


if __name__ == "__main__":
    main()
