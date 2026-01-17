import csv
import json
import sys
from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib import gridspec


def wei_to_eth(wei: int) -> float:
    return wei / 10**18


def marker_for_role(role: str) -> str:
    r = (role or "").lower()
    if "offline" in r:
        return "D"  # diamond
    if "distance" in r:
        return "^"  # triangle up
    if "non-existence" in r or "non existence" in r:
        return "v"  # triangle down
    if "honest" in r:
        return "o"  # default, may override per-honest later
    return "o"


def main() -> int:
    if len(sys.argv) < 3:
        print("Usage: python scripts/plot_staking.py <staking_csv> <output_pdf> [threshold_wei] [roles_json]")
        return 2

    csv_path = Path(sys.argv[1])
    out_path = Path(sys.argv[2])
    threshold_wei = int(sys.argv[3]) if len(sys.argv) >= 4 else None
    roles_path = Path(sys.argv[4]) if len(sys.argv) >= 5 else None
    roles = {}
    if roles_path is not None and roles_path.exists():
        roles = json.loads(roles_path.read_text())

    rows = []
    with csv_path.open(newline="") as f:
        r = csv.DictReader(f)
        for row in r:
            rows.append(row)

    if not rows:
        print("No rows in CSV.")
        return 1

    rounds = [int(r["round"]) for r in rows]
    addrs = [a for a in rows[0].keys() if a.startswith("stake_")]
    addrs = [a.replace("stake_", "") for a in addrs]

    # IEEE single-column friendly sizing (~3.5in width).
    # Use a dedicated legend row so nothing overlaps the plot.
    fig = plt.figure(figsize=(3.5, 2.8), dpi=300)
    gs = gridspec.GridSpec(2, 1, height_ratios=[1.0, 0.55], hspace=0.05, figure=fig)
    ax1 = fig.add_subplot(gs[0])
    ax2 = ax1.twinx()
    ax_leg = fig.add_subplot(gs[1])
    ax_leg.axis("off")

    # Marker cadence: keep readable in IEEE single-column and avoid overlaps.
    marker_step = 6  # show a marker roughly every ~6 rounds

    # Identify honest addresses to de-overlap markers when lines coincide.
    honest_addrs = [a for a in addrs if roles.get(a, "").lower() == "honest"]
    honest_marker_map = {}
    if len(honest_addrs) >= 2:
        honest_marker_map[honest_addrs[0]] = "o"
        honest_marker_map[honest_addrs[1]] = "s"

    for idx, addr in enumerate(addrs):
        role = roles.get(addr, "")
        label = f"{addr[:10]} ({role})" if role else addr[:10]
        ys = [wei_to_eth(int(r[f"stake_{addr}"])) for r in rows]
        marker = honest_marker_map.get(addr) or marker_for_role(role)
        markevery = (idx % marker_step, marker_step)
        (line,) = ax1.plot(
            rounds,
            ys,
            linewidth=1.6,
            label=label,
            marker=marker,
            markersize=3.2,
            markevery=markevery,
            markerfacecolor="white",
            markeredgewidth=0.9,
        )

        # plot cumulative prize (dashed, same color) on right axis.
        # Skip all-zero prize series to avoid visual clutter that looks like "staking=0".
        prize_key = f"prize_{addr}"
        if prize_key in rows[0]:
            prize = [wei_to_eth(int(r.get(prize_key, "0") or "0")) for r in rows]
            if any(p > 0 for p in prize):
                ax2.plot(
                    rounds,
                    prize,
                    linewidth=1.2,
                    linestyle="--",
                    color=line.get_color(),
                    alpha=0.9,
                    label="_nolegend_",
                )

        # mark validity drop points
        prev_valid = None
        for i, r in enumerate(rows):
            v = r.get(f"valid_{addr}", "")
            is_valid = v.lower() in ("true", "1")
            if prev_valid is None:
                prev_valid = is_valid
                continue
            if prev_valid and not is_valid:
                ax1.scatter([rounds[i]], [ys[i]], marker="x", s=28, color=line.get_color(), zorder=5)
            prev_valid = is_valid

    if threshold_wei is not None:
        thr = wei_to_eth(threshold_wei)
        ax1.axhline(y=thr, color="black", linestyle="--", linewidth=0.9)
        ax1.text(rounds[0], thr, "validity threshold", fontsize=7, va="bottom", ha="left")

    # Title removed for paper-ready tight figures.
    ax1.set_xlabel("")
    ax1.set_ylabel("Stake (ETH)", fontsize=7)
    ax2.set_ylabel("Prize (ETH)", fontsize=7)
    ax1.grid(True, alpha=0.25)

    ax1.tick_params(axis="both", labelsize=7)
    ax2.tick_params(axis="y", labelsize=7)

    # Legend in dedicated row so it never overlaps plot area.
    handles, labels = ax1.get_legend_handles_labels()
    prize_proxy = plt.Line2D([0], [0], linestyle="--", color="gray", linewidth=1.2)
    handles.append(prize_proxy)
    labels.append("prize (dashed)")
    ax_leg.legend(
        handles,
        labels,
        loc="center",
        ncol=2,
        fontsize=7,
        frameon=False,
        title="validator",
        title_fontsize=7,
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    # Make margins as tight as possible for IEEE-style inclusion.
    fig.savefig(out_path, bbox_inches="tight", pad_inches=0.01)
    print(f"Wrote {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

