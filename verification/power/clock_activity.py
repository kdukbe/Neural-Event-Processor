"""Extract clock edge counts and enable statistics directly from SAIF."""
from portable_manifest import load_manifest
import argparse
from portable_manifest import EVIDENCE
import hashlib
import json
import re
from pathlib import Path


def clock_statistics(path, sfe_mhz):
    text = Path(path).read_text(encoding="ascii")
    scale = re.search(r"\(TIMESCALE\s+(\d+)\s+(\w+)\)", text)
    seconds_per_unit = int(scale[1]) * {"ps": 1e-12, "ns": 1e-9, "us": 1e-6}[scale[2]]
    duration = int(re.search(r"\(DURATION\s+(\d+)\)", text)[1])
    duration_s = duration * seconds_per_unit

    def entries(name):
        lines = re.findall(r"^\s*\(" + re.escape(name) + r"\s+\(T0.*$", text, re.M)
        records = [dict((k, int(v)) for k, v in re.findall(r"\((T0|T1|TX|TZ|TB|TC)\s+(\d+)\)", line)) for line in lines]
        if not records:
            raise ValueError(f"No clock activity: {name}")
        if any(record != records[0] for record in records):
            raise ValueError(f"Clock aliases disagree: {name}")
        value = records[0]
        if value["TX"] or value["TZ"] or value["T0"] + value["T1"] != duration:
            raise ValueError(f"Unknown or incomplete activity: {name}")
        return value

    raw = entries("SFE_CLK")
    expected_edges = 2 * sfe_mhz * 1e6 * duration_s
    if abs(raw["TC"] - expected_edges) > 2.1:
        raise ValueError(f"SFE clock does not match implementation: {raw['TC']} vs {expected_edges}")
    is_gated = "(sfe_run_clk " in text
    gated = entries("sfe_run_clk") if is_gated else raw
    if gated["TC"] > raw["TC"] + 2:
        raise ValueError("Gated clock has more edges than its source")
    pulses = gated["TC"] / 2
    result = {
        "saif_sha256": hashlib.sha256(Path(path).read_bytes()).hexdigest(),
        "observation_s": duration_s,
        "hardware_sfe_mhz": sfe_mhz,
        "clock_gated": is_gated,
        "source_clock_edges": raw["TC"],
        "delivered_clock_edges": gated["TC"],
        "delivered_clock_pulses": pulses,
        "clock_delivery_fraction": gated["TC"] / raw["TC"],
        "average_clock_mhz_for_power_only": pulses / duration_s / 1e6,
        "average_period_ns_for_power_only": duration_s * 1e9 / pulses if pulses else None,
        "average_high_pulse_ns": gated["T1"] * seconds_per_unit * 1e9 / pulses if pulses else None,
        "clock_high_fraction": gated["T1"] / duration,
    }
    if is_gated:
        enable = entries("clock_enable")
        result["enable_fraction"] = enable["T1"] / duration
        result["enable_transitions"] = enable["TC"]
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["always_on_1mhz", "always_on_8mhz", "event_driven_8mhz"])
    parser.add_argument("dataset", choices=["burst", "real1", "real2", "real3"])
    args = parser.parse_args()
    folder = EVIDENCE / args.dataset / args.mode
    result = clock_statistics(folder / "activity.saif", 1 if args.mode == "always_on_1mhz" else 8)
    if result["clock_gated"] != (args.mode == "event_driven_8mhz"):
        raise ValueError("Clock hierarchy does not match mode")
    (folder / "clock_activity.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    settings = [f"set observed_clock_edges {result['delivered_clock_edges']}"]
    if result["delivered_clock_edges"]:
        settings += [f"set observed_clock_period_ns {result['average_period_ns_for_power_only']:.12f}",
                     f"set observed_clock_high_ns {result['average_high_pulse_ns']:.12f}"]
    (folder / "clock_activity.tcl").write_text("\n".join(settings) + "\n", encoding="ascii")
    print(json.dumps(result))


if __name__ == "__main__":
    main()
