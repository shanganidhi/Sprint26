#!/usr/bin/env python3
"""
plot_power.py — Generate a bar chart comparing dense vs sparse power.

Usage:
    python3 plot_power.py

Edit the VALUES below with your actual Genus report numbers.
"""
import matplotlib
matplotlib.use('Agg')  # non-interactive backend
import matplotlib.pyplot as plt
import numpy as np

# =====================================================
# EDIT THESE VALUES with your actual Genus power numbers
# Units: milliWatts (mW)
# =====================================================
labels     = ['Dense\n(0%)', 'Sparse-50\n(50%)', 'Sparse-80\n(80%)', 'Sparse-90\n(90%)', 'Blackout\n(100%)']
# Example placeholder values (replace with actuals!)
total_power   = [3.20, 2.10, 1.40, 1.10, 0.70]
dynamic_power = [2.50, 1.50, 0.85, 0.60, 0.15]
leakage_power = [0.70, 0.60, 0.55, 0.50, 0.55]

# =====================================================
# Plot
# =====================================================
x = np.arange(len(labels))
width = 0.25

fig, ax = plt.subplots(figsize=(10, 6))

bars1 = ax.bar(x - width, total_power,   width, label='Total Power',    color='#2196F3', edgecolor='white')
bars2 = ax.bar(x,         dynamic_power, width, label='Dynamic Power',  color='#FF5722', edgecolor='white')
bars3 = ax.bar(x + width, leakage_power, width, label='Leakage Power',  color='#4CAF50', edgecolor='white')

# Labels and formatting
ax.set_xlabel('Sparsity Level', fontsize=12, fontweight='bold')
ax.set_ylabel('Power (mW)', fontsize=12, fontweight='bold')
ax.set_title('Dynamic Power vs Sparsity Level\n4×4 INT8 Weight-Stationary Systolic Array', fontsize=14, fontweight='bold')
ax.set_xticks(x)
ax.set_xticklabels(labels)
ax.legend(loc='upper right', fontsize=11)
ax.grid(axis='y', alpha=0.3, linestyle='--')

# Add value labels on bars
for bars in [bars1, bars2, bars3]:
    for bar in bars:
        height = bar.get_height()
        ax.annotate(f'{height:.2f}',
                    xy=(bar.get_x() + bar.get_width() / 2, height),
                    xytext=(0, 3), textcoords="offset points",
                    ha='center', va='bottom', fontsize=8)

# Add reduction percentage annotation
if total_power[0] > 0:
    reduction = 100 * (total_power[0] - total_power[3]) / total_power[0]
    ax.annotate(f'↓ {reduction:.0f}% reduction',
                xy=(3, total_power[3]),
                xytext=(3.3, total_power[0] * 0.7),
                fontsize=11, fontweight='bold', color='red',
                arrowprops=dict(arrowstyle='->', color='red', lw=1.5))

plt.tight_layout()
plt.savefig('reports/power_vs_sparsity.png', dpi=150, bbox_inches='tight')
plt.savefig('reports/power_vs_sparsity.pdf', bbox_inches='tight')
print("Saved: reports/power_vs_sparsity.png and reports/power_vs_sparsity.pdf")
