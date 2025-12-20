import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import glob
import os
import argparse
import numpy as np
from matplotlib.patches import Patch

def main():
    parser = argparse.ArgumentParser(description="Plot RAT Experiment Results")
    parser.add_argument("--output", default="rat_experiment_results.pdf", help="Output PDF file (legacy arg)")
    args = parser.parse_args()

    # 1. Load Data
    csv_files = glob.glob("rat_validator_result_*.csv")
    data_frames = []

    if csv_files:
        for file in csv_files:
            region = file.replace("rat_validator_result_", "").replace(".csv", "")
            try:
                df = pd.read_csv(file)
                df['Region'] = region
                data_frames.append(df)
            except Exception as e:
                print(f"Error reading {file}: {e}")
    else:
        print("No validator result CSV files found. Skipping validator plots.")

    valid_data = pd.DataFrame()
    if data_frames:
        full_data = pd.concat(data_frames, ignore_index=True)
        if 'Status' in full_data.columns:
            valid_data = full_data[full_data['Status'] == 'VALID'].copy()
        else:
            valid_data = full_data # Fallback

    if valid_data.empty and not glob.glob("rat_benchmark_gas.csv"):
        print("No valid data loaded (Validator or Gas). Exiting.")
        return

    # 2. Setup Plotting - Generate Separate PDFs
    sns.set_theme(style="whitegrid")

    if not valid_data.empty:
        # Determine if we have TxCount for Scale Analysis
        has_scale_data = 'TxCount' in valid_data.columns

        # --- Plot A: Validator Processing Time ---
        plt.figure(figsize=(8, 6))
        if has_scale_data:
            sns.boxplot(x="TxCount", y="ProcessTimeMS", data=valid_data, color="skyblue")
            plt.title("Validator Processing Time (by Batch Size)")
            plt.xlabel("Batch Size (Tx Count)")
        else:
            sns.boxplot(x="Region", y="ProcessTimeMS", data=valid_data, palette="viridis")
            plt.title("Validator Processing Time (by Region)")
            plt.xlabel("Region")
        plt.ylabel("Time (ms)")
        plt.tight_layout()
        plt.savefig("rat_result_process_time.pdf")
        print("Saved rat_result_process_time.pdf (Box Plot)")
        plt.close()

        # --- Plot B: End-to-End Latency CDF ---
        plt.figure(figsize=(8, 6))
        valid_data['TotalReactionTime'] = valid_data['LatencyMS'] + valid_data['ProcessTimeMS']

        # Capture axis to modify legend
        ax = sns.ecdfplot(data=valid_data, x="TotalReactionTime", hue="Region", palette="viridis")

        plt.title("End-to-End Reaction Time CDF")
        plt.xlabel("Total Time (ms) [Network + Processing]")
        plt.ylabel("Cumulative Probability")

        if ax.get_legend():
            ax.get_legend().set_title("Virtual Region")

        plt.tight_layout()
        plt.savefig("rat_result_latency_cdf.pdf")
        print("Saved rat_result_latency_cdf.pdf (CDF)")
        plt.close()

        # --- Plot C: Linear Scalability Analysis ---
        if has_scale_data:
            plt.figure(figsize=(8, 6))
            sns.regplot(x="TxCount", y="ProcessTimeMS", data=valid_data,
                        scatter_kws={'alpha':0.3, 'label': 'Observed Samples'},
                        line_kws={'color':'red', 'label': 'Linear Fit (O(N))'},
                        order=1)

            plt.title("Linear Scalability Analysis (O(N))")
            plt.xlabel("Batch Size (Tx Count)")
            plt.ylabel("Processing Time (ms)")

            try:
                corr = valid_data['TxCount'].corr(valid_data['ProcessTimeMS'])
                plt.text(0.05, 0.90, f'Pearson R: {corr:.3f}', transform=plt.gca().transAxes,
                         verticalalignment='top', bbox=dict(boxstyle="round", alpha=0.1, facecolor='white'))
            except:
                pass

            plt.legend()
            plt.tight_layout()
            plt.savefig("rat_result_scalability.pdf")
            print("Saved rat_result_scalability.pdf (Scalability)")
            plt.close()
    else:
        print("Skipping plots A, B, C (no validator data)")

    # --- Plot D: Gas Cost Analysis ---
    gas_files = glob.glob("rat_benchmark_gas.csv")
    if gas_files:
        try:
            df_gas = pd.read_csv("rat_benchmark_gas.csv")

            # Constants - based on L2OutputOracle baseline
            BASELINE_PROPOSER = 185000

            # Calculate means
            check_only = 0
            triggered = 0
            submit_solution = 0

            if 'GasUsed' in df_gas.columns and 'Scenario' in df_gas.columns:
                if 'Check_Only' in df_gas['Scenario'].values:
                    check_only = df_gas[df_gas['Scenario'] == 'Check_Only']['GasUsed'].mean()
                elif 'Baseline' in df_gas['Scenario'].values:
                     check_only = df_gas[df_gas['Scenario'] == 'Baseline']['GasUsed'].mean()

                if 'Triggered' in df_gas['Scenario'].values:
                    triggered = df_gas[df_gas['Scenario'] == 'Triggered']['GasUsed'].mean()
                elif 'RAT_Triggered' in df_gas['Scenario'].values:
                    triggered = df_gas[df_gas['Scenario'] == 'RAT_Triggered']['GasUsed'].mean()

                if 'Submit_Solution' in df_gas['Scenario'].values:
                    submit_solution = df_gas[df_gas['Scenario'] == 'Submit_Solution']['GasUsed'].mean()

            # Construct Bars Data
            bar1_val = BASELINE_PROPOSER
            bar2_val = BASELINE_PROPOSER + check_only
            bar3_val = BASELINE_PROPOSER + triggered
            bar4_val = submit_solution

            categories = [
                'Posting L2 state\n(Baseline)',
                'Post L2 state\nwithout RAT trigger',
                'Post L2 state\nwith RAT trigger',
                'Submit RAT\nsolution'
            ]
            values = [bar1_val, bar2_val, bar3_val, bar4_val]

            plt.figure(figsize=(10, 6))
            bars = plt.bar(categories, values, width=0.5, edgecolor='black', linewidth=1.2)

            # Styling - Uniform Hatching for RAT Overhead
            # Bar 1: Base Proposer (Gray)
            bars[0].set_facecolor('gray')

            # Bar 2: Proposer + Check overhead (Gray + Hatch)
            bars[1].set_facecolor('gray')
            bars[1].set_hatch('//')

            # Bar 3: Proposer + Trigger overhead (Gray + Hatch)
            # Both signify RAT Overhead, just different magnitudes
            bars[2].set_facecolor('gray')
            bars[2].set_hatch('//')

            # Bar 4: Validator (Green + Hatch)
            bars[3].set_facecolor('lightgreen')
            bars[3].set_hatch('//')

            plt.ylabel("Gas Cost (k)")

            # Format Y tick labels
            yticks = plt.gca().get_yticks()
            plt.gca().set_yticklabels([f'{int(y/1000)}k' for y in yticks])

            plt.xticks(rotation=15, ha='right')
            plt.ylim(0, max(values) * 1.25) # More headroom for legend

            # Legend aligned with Patterns
            legend_elements = [
                Patch(facecolor='gray', edgecolor='black', label='Proposer (Base)'),
                Patch(facecolor='white', hatch='//', edgecolor='black', label='RAT Overhead / Validator'),
                # Or better:
                # Patch(facecolor='lightgreen', hatch='//', edgecolor='black', label='Validator')
            ]
            # Let's break it down as Requested
            legend_elements_refined = [
                Patch(facecolor='gray', edgecolor='black', label='Proposer Base'),
                Patch(facecolor='white', hatch='//', edgecolor='black', label='RAT Overhead'),
                Patch(facecolor='lightgreen', hatch='//', edgecolor='black', label='Validator')
            ]

            plt.legend(handles=legend_elements_refined, loc='upper right')

            # Add value labels
            for bar in bars:
                height = bar.get_height()
                plt.text(bar.get_x() + bar.get_width()/2., height,
                         f'{int(height):,}',
                         ha='center', va='bottom', fontsize=10, fontweight='bold')

            plt.tight_layout()
            plt.savefig("rat_result_gas_cost_v3.pdf")
            print("Saved rat_result_gas_cost_v3.pdf (Detailed 4-Bar Chart)")
            plt.close()
        except Exception as e:
            print(f"Error plotting gas costs: {e}")

if __name__ == "__main__":
    main()
