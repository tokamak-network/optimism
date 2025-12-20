import os
import glob
import re
import matplotlib.pyplot as plt
import pandas as pd
import seaborn as sns

# Setup
RESULTS_DIR = "op-rat/results"
OUTPUT_FILE = "rat_sensitivity_plot.pdf"

def parse_sensitivity_data():
    data = []

    # Find all sensitivity directories
    dirs = glob.glob(os.path.join(RESULTS_DIR, "sensitivity_*"))

    for d in dirs:
        dirname = os.path.basename(d)
        # Parse probability from dirname: sensitivity_{PROB}_{TIMESTAMP}
        match = re.match(r"sensitivity_(\d+)_(\d+)", dirname)
        if not match:
            continue

        prob_setting = int(match.group(1)) # 0-100000
        timestamp = int(match.group(2))
        target_percent = prob_setting / 1000.0 # Convert to %

        # Read log file to count triggers
        log_file = os.path.join(d, "logs", "rat_validator_us-east.log")
        if not os.path.exists(log_file):
            continue

        with open(log_file, 'r') as f:
            content = f.read()

        # Count total blocks (lines with "[Block ... Detected")
        total_blocks = len(re.findall(r"\[Block \d+\] Detected", content))

        # Count triggers (lines with "RAT Trigger: YES")
        triggers = len(re.findall(r"RAT Trigger: YES", content))

        if total_blocks > 0:
            actual_percent = (triggers / total_blocks) * 100
        else:
            actual_percent = 0

        data.append({
            "Target Probability (%)": target_percent,
            "Actual Trigger Rate (%)": actual_percent,
            "Total Blocks": total_blocks,
            "Triggers": triggers,
            "Timestamp": timestamp
        })

    if not data:
        print("No data found!")
        return

    df = pd.DataFrame(data)

    # Filter: Keep only latest run for each probability
    df = df.sort_values("Timestamp", ascending=False)
    df = df.drop_duplicates(subset="Target Probability (%)", keep="first")

    df = df.sort_values("Target Probability (%)")

    # --- Cost Projection Constants (from rat_benchmark_gas.csv) ---
    GAS_CHECK_ONLY = 32081
    GAS_TRIGGERED = 120830

    # Calculate Projected Cost (Amortized)
    # Cost = (Rate * Trigger_Gas) + ((1-Rate) * Check_Gas)
    df["Projected Gas Overhead"] = (df["Actual Trigger Rate (%)"] / 100 * GAS_TRIGGERED) + \
                                   ((1 - df["Actual Trigger Rate (%)"] / 100) * GAS_CHECK_ONLY)

    print("\nParsed Data with Cost Projection:")
    print(df)

    # Plot (subplots)
    fig, axes = plt.subplots(1, 2, figsize=(16, 6))
    sns.set_style("whitegrid")

    # Plot 1: Trigger Rate
    sns.lineplot(data=df, x="Target Probability (%)", y="Actual Trigger Rate (%)", marker='o', linewidth=2.5, ax=axes[0])
    max_val = max(df["Target Probability (%)"].max(), df["Actual Trigger Rate (%)"].max())
    if max_val == 0: max_val = 100
    axes[0].plot([0, max_val], [0, max_val], '--', color='gray', alpha=0.5, label="Ideal (y=x)")
    axes[0].set_title("Result 1: Trigger Reliability (Robustness)", fontsize=14)
    axes[0].set_ylabel("Measured Trigger Rate (%)", fontsize=12)
    axes[0].legend()

    # Plot 2: Economic Overhead
    sns.lineplot(data=df, x="Target Probability (%)", y="Projected Gas Overhead", marker='s', color='red', linewidth=2.5, ax=axes[1])
    axes[1].set_title("Result 2: Economic Overhead (Amortized Gas)", fontsize=14)
    axes[1].set_ylabel("Average Gas Cost per Block", fontsize=12)
    axes[1].set_xlabel("Configured Probability (%)", fontsize=12)

    # Annotate points on Plot 2
    for x, y in zip(df["Target Probability (%)"], df["Projected Gas Overhead"]):
        axes[1].text(x, y, f"{int(y):,}", ha='center', va='bottom', fontsize=10, fontweight='bold')

    plt.suptitle("RAT Sensitivity Analysis: Reliability vs. Cost", fontsize=16)
    plt.tight_layout()

    # Save
    plt.savefig(OUTPUT_FILE)
    print(f"\nSensitivity plot saved to {OUTPUT_FILE}")

if __name__ == "__main__":
    parse_sensitivity_data()
