#!/usr/bin/env python3
"""
parse_power.py — Extract and compare power numbers from Genus reports.

Usage:
    python3 parse_power.py reports/power_report_dense.rpt reports/power_report_sparse90.rpt
"""
import re
import sys


def extract_power(filename):
    """Extract power values from a Genus power report."""
    results = {}
    try:
        with open(filename, 'r') as f:
            text = f.read()

        # Try multiple patterns (Genus report format varies)
        patterns = {
            'total':    [r'Total\s+Power\s*[:\s]+([\d\.eE\+\-]+)',
                         r'Total\s+([\d\.eE\+\-]+)\s+'],
            'dynamic':  [r'Dynamic\s+Power\s*[:\s]+([\d\.eE\+\-]+)',
                         r'Internal\s+Power\s*[:\s]+([\d\.eE\+\-]+)'],
            'switching':[r'Switching\s+Power\s*[:\s]+([\d\.eE\+\-]+)',
                         r'Net\s+Switching\s+Power\s*[:\s]+([\d\.eE\+\-]+)'],
            'leakage':  [r'Leakage\s+Power\s*[:\s]+([\d\.eE\+\-]+)',
                         r'Cell\s+Leakage\s+Power\s*[:\s]+([\d\.eE\+\-]+)'],
        }

        for key, pats in patterns.items():
            for pat in pats:
                m = re.search(pat, text, re.IGNORECASE)
                if m:
                    results[key] = float(m.group(1))
                    break

    except FileNotFoundError:
        print(f"ERROR: File not found: {filename}")
        return None

    return results


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 parse_power.py <report1> [report2]")
        sys.exit(1)

    files = sys.argv[1:]
    all_results = {}

    for fname in files:
        result = extract_power(fname)
        if result:
            all_results[fname] = result
            print(f"\n{'='*50}")
            print(f"Report: {fname}")
            print(f"{'='*50}")
            for key, val in result.items():
                print(f"  {key:15s}: {val:.6e} W")

    # Compare if two reports provided
    if len(all_results) == 2:
        keys = list(all_results.keys())
        r1 = all_results[keys[0]]
        r2 = all_results[keys[1]]

        print(f"\n{'='*50}")
        print(f"COMPARISON: {keys[0]} vs {keys[1]}")
        print(f"{'='*50}")

        for metric in ['total', 'dynamic', 'switching', 'leakage']:
            if metric in r1 and metric in r2:
                v1 = r1[metric]
                v2 = r2[metric]
                if v1 > 0:
                    reduction = 100.0 * (v1 - v2) / v1
                    print(f"  {metric:15s}: {v1:.4e} → {v2:.4e}  ({reduction:+.1f}% change)")
                else:
                    print(f"  {metric:15s}: {v1:.4e} → {v2:.4e}")

        # Highlight total power reduction
        if 'total' in r1 and 'total' in r2 and r1['total'] > 0:
            pct = 100.0 * (r1['total'] - r2['total']) / r1['total']
            print(f"\n  ★ TOTAL POWER REDUCTION: {pct:.1f}%")


if __name__ == "__main__":
    main()
