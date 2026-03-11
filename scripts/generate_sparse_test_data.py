#!/usr/bin/env python3
"""
generate_sparse_test_data.py
Generate dense/sparse activation and weight matrices for systolic array testing.

Usage:
    python3 generate_sparse_test_data.py --sparsity 0.0 --outdir data       # Dense
    python3 generate_sparse_test_data.py --sparsity 0.9 --outdir data       # 90% sparse
    python3 generate_sparse_test_data.py --sparsity 1.0 --outdir data       # Blackout (all zeros)
"""
import numpy as np
import argparse
import os

SIZE = 4
DATA_WIDTH = 8  # INT8: range -128..127


def to_twos_complement_hex(val, bits=8):
    """Convert signed integer to 2's complement hex string."""
    if val < 0:
        val = (1 << bits) + val
    return format(val & ((1 << bits) - 1), f'0{bits // 4}x')


def save_hex_matrix(mat, fname, bits=8):
    """Save matrix values as hex file, one value per line, row-major."""
    with open(fname, "w") as f:
        for r in range(mat.shape[0]):
            for c in range(mat.shape[1]):
                f.write(to_twos_complement_hex(int(mat[r, c]), bits) + "\n")


def generate_matrices(sparsity, seed=42):
    """Generate activation and weight matrices with given sparsity level."""
    np.random.seed(seed)

    # Values in INT8 range but kept small for manageable golden values
    matA = np.random.randint(-8, 9, (SIZE, SIZE)).astype(np.int32)
    matB = np.random.randint(-8, 9, (SIZE, SIZE)).astype(np.int32)

    # Apply sparsity: zero out elements randomly
    if sparsity > 0:
        maskA = np.random.rand(SIZE, SIZE) < sparsity
        maskB = np.random.rand(SIZE, SIZE) < sparsity
        matA[maskA] = 0
        matB[maskB] = 0

    # Compute golden result: C = A * B
    golden = matA.dot(matB)

    return matA, matB, golden


def write_all(outdir, sparsity, seed=42):
    """Generate and write all data files."""
    os.makedirs(outdir, exist_ok=True)

    A, B, G = generate_matrices(sparsity, seed)

    # Save hex files
    save_hex_matrix(A, os.path.join(outdir, "activations.hex"), bits=8)
    save_hex_matrix(B, os.path.join(outdir, "weights.hex"), bits=8)
    save_hex_matrix(G, os.path.join(outdir, "golden.hex"), bits=32)

    # Print summary
    total_elements = SIZE * SIZE
    a_zeros = np.sum(A == 0)
    b_zeros = np.sum(B == 0)

    print(f"Generated data with sparsity={sparsity:.1%} (seed={seed}) in {outdir}/")
    print(f"  Activation zeros: {a_zeros}/{total_elements} ({a_zeros/total_elements:.0%})")
    print(f"  Weight zeros:     {b_zeros}/{total_elements} ({b_zeros/total_elements:.0%})")
    print(f"\nMatrix A (activations):\n{A}")
    print(f"\nMatrix B (weights):\n{B}")
    print(f"\nGolden C = A*B:\n{G}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate test data for systolic array")
    parser.add_argument("--sparsity", type=float, default=0.0,
                        help="Fraction of elements to zero out (0.0=dense, 1.0=blackout)")
    parser.add_argument("--outdir", type=str, default="data",
                        help="Output directory for hex files")
    parser.add_argument("--seed", type=int, default=42,
                        help="Random seed for reproducibility")
    args = parser.parse_args()

    write_all(args.outdir, args.sparsity, args.seed)
