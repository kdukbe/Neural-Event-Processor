"""Sample input, NEO detection, FIR and alignment used by Training and Golden."""
from __future__ import annotations
import csv
from dataclasses import dataclass
from pathlib import Path
import numpy as np

CHANNELS = 16
WINDOW_SIZE = 64
PRE_SAMPLES = 32
POST_SAMPLES = 31
DEFAULT_COEFFICIENTS = (8, -2, -6, -4, 0, 0, 0, 0, 0)
CANDIDATE_OFFSETS = np.arange(-32, 32, dtype=np.int64)


def set_channel_count(channel_count: int) -> None:
    """Select how many interleaved channels the shared model must read."""
    if channel_count <= 0:
        raise ValueError("channel_count must be positive")
    global CHANNELS
    CHANNELS = channel_count


@dataclass
class ChannelSamples:
    timestamps: np.ndarray
    values: np.ndarray


@dataclass
class Event:
    dataset: str
    event_id: int
    timestamp: int
    channel_id: int
    event_sample: int
    sample_index: int
    window: np.ndarray
    fir: np.ndarray
    max_slope_index: int


def read_input(path: Path) -> dict[int, ChannelSamples]:
    timestamps: dict[int, list[int]] = {channel: [] for channel in range(CHANNELS)}
    values: dict[int, list[int]] = {channel: [] for channel in range(CHANNELS)}

    with path.open(newline="", encoding="utf-8") as input_file:
        reader = csv.DictReader(input_file)
        required = ["timestamp", "channel_id", "valid", "sample"]
        if reader.fieldnames != required:
            raise ValueError(f"{path}: expected header {required}, got {reader.fieldnames}")

        for row in reader:
            if int(row["valid"]) == 0:
                continue
            channel = int(row["channel_id"])
            if channel not in range(CHANNELS):
                raise ValueError(
                    f"{path}: channel_id must be 0..{CHANNELS - 1}, got {channel}"
                )
            timestamps[channel].append(int(row["timestamp"]))
            values[channel].append(int(row["sample"]))

    result: dict[int, ChannelSamples] = {}
    for channel in range(CHANNELS):
        channel_timestamps = np.asarray(timestamps[channel], dtype=np.int64)
        channel_values = np.asarray(values[channel], dtype=np.int64)
        if len(channel_values) < WINDOW_SIZE:
            raise ValueError(f"{path}: channel {channel} has fewer than 64 samples")
        if np.any(np.diff(channel_timestamps) <= 0):
            raise ValueError(f"{path}: channel {channel} timestamps are not increasing")
        result[channel] = ChannelSamples(channel_timestamps, channel_values)
    return result


def fir_filter(window: np.ndarray, coefficients: tuple[int, ...]) -> np.ndarray:
    """Match the RTL causal FIR, including zero-padding at each window start."""
    result = np.zeros(WINDOW_SIZE, dtype=np.int64)
    for sample_index in range(WINDOW_SIZE):
        total = 0
        for tap, coefficient in enumerate(coefficients):
            source_index = sample_index - tap
            if source_index >= 0:
                total += int(window[source_index]) * coefficient
        result[sample_index] = total
    return result


def find_max_slope(window: np.ndarray) -> int:
    """Return the first index with the largest raw positive slope, as in RTL."""
    slopes = window[1:].astype(np.int64) - window[:-1].astype(np.int64)
    return int(np.argmax(slopes)) + 1


def detect_events(
    dataset: str,
    channels: dict[int, ChannelSamples],
    threshold: int,
    refractory: int,
    coefficients: tuple[int, ...],
) -> tuple[list[Event], int]:
    detected: list[tuple[int, int, int, int]] = []
    incomplete_windows = 0

    for channel in range(CHANNELS):
        data = channels[channel]
        last_event_timestamp = -10**12

        # center_index is x[n] in x[n]^2 - x[n-1]x[n+1].  The WindowBuffer
        # enables SD only after 32 earlier samples are available.
        for center_index in range(PRE_SAMPLES, len(data.values) - 1):
            current = int(data.values[center_index])
            previous = int(data.values[center_index - 1])
            following = int(data.values[center_index + 1])
            timestamp = int(data.timestamps[center_index])
            neo = current * current - previous * following

            if neo < threshold or timestamp - last_event_timestamp <= refractory:
                continue

            last_event_timestamp = timestamp
            if center_index + POST_SAMPLES >= len(data.values):
                incomplete_windows += 1
                continue
            detected.append((timestamp, channel, current, center_index))

    detected.sort(key=lambda item: (item[0], item[1]))
    events: list[Event] = []
    # SD.v increments o_id on the detection edge, so the first RTL event ID is 1.
    for event_id, (timestamp, channel, event_sample, center_index) in enumerate(
        detected, start=1
    ):
        values = channels[channel].values
        window = values[
            center_index - PRE_SAMPLES : center_index + POST_SAMPLES + 1
        ].copy()
        if len(window) != WINDOW_SIZE:
            raise AssertionError("internal error: window length is not 64")
        fir = fir_filter(window, coefficients)
        events.append(
            Event(
                dataset=dataset,
                event_id=event_id,
                timestamp=timestamp,
                channel_id=channel,
                event_sample=event_sample,
                sample_index=center_index,
                window=window,
                fir=fir,
                max_slope_index=find_max_slope(window),
            )
        )
    return events, incomplete_windows


def aligned_feature_matrix(events: list[Event]) -> np.ndarray:
    matrix = np.zeros((len(events), len(CANDIDATE_OFFSETS)), dtype=np.float64)
    for row, event in enumerate(events):
        addresses = event.max_slope_index + CANDIDATE_OFFSETS
        valid = (addresses >= 0) & (addresses < WINDOW_SIZE)
        matrix[row, valid] = event.fir[addresses[valid]]
    return matrix


def valid_candidate_mask(events: list[Event]) -> np.ndarray:
    """Keep only offsets whose RTL address is valid for every training spike."""
    slopes = np.asarray([event.max_slope_index for event in events], dtype=np.int64)
    addresses = slopes[:, None] + CANDIDATE_OFFSETS[None, :]
    return np.all((addresses >= 0) & (addresses < WINDOW_SIZE), axis=0)
