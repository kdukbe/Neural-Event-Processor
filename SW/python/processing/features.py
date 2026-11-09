"""Select up to seven feature offsets from unlabeled training waveforms."""
import numpy as np
from . import signal_model as sfe


def laplacian_scores(x, neighbors=5):
    """He/Cai/Niyogi 2005, section 2.1, Eq.(1), symmetric kNN graph.

    k=5 and t=median positive connected squared distance are our settings.
    Feature scaling is unchanged: all candidate FIR samples have the same unit.
    """
    n = len(x)
    if n < 3:
        raise ValueError('At least three waveforms required for this experiment')
    k = min(neighbors, n-1)
    sq = ((x[:, None, :]-x[None, :, :])**2).sum(2)
    np.fill_diagonal(sq, np.inf)
    nn = np.argsort(sq, axis=1, kind='stable')[:, :k]
    edges = np.zeros((n, n), dtype=bool)
    edges[np.arange(n)[:, None], nn] = True
    edges |= edges.T
    distances = sq[edges]
    positive = distances[np.isfinite(distances) & (distances > 0)]
    if not len(positive):
        raise ValueError('No varying waveforms')
    scale = float(np.median(positive))
    s = np.zeros((n, n))
    s[edges] = np.exp(-sq[edges]/scale)
    d = s.sum(1)
    centered = x - (d[:, None]*x).sum(0)/d.sum()
    denominator = (d[:, None]*centered**2).sum(0)
    numerator = denominator - (centered*(s@centered)).sum(0)
    score = np.full(x.shape[1], np.inf)
    good = denominator > max(float(denominator.max())*1e-12, 1e-12)
    score[good] = np.maximum(numerator[good], 0)/denominator[good]
    return score, dict(k=k,heat_scale=scale,graph_edges=int(edges.sum()//2))


def select_offsets(events, neighbors=5):
    """Rank valid FIR sample positions by Laplacian Score (lower is better)."""
    training = list(events)
    if len(training) < 3:
        raise ValueError('fewer than three training waveforms')
    x = sfe.aligned_feature_matrix(training)
    mask = sfe.valid_candidate_mask(training)
    varying = x.var(0) > max(float(x.var(0).max())*1e-12, 1e-12)
    mask &= varying
    available = np.flatnonzero(mask)
    if len(available) < 2:
        raise ValueError('fewer than two nonconstant in-window candidate positions')
    meta = dict(training_events=len(training), valid_candidates=len(available), flat_classes=[])
    scores, graph = laplacian_scores(x[:, available], neighbors)
    meta.update(graph)
    rank_score = np.full(64, np.inf)
    rank_score[available] = scores
    ranked = sorted(available, key=lambda c: (rank_score[c], abs(int(sfe.CANDIDATE_OFFSETS[c])), int(sfe.CANDIDATE_OFFSETS[c])))
    selected = []
    for c in ranked:
        if not np.isfinite(rank_score[c]):
            continue
        selected.append(int(c))
        if len(selected) == 7:
            break
    if len(selected) < 2:
        raise ValueError('fewer than two selected positions')
    meta['offsets'] = [int(sfe.CANDIDATE_OFFSETS[c]) for c in selected]
    meta['feature_count'] = len(selected)
    return selected, meta
