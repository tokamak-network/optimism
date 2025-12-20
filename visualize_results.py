#!/usr/bin/env python3
"""
RAT Experiment Visualization Script (RAT Performance)
4 Core Graphs: T_proc Distribution, Timing Breakdown, Proof Timing, L2 Load
Academic style: minimal colors, hatch patterns for differentiation
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from pathlib import Path
import argparse
import sys
import re
from datetime import datetime

# ============================================================================
# Publication Style Configuration (Academic/Minimal)
# ============================================================================
plt.style.use('seaborn-v0_8-whitegrid')

plt.rcParams.update({
    'font.family': 'serif',
    'font.serif': ['Times New Roman', 'DejaVu Serif', 'serif'],
    'font.size': 11,
    'axes.titlesize': 12,
    'axes.labelsize': 11,
    'xtick.labelsize': 10,
    'ytick.labelsize': 10,
    'legend.fontsize': 9,
    'figure.titlesize': 14,
    'figure.dpi': 150,
    'savefig.dpi': 300,
    'savefig.bbox': 'tight',
    'axes.linewidth': 0.8,
    'grid.linewidth': 0.5,
    'lines.linewidth': 1.5,
    'axes.labelcolor': 'black',
    'xtick.color': 'black',
    'ytick.color': 'black',
})

# Minimal color palette - grayscale with one accent
COLORS = {
    'primary': '#333333',      # Dark gray
    'secondary': '#888888',    # Medium gray
    'light': '#CCCCCC',        # Light gray
    'accent': '#2E86AB',       # Blue accent (used sparingly)
}

# Region markers for scatter plots
REGION_MARKERS = {'US': 'o', 'EU': 's', 'ASIA': '^'}
REGION_ORDER = ['US', 'EU', 'ASIA']
REGION_LABELS = {'US': 'US', 'EU': 'EU', 'ASIA': 'Asia'}

# ============================================================================
# Data Loading
# ============================================================================

def load_timing_data(csv_path: str) -> pd.DataFrame:
    """Load timing metrics from CSV."""
    df = pd.read_csv(csv_path)
    df['region_full'] = df['region']
    df['region'] = df['region'].str.extract(r'VAL-(\w+)-\d+')[0]
    for col in ['T_proc_ms', 'T_net_ms', 'T_total_ms']:
        df[col] = pd.to_numeric(df[col], errors='coerce')
    return df

def load_proof_timings(results_dir: Path) -> pd.DataFrame:
    """Parse validator logs to extract individual proof submission timestamps."""
    data = []
    pattern = re.compile(r't=(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})')

    for log_file in results_dir.glob('validator_VAL-*.log'):
        region = log_file.stem.split('_')[1]
        region_short = region.split('-')[1]

        with open(log_file, 'r') as f:
            for line in f:
                if 'Evidence Submitted Successfully' in line:
                    match = pattern.search(line)
                    if match:
                        ts = datetime.strptime(match.group(1), '%Y-%m-%dT%H:%M:%S')
                        data.append({'timestamp': ts, 'region': region_short})

    if not data:
        return pd.DataFrame()

    df = pd.DataFrame(data)
    df = df.sort_values('timestamp')
    return df

def load_spammer_data(results_dir: Path) -> pd.DataFrame:
    """Parse spammer log to extract transaction throughput."""
    spammer_log = results_dir / 'spammer.log'
    if not spammer_log.exists():
        return pd.DataFrame()

    data = []
    pattern = re.compile(r'(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}).*Burst: Sent (\d+) txs')

    with open(spammer_log, 'r') as f:
        for line in f:
            match = pattern.search(line)
            if match:
                ts = datetime.strptime(match.group(1), '%Y/%m/%d %H:%M:%S')
                txs = int(match.group(2))
                data.append({'timestamp': ts, 'txs': txs})

    if not data:
        return pd.DataFrame()

    df = pd.DataFrame(data)
    df = df.sort_values('timestamp')
    return df

# ============================================================================
# Visualization Functions
# ============================================================================

def create_combined_figure(df: pd.DataFrame, proof_df: pd.DataFrame,
                           spammer_df: pd.DataFrame, output_dir: Path):
    """Create combined 4-panel figure with academic style."""

    fig, axes = plt.subplots(2, 2, figsize=(12, 8))
    axes = axes.flatten()

    # =========================================================================
    # Panel (a): T_proc Distribution (Clean Violin - no scatter points)
    # =========================================================================
    ax1 = axes[0]

    data_by_region = [df[df['region'] == r]['T_proc_ms'].dropna().values for r in REGION_ORDER]

    # Violin plot - grayscale
    parts = ax1.violinplot(data_by_region, positions=range(len(REGION_ORDER)),
                           showmeans=True, showmedians=True)

    # Style all violins in grayscale
    for pc in parts['bodies']:
        pc.set_facecolor(COLORS['light'])
        pc.set_edgecolor(COLORS['primary'])
        pc.set_alpha(0.8)

    # Style lines
    for partname in ['cbars', 'cmins', 'cmaxes', 'cmeans', 'cmedians']:
        if partname in parts:
            parts[partname].set_color(COLORS['primary'])
            parts[partname].set_linewidth(1.5)

    ax1.set_ylabel('Processing Time $T_{proc}$ (ms)')
    ax1.set_xlabel('Region')
    ax1.set_title('(a) Processing Time Distribution')
    ax1.set_xticks(range(len(REGION_ORDER)))
    ax1.set_xticklabels([REGION_LABELS[r] for r in REGION_ORDER])
    ax1.yaxis.grid(True, linestyle='--', alpha=0.5)
    ax1.set_axisbelow(True)

    # Add mean labels
    for i, data in enumerate(data_by_region):
        if len(data) > 0:
            mean_val = np.mean(data)
            ax1.annotate(f'{mean_val:.0f}ms', (i, mean_val + 40), ha='center', fontsize=9)

    # =========================================================================
    # Panel (b): Timing Breakdown (Hatched bars, black Y-axis labels)
    # =========================================================================
    ax2 = axes[1]
    ax2_right = ax2.twinx()

    stats = df.groupby('region').agg({
        'T_proc_ms': 'mean',
        'T_net_ms': 'mean',
    }).reindex(REGION_ORDER)

    x = np.arange(len(REGION_ORDER))
    width = 0.35

    # Left axis: T_proc (solid fill)
    bars1 = ax2.bar(x - width/2, stats['T_proc_ms'], width,
                    label='$T_{proc}$', color=COLORS['primary'], alpha=0.9)

    # Right axis: T_net (hatched, lighter color)
    bars2 = ax2_right.bar(x + width/2, stats['T_net_ms'], width,
                          label='$T_{net}$', color=COLORS['light'],
                          edgecolor=COLORS['primary'], hatch='///', linewidth=1)

    # Black axis labels
    ax2.set_ylabel('$T_{proc}$ (ms)')
    ax2_right.set_ylabel('$T_{net}$ (ms)')
    ax2.set_xlabel('Region')
    ax2.set_title('(b) Timing Breakdown')
    ax2.set_xticks(x)
    ax2.set_xticklabels([REGION_LABELS[r] for r in REGION_ORDER])

    ax2.set_ylim(0, 300)
    ax2_right.set_ylim(0, 15000)

    # Value labels on bars
    for bar in bars1:
        height = bar.get_height()
        ax2.annotate(f'{height:.0f}', (bar.get_x() + bar.get_width()/2, height),
                     ha='center', va='bottom', fontsize=9)

    for bar in bars2:
        height = bar.get_height()
        ax2_right.annotate(f'{height:.0f}', (bar.get_x() + bar.get_width()/2, height),
                           ha='center', va='bottom', fontsize=9)

    # Combined legend - outside
    lines1, labels1 = ax2.get_legend_handles_labels()
    lines2, labels2 = ax2_right.get_legend_handles_labels()
    ax2.legend(lines1 + lines2, labels1 + labels2, loc='upper left', framealpha=0.9)

    ax2.yaxis.grid(True, linestyle='--', alpha=0.5)
    ax2.set_axisbelow(True)

    # =========================================================================
    # Panel (c): Proof Submission Timing (Scatter with colors)
    # =========================================================================
    ax3 = axes[2]

    # Regional colors for this panel only
    region_colors = {'US': '#2E86AB', 'EU': '#E63946', 'ASIA': '#2A9D8F'}

    if not proof_df.empty:
        proof_df = proof_df.copy()
        start_time = proof_df['timestamp'].min()
        proof_df['elapsed'] = (proof_df['timestamp'] - start_time).dt.total_seconds()

        # Scatter plot - each proof event as a point with colors
        y_positions = {'US': 3, 'EU': 2, 'ASIA': 1}

        for i, region in enumerate(REGION_ORDER):
            region_data = proof_df[proof_df['region'] == region]
            if not region_data.empty:
                y = [y_positions[region]] * len(region_data)
                ax3.scatter(region_data['elapsed'], y,
                           marker=REGION_MARKERS[region],
                           s=70, c=region_colors[region], alpha=0.8,
                           label=REGION_LABELS[region], edgecolors='white', linewidths=0.5)

        ax3.set_xlabel('Elapsed Time (seconds)')
        ax3.set_ylabel('Region')
        ax3.set_title('(c) Proof Submission Timeline')
        ax3.set_yticks([1, 2, 3])
        ax3.set_yticklabels(['Asia', 'EU', 'US'])
        ax3.set_ylim(0.5, 3.5)
        ax3.set_xlim(left=0)
        ax3.legend(loc='center left', bbox_to_anchor=(1.02, 0.5), framealpha=0.9)
        ax3.xaxis.grid(True, linestyle='--', alpha=0.5)
        ax3.set_axisbelow(True)
    else:
        ax3.text(0.5, 0.5, 'No proof data', ha='center', va='center',
                transform=ax3.transAxes, fontsize=12, color='gray')
        ax3.set_title('(c) Proof Submission Timeline')

    # =========================================================================
    # Panel (d): L2 Transaction Load (Minimal style)
    # =========================================================================
    ax4 = axes[3]

    if not spammer_df.empty:
        spammer_df = spammer_df.copy()
        start_time = spammer_df['timestamp'].min()
        spammer_df['elapsed'] = (spammer_df['timestamp'] - start_time).dt.total_seconds()

        # Bar chart - grayscale
        ax4.bar(spammer_df['elapsed'], spammer_df['txs'], width=0.9,
                color=COLORS['light'], edgecolor=COLORS['secondary'], linewidth=0.5)

        # Moving average line
        if len(spammer_df) >= 5:
            spammer_df['txs_ma'] = spammer_df['txs'].rolling(window=10, center=True).mean()
            ax4.plot(spammer_df['elapsed'], spammer_df['txs_ma'],
                    color=COLORS['primary'], linewidth=2, label='10-pt MA')

        # Target line
        target_tps = 100
        ax4.axhline(y=target_tps, color=COLORS['primary'], linestyle='--',
                   alpha=0.7, linewidth=1.5)

        avg_tps = spammer_df['txs'].mean()

        ax4.set_xlabel('Elapsed Time (seconds)')
        ax4.set_ylabel('Transactions per Second')
        ax4.set_title(f'(d) L2 Transaction Load (Avg: {avg_tps:.0f} TPS)')
        ax4.set_ylim(bottom=0)
        ax4.legend(loc='upper right', framealpha=0.9)
        ax4.yaxis.grid(True, linestyle='--', alpha=0.5)
        ax4.set_axisbelow(True)
    else:
        ax4.text(0.5, 0.5, 'No spammer data', ha='center', va='center',
                transform=ax4.transAxes, fontsize=12, color='gray')
        ax4.set_title('(d) L2 Transaction Load')

    # =========================================================================
    # Final Layout - Show combined view
    # =========================================================================
    fig.suptitle('RAT Protocol Performance Analysis', fontsize=14, fontweight='bold', y=1.01)
    plt.tight_layout()

    # Show combined figure
    plt.show()

    # =========================================================================
    # Save individual figures without titles
    # =========================================================================
    output_dir.mkdir(parents=True, exist_ok=True)

    # Save each panel as individual PDF
    save_individual_figures(df, proof_df, spammer_df, output_dir)

    return fig

def save_individual_figures(df, proof_df, spammer_df, output_dir):
    """Save each panel as individual PDF without title."""

    # Regional colors for panel c
    region_colors = {'US': '#2E86AB', 'EU': '#E63946', 'ASIA': '#2A9D8F'}

    # --- Figure 1: Processing Time Distribution ---
    fig1, ax1 = plt.subplots(figsize=(5, 3.5))
    data_by_region = [df[df['region'] == r]['T_proc_ms'].dropna().values for r in REGION_ORDER]
    parts = ax1.violinplot(data_by_region, positions=range(len(REGION_ORDER)),
                           showmeans=True, showmedians=True)
    for pc in parts['bodies']:
        pc.set_facecolor(COLORS['light'])
        pc.set_edgecolor(COLORS['primary'])
        pc.set_alpha(0.8)
    for partname in ['cbars', 'cmins', 'cmaxes', 'cmeans', 'cmedians']:
        if partname in parts:
            parts[partname].set_color(COLORS['primary'])
            parts[partname].set_linewidth(1.5)
    ax1.set_ylabel('Processing Time $T_{proc}$ (ms)')
    ax1.set_xlabel('Region')
    ax1.set_xticks(range(len(REGION_ORDER)))
    ax1.set_xticklabels([REGION_LABELS[r] for r in REGION_ORDER])
    ax1.yaxis.grid(True, linestyle='--', alpha=0.5)
    for i, data in enumerate(data_by_region):
        if len(data) > 0:
            ax1.annotate(f'{np.mean(data):.0f}ms', (i, np.mean(data) + 40), ha='center', fontsize=9)
    plt.tight_layout()
    fig1.savefig(output_dir / 'fig_a_processing_time.pdf', bbox_inches='tight')
    plt.close(fig1)
    print(f"✅ Saved: {output_dir / 'fig_a_processing_time.pdf'}")

    # --- Figure 2: Timing Breakdown ---
    fig2, ax2 = plt.subplots(figsize=(5, 3.5))
    ax2_right = ax2.twinx()
    stats = df.groupby('region').agg({'T_proc_ms': 'mean', 'T_net_ms': 'mean'}).reindex(REGION_ORDER)
    x = np.arange(len(REGION_ORDER))
    width = 0.35
    bars1 = ax2.bar(x - width/2, stats['T_proc_ms'], width, label='$T_{proc}$', color=COLORS['primary'], alpha=0.9)
    bars2 = ax2_right.bar(x + width/2, stats['T_net_ms'], width, label='$T_{net}$',
                          color=COLORS['light'], edgecolor=COLORS['primary'], hatch='///', linewidth=1)
    ax2.set_ylabel('$T_{proc}$ (ms)')
    ax2_right.set_ylabel('$T_{net}$ (ms)')
    ax2.set_xlabel('Region')
    ax2.set_xticks(x)
    ax2.set_xticklabels([REGION_LABELS[r] for r in REGION_ORDER])
    ax2.set_ylim(0, 300)
    ax2_right.set_ylim(0, 15000)
    for bar in bars1:
        ax2.annotate(f'{bar.get_height():.0f}', (bar.get_x() + bar.get_width()/2, bar.get_height()),
                     ha='center', va='bottom', fontsize=9)
    for bar in bars2:
        ax2_right.annotate(f'{bar.get_height():.0f}', (bar.get_x() + bar.get_width()/2, bar.get_height()),
                           ha='center', va='bottom', fontsize=9)
    lines1, labels1 = ax2.get_legend_handles_labels()
    lines2, labels2 = ax2_right.get_legend_handles_labels()
    ax2.legend(lines1 + lines2, labels1 + labels2, loc='upper left', framealpha=0.9)
    ax2.yaxis.grid(True, linestyle='--', alpha=0.5)
    plt.tight_layout()
    fig2.savefig(output_dir / 'fig_b_timing_breakdown.pdf', bbox_inches='tight')
    plt.close(fig2)
    print(f"✅ Saved: {output_dir / 'fig_b_timing_breakdown.pdf'}")

    # --- Figure 3: Proof Submission Timeline ---
    fig3, ax3 = plt.subplots(figsize=(5, 3.5))
    if not proof_df.empty:
        proof_df_copy = proof_df.copy()
        start_time = proof_df_copy['timestamp'].min()
        proof_df_copy['elapsed'] = (proof_df_copy['timestamp'] - start_time).dt.total_seconds()
        y_positions = {'US': 3, 'EU': 2, 'ASIA': 1}
        for region in REGION_ORDER:
            region_data = proof_df_copy[proof_df_copy['region'] == region]
            if not region_data.empty:
                y = [y_positions[region]] * len(region_data)
                ax3.scatter(region_data['elapsed'], y, marker=REGION_MARKERS[region],
                           s=70, c=region_colors[region], alpha=0.8,
                           label=REGION_LABELS[region], edgecolors='white', linewidths=0.5)
        ax3.set_xlabel('Elapsed Time (seconds)')
        ax3.set_ylabel('Region')
        ax3.set_yticks([1, 2, 3])
        ax3.set_yticklabels(['Asia', 'EU', 'US'])
        ax3.set_ylim(0.5, 3.5)
        ax3.set_xlim(left=0)
        # Legend removed - Y-axis labels already show regions
        ax3.xaxis.grid(True, linestyle='--', alpha=0.5)
    plt.tight_layout()
    fig3.savefig(output_dir / 'fig_c_proof_timeline.pdf', bbox_inches='tight')
    plt.close(fig3)
    print(f"✅ Saved: {output_dir / 'fig_c_proof_timeline.pdf'}")

    # --- Figure 4: L2 Transaction Load ---
    fig4, ax4 = plt.subplots(figsize=(5, 3.5))
    if not spammer_df.empty:
        spammer_df_copy = spammer_df.copy()
        start_time = spammer_df_copy['timestamp'].min()
        spammer_df_copy['elapsed'] = (spammer_df_copy['timestamp'] - start_time).dt.total_seconds()
        ax4.bar(spammer_df_copy['elapsed'], spammer_df_copy['txs'], width=0.9,
                color=COLORS['light'], edgecolor=COLORS['secondary'], linewidth=0.5)
        if len(spammer_df_copy) >= 5:
            spammer_df_copy['txs_ma'] = spammer_df_copy['txs'].rolling(window=10, center=True).mean()
            ax4.plot(spammer_df_copy['elapsed'], spammer_df_copy['txs_ma'],
                    color=COLORS['primary'], linewidth=2, label='10-pt MA')
        ax4.axhline(y=100, color=COLORS['primary'], linestyle='--', alpha=0.7, linewidth=1.5)
        ax4.set_xlabel('Elapsed Time (seconds)')
        ax4.set_ylabel('Transactions per Second')
        ax4.set_ylim(bottom=0)
        ax4.legend(loc='upper right', framealpha=0.9)
        ax4.yaxis.grid(True, linestyle='--', alpha=0.5)
    plt.tight_layout()
    fig4.savefig(output_dir / 'fig_d_l2_load.pdf', bbox_inches='tight')
    plt.close(fig4)
    print(f"✅ Saved: {output_dir / 'fig_d_l2_load.pdf'}")

# ============================================================================
# Main
# ============================================================================

def main():
    parser = argparse.ArgumentParser(description='RAT Experiment Visualization')
    parser.add_argument('--input', '-i', type=str, required=True,
                        help='Path to results directory or timing_metrics.csv')
    parser.add_argument('--output', '-o', type=str, default=None,
                        help='Output directory (default: input/figures)')

    args = parser.parse_args()

    input_path = Path(args.input)
    if input_path.is_dir():
        csv_path = input_path / 'timing_metrics.csv'
        results_dir = input_path
    else:
        csv_path = input_path
        results_dir = csv_path.parent

    if not csv_path.exists():
        print(f"❌ Error: {csv_path} not found")
        sys.exit(1)

    output_dir = Path(args.output) if args.output else results_dir / 'figures'

    print(f"\n{'='*60}")
    print(f"📊 RAT Performance Visualization")
    print(f"{'='*60}")
    print(f"Input:  {results_dir}")
    print(f"Output: {output_dir}")

    # Load data
    print("\n📂 Loading timing data...")
    df = load_timing_data(csv_path)
    print(f"   Loaded {len(df)} samples from {df['region'].nunique()} regions")

    print("📂 Loading proof timing data...")
    proof_df = load_proof_timings(results_dir)
    print(f"   Found {len(proof_df)} proof submission events")

    print("📂 Loading spammer data...")
    spammer_df = load_spammer_data(results_dir)
    print(f"   Found {len(spammer_df)} spammer burst events")

    # Print statistics
    print("\n📋 Statistics Summary:")
    stats = df.groupby('region').agg({
        'T_proc_ms': ['mean', 'std'],
        'T_net_ms': ['mean', 'std'],
        'T_total_ms': ['mean', 'std', 'count']
    }).round(1)
    print(stats)

    if not spammer_df.empty:
        avg_tps = spammer_df['txs'].mean()
        print(f"\n📊 Spammer Avg TPS: {avg_tps:.1f}")

    # Create visualization
    print("\n📈 Generating combined figure...")
    create_combined_figure(df, proof_df, spammer_df, output_dir)

    print(f"\n{'='*60}")
    print(f"✅ Complete!")
    print(f"{'='*60}\n")

if __name__ == '__main__':
    main()
