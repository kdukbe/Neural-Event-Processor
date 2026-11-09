"""Shared NEO threshold: pooled MAD noise estimate, using the training prefix."""
import csv
import math
from pathlib import Path
import numpy as np

COEFFICIENT = 14
NORMAL_MEDIAN_ABS = 0.6744897501960817
DEFAULT_PREFIX_SAMPLES = 20_000


def calculate(path, channels=16, samples_per_channel=DEFAULT_PREFIX_SAMPLES):
    count = [0]*channels
    samples = [[] for _ in range(channels)]
    last_time = [-1]*channels
    with Path(path).open(encoding='utf-8-sig', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            if not int(row['valid']):
                continue
            ch, t, x = int(row['channel_id']), int(row['timestamp']), int(row['sample'])
            if not 0 <= ch < channels or not -32768 <= x <= 32767:
                raise ValueError('Channel or signed 16-bit sample is out of range')
            if t <= last_time[ch]:
                raise ValueError('Each channel must have increasing timestamps')
            last_time[ch] = t
            if samples_per_channel and count[ch] >= samples_per_channel:
                continue
            count[ch] += 1
            samples[ch].append(x)
    if any(c < 3 for c in count):
        raise ValueError('At least three samples are required in every channel')
    # Channel medians only remove DC offsets for this statistic. The RTL input
    # itself is unchanged, and the final threshold is shared by all channels.
    centered = [np.asarray(v,dtype=np.float64)-np.median(v) for v in samples]
    mad = float(np.median(np.abs(np.concatenate(centered))))
    sigma = mad/NORMAL_MEDIAN_ABS
    value = max(1, min(0xffffffff, math.ceil(COEFFICIENT*sigma*sigma)))
    return dict(threshold=value, formula='ceil(14 * noise_sigma**2)',
                noise_estimator='median_all_channels(abs(x - median_channel(x))) / 0.6744897501960817',
                coefficient=COEFFICIENT, median_absolute_deviation=mad, noise_sigma=sigma,
                samples_per_channel=count, requested_samples_per_channel=samples_per_channel,
                shared_across_channels=True,
                selection_status='Development recommendation; 20000-sample prefix checked on current three recordings, not a universal minimum or full accuracy proof')
