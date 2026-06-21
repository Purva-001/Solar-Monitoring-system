import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  Alert,
  Box,
  Chip,
  Grid,
  LinearProgress,
  Paper,
  Typography,
  Button
} from '@mui/material';
import { CheckCircle, ErrorOutline } from '@mui/icons-material';
import './HealthReport.css';
import {
  readingsChannelIndexForPanel,
  unwrapPanelReadingsPayload,
} from '../utils/solarReadings';

const DEFAULT_PANEL_ID = 'PL01-B02-INV03-STR05-P01';
const RATED_PANEL_W = 40;

const formatNumber = (n, digits = 2) => {
  const v = Number(n);
  if (!Number.isFinite(v)) return '—';
  return v.toFixed(digits);
};

const toFinite = (v) => {
  if (v === null || v === undefined || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
};

const getP1FromHealthReport = (healthReport) => {
  const sd = healthReport?.sensor_data;
  const p1 = sd?.P1 ?? sd?.power?.P1;
  if (p1 && typeof p1 === 'object' && 'value' in p1) return toFinite(p1.value);
  return toFinite(p1);
};

/** Power (W) for channel 1–4 from a snapshot object (backend: panel{n}power_before | _after). */
const channelPowerFromSnapshot = (payload, channelIdx, phase) => {
  if (!payload || typeof payload !== 'object') return null;
  const key = `panel${channelIdx}power_${phase}`;
  const v = payload[key];
  return toFinite(v);
};

/** Shortfall vs rated power (0–100%); aligns small-demo panels with a 40 W nameplate. */
const deviationUnderRated = (w, rated = RATED_PANEL_W) => {
  if (w === null || w === undefined) return null;
  const n = Number(w);
  if (!Number.isFinite(n)) return null;
  return Math.max(0, ((rated - n) / rated) * 100);
};

const healthLabelFromW = (w) => {
  if (w === null || w === undefined) return null;
  return Number(w) >= 5 ? 'Healthy' : 'Faulty';
};

const MaintenanceComparisonAnalysis = ({ panelId = null, autoRunToken = 0 }) => {
  const [selectedPanelId, setSelectedPanelId] = useState(panelId || DEFAULT_PANEL_ID);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const [before, setBefore] = useState(null);
  const [after, setAfter] = useState(null);
  const [comparison, setComparison] = useState(null);

  const [countdown, setCountdown] = useState(0);
  const runningRef = useRef(false);
  const lastAutoTokenRef = useRef(0);

  useEffect(() => {
    if (panelId) setSelectedPanelId(panelId);
  }, [panelId]);

  const effectivePanelId = selectedPanelId || DEFAULT_PANEL_ID;
  const channelIdx = useMemo(
    () => readingsChannelIndexForPanel(effectivePanelId),
    [effectivePanelId]
  );

  const [liveReadings, setLiveReadings] = useState(null);

  useEffect(() => {
    let cancelled = false;
    const tick = async () => {
      try {
        const res = await fetch(
          `/api/panel/readings?panel_id=${encodeURIComponent(effectivePanelId)}`,
          { method: 'GET', headers: { Accept: 'application/json' } }
        );
        if (!res.ok) return;
        const raw = await res.json();
        const data = unwrapPanelReadingsPayload(raw) ?? raw;
        if (cancelled) return;
        setLiveReadings(data && typeof data === 'object' && !Array.isArray(data) ? data : null);
      } catch {
        if (!cancelled) setLiveReadings(null);
      }
    };
    tick();
    const id = setInterval(tick, 5000);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, [effectivePanelId]);

  const liveChannelPowerW = useMemo(() => {
    if (!liveReadings) return null;
    const k = `panel${channelIdx}power`;
    const raw = liveReadings[k] ?? liveReadings?.power?.[`P${channelIdx}`] ?? liveReadings?.[`P${channelIdx}`];
    return toFinite(raw);
  }, [liveReadings, channelIdx]);

  const fetchBefore = async (pid) => {
    const res = await fetch(`/api/panel/comparison/before?panel_id=${encodeURIComponent(pid)}`, { method: 'GET' });
    if (!res.ok) throw new Error(`Before snapshot fetch failed: ${res.status}`);
    return await res.json();
  };

  const captureBefore = async (pid) => {
    const res = await fetch(`/api/panel/comparison/before?panel_id=${encodeURIComponent(pid)}`, { method: 'POST' });
    if (!res.ok) {
      const text = await res.text();
      throw new Error(text || `Before snapshot capture failed: ${res.status}`);
    }
    return await res.json();
  };

  const fetchLatest = async (pid) => {
    const res = await fetch(`/api/panel/comparison/latest?panel_id=${encodeURIComponent(pid)}`, { method: 'GET' });
    if (!res.ok) throw new Error(`Comparison fetch failed: ${res.status}`);
    return await res.json();
  };

  const runComparison = async (pid) => {
    const res = await fetch(`/api/panel/comparison/run?panel_id=${encodeURIComponent(pid)}`, { method: 'POST' });
    if (!res.ok) {
      const text = await res.text();
      throw new Error(text || `Comparison run failed: ${res.status}`);
    }
    return await res.json();
  };

  const startCountdownAndRun = async (pid) => {
    if (!pid) return;
    if (runningRef.current) return;

    runningRef.current = true;
    setError(null);
    setLoading(true);
    setAfter(null);
    setComparison(null);

    try {
      const beforePayload = await captureBefore(pid);
      setBefore(beforePayload || null);

      const seconds = 30;
      setCountdown(seconds);
      for (let s = seconds; s > 0; s -= 1) {
        await new Promise((r) => setTimeout(r, 1000));
        setCountdown((prev) => Math.max(0, prev - 1));
      }

      const out = await runComparison(pid);
      setBefore(out?.before || beforePayload || null);
      setAfter(out?.after || null);
      setComparison(out || null);
    } catch (e) {
      setError(e?.message || 'Failed to run maintenance comparison');
    } finally {
      setLoading(false);
      runningRef.current = false;
    }
  };

  useEffect(() => {
    let cancelled = false;

    const init = async () => {
      if (!selectedPanelId) return;
      try {
        setError(null);
        let b = await fetchBefore(selectedPanelId);
        const c = await fetchLatest(selectedPanelId);
        const beforeMissing =
          !b ||
          (typeof b === 'object' && !Array.isArray(b) && Object.keys(b).length === 0) ||
          !b?.image?.url;
        if (beforeMissing) {
          b = await captureBefore(selectedPanelId);
        }
        if (cancelled) return;
        setBefore(b || null);
        if (c && Object.keys(c).length) {
          setAfter(c?.after || null);
          setComparison(c);
        }
      } catch (e) {
        if (cancelled) return;
        // Surface backend/proxy issues (otherwise UI just shows "No image").
        // eslint-disable-next-line no-console
        console.error('MaintenanceComparisonAnalysis init failed:', e);
        setError(e?.message || 'Failed to load/capture comparison snapshot');
      }
    };

    init();
    return () => {
      cancelled = true;
    };
  }, [selectedPanelId]);

  useEffect(() => {
    if (!autoRunToken) return;
    if (autoRunToken === lastAutoTokenRef.current) return;
    lastAutoTokenRef.current = autoRunToken;
    if (!selectedPanelId) return;
    startCountdownAndRun(selectedPanelId);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [autoRunToken, selectedPanelId]);

  const beforePowerRaw = useMemo(() => {
    const ch = channelPowerFromSnapshot(before, channelIdx, 'before');
    if (ch !== null) return ch;
    const fromP1 = getP1FromHealthReport(before?.health_report);
    if (fromP1 !== null) return fromP1;
    return toFinite(before?.power_before);
  }, [before, channelIdx]);

  const afterPowerStored = useMemo(() => {
    const a =
      channelPowerFromSnapshot(comparison, channelIdx, 'after') ??
      channelPowerFromSnapshot(after, channelIdx, 'after') ??
      channelPowerFromSnapshot(comparison?.after, channelIdx, 'after');
    if (a !== null) return a;
    const report = comparison?.after?.health_report || after?.health_report;
    const fromP1 = getP1FromHealthReport(report);
    if (fromP1 !== null) return fromP1;
    return toFinite(comparison?.power_after ?? after?.power_after);
  }, [comparison, after, channelIdx]);

  /** After cleaning: saved snapshot if present, else live AWS reading for this panel channel. */
  const afterPowerRaw =
    afterPowerStored !== null && afterPowerStored !== undefined ? afterPowerStored : liveChannelPowerW;

  const imageBustQuery = useMemo(
    () =>
      encodeURIComponent(
        `${comparison?.timestamp ?? ''}|${before?.timestamp ?? ''}|${after?.timestamp ?? ''}|${autoRunToken}`
      ),
    [comparison?.timestamp, before?.timestamp, after?.timestamp, autoRunToken]
  );

  const normalizeImageUrl = (u) => {
    if (!u) return null;
    const s = String(u);
    if (s.startsWith('/captures/')) return `/api/assets/${s.replace('/captures/', '')}`;
    return s;
  };
  const beforeImage = before?.image?.url ? `${normalizeImageUrl(before.image.url)}?v=${imageBustQuery}` : null;
  const afterImage = (comparison?.after?.image?.url || after?.image?.url)
    ? `${normalizeImageUrl((comparison?.after?.image?.url || after?.image?.url))}?v=${imageBustQuery}`
    : null;

  const beforePower = beforePowerRaw;
  const afterPower = afterPowerRaw;

  const beforeHealth =
    healthLabelFromW(beforePower) ||
    before?.resolution_status ||
    before?.health_report?.status ||
    before?.resolution ||
    null;
  const afterHealth =
    healthLabelFromW(afterPower) ||
    comparison?.after?.resolution_status ||
    after?.resolution_status ||
    comparison?.resolution_status ||
    null;

  const beforeHealthColor = String(beforeHealth || '').toLowerCase().includes('healthy') ? 'success' : 'warning';
  const afterHealthColor = String(afterHealth || '').toLowerCase().includes('healthy') || String(afterHealth || '').toLowerCase().includes('resolved') ? 'success' : 'warning';

  const beforeDeviation = deviationUnderRated(beforePower);
  const afterDeviation = deviationUnderRated(afterPower);

  const improvementPercent = useMemo(() => {
    const pb = toFinite(beforePower);
    const pa = toFinite(afterPower);
    if (pb === null || pa === null) return null;
    if (Math.abs(pb) < 1e-9) return null;
    return ((pa - pb) / pb) * 100;
  }, [beforePower, afterPower]);

  const energyRecoveredWh = useMemo(() => {
    const pb = toFinite(beforePower);
    const pa = toFinite(afterPower);
    if (pb === null || pa === null) return null;
    const diffW = pa - pb;
    // For now assume 1 hour equivalent recovery window (can be replaced with real duration later)
    return diffW;
  }, [beforePower, afterPower]);

  const resolution = useMemo(() => {
    const imp = toFinite(improvementPercent);
    if (imp === null) return null;
    if (imp > 10) return 'Resolved';
    if (imp >= 3) return 'Monitor';
    return 'Escalate';
  }, [improvementPercent]);

  const resolutionColor =
    resolution === 'Resolved' ? 'success' : resolution === 'Monitor' ? 'warning' : resolution ? 'error' : 'default';

  const progressValue = toFinite(improvementPercent) !== null ? Math.max(0, Math.min(100, Number(improvementPercent))) : 0;

  return (
    <Box className="health-report">
      <Box
        sx={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: { xs: 'flex-start', md: 'center' },
          gap: 2,
          flexDirection: { xs: 'column', md: 'row' },
          mb: 2
        }}
      >
        <Box>
          <Typography variant="h4" fontWeight={900} sx={{ mb: 0.5 }}>
            Maintenance Comparison Analysis
          </Typography>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, flexWrap: 'wrap' }}>
            {selectedPanelId && (
              <Chip
                label={`Panel: ${selectedPanelId}`}
                sx={{ bgcolor: '#dcfce7', color: '#166534', fontWeight: 900 }}
              />
            )}
            {comparison?.timestamp && (
              <Chip
                label={`Completed: ${new Date(comparison.timestamp).toLocaleString()}`}
                sx={{ bgcolor: '#e0f2fe', color: '#075985', fontWeight: 900 }}
              />
            )}
          </Box>
        </Box>

        <Button
          variant="contained"
          disabled={!selectedPanelId || loading}
          onClick={() => startCountdownAndRun(selectedPanelId)}
          sx={{ fontWeight: 900, borderRadius: 2 }}
        >
          Run After-Cleaning Comparison
        </Button>
      </Box>

      {error && (
        <Alert severity="error" sx={{ mb: 2 }}>
          {error}
        </Alert>
      )}

      {liveReadings?.source === 'dummy' ? (
        <Alert severity="warning" sx={{ mb: 2 }}>
          Panel readings are using dummy data (AWS unreachable or misconfigured). Set{' '}
          <strong>AWS_API_ENDPOINT</strong> in <code>.env</code> and restart the API server — powers here will not match
          your live Gateway JSON until real readings load.
        </Alert>
      ) : null}

      {loading && (
        <Paper elevation={0} sx={{ p: 2.5, borderRadius: 2, border: '1px solid #eaeaea', mb: 2 }}>
          <Typography fontWeight={900} sx={{ fontSize: 18, mb: 1 }}>
            Running post-clean comparison… Stabilizing ({countdown}s)
          </Typography>
          <LinearProgress variant="determinate" value={((30 - countdown) / 30) * 100} sx={{ height: 10, borderRadius: 5 }} />
        </Paper>
      )}

      <Grid container spacing={2.5}>
        <Grid item xs={12} md={6}>
          <Paper elevation={0} sx={{ p: 2.5, borderRadius: 2, border: '1px solid #eaeaea' }}>
            <Typography fontWeight={900} sx={{ fontSize: 20, mb: 1.5 }}>
              Before Cleaning
            </Typography>
            <Box sx={{ display: 'flex', gap: 2, flexDirection: { xs: 'column', sm: 'row' } }}>
              <Box sx={{ flex: 1 }}>
                <Typography sx={{ fontWeight: 900, fontSize: 16, mb: 0.5 }}>Image</Typography>
                <Box
                  sx={{
                    borderRadius: 2,
                    border: '1px solid #eaeaea',
                    overflow: 'hidden',
                    bgcolor: '#fff',
                    height: 240,
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center'
                  }}
                >
                  {beforeImage ? (
                    <img src={beforeImage} alt="Before cleaning" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                  ) : (
                    <Typography color="text.secondary" sx={{ fontWeight: 800 }}>
                      No image
                    </Typography>
                  )}
                </Box>
              </Box>

              <Box sx={{ flex: 1 }}>
                <Typography sx={{ fontWeight: 900, fontSize: 16, mb: 1 }}>Power (W)</Typography>
                <Typography sx={{ fontWeight: 900, fontSize: 34, mb: 1 }}>
                  {beforePower !== null ? formatNumber(beforePower, 2) : '—'}
                </Typography>

                <Typography sx={{ fontWeight: 900, fontSize: 16, mb: 1 }}>Health Status</Typography>
                <Chip
                  icon={<ErrorOutline />}
                  label={beforeHealth || '—'}
                  color={beforeHealthColor}
                  sx={{ fontWeight: 900, fontSize: 14, px: 1.25, py: 0.5 }}
                />

                <Box sx={{ mt: 2 }}>
                  <Typography sx={{ fontWeight: 900, fontSize: 16, mb: 0.5 }}>Deviation %</Typography>
                  <Typography sx={{ fontWeight: 900, fontSize: 28 }}>
                    {Number.isFinite(Number(beforeDeviation)) ? `${formatNumber(beforeDeviation, 1)}%` : '—'}
                  </Typography>
                </Box>
              </Box>
            </Box>
          </Paper>
        </Grid>

        <Grid item xs={12} md={6}>
          <Paper elevation={0} sx={{ p: 2.5, borderRadius: 2, border: '1px solid #eaeaea' }}>
            <Typography fontWeight={900} sx={{ fontSize: 20, mb: 1.5 }}>
              After Cleaning
            </Typography>
            <Box sx={{ display: 'flex', gap: 2, flexDirection: { xs: 'column', sm: 'row' } }}>
              <Box sx={{ flex: 1 }}>
                <Typography sx={{ fontWeight: 900, fontSize: 16, mb: 0.5 }}>Image</Typography>
                <Box
                  sx={{
                    borderRadius: 2,
                    border: '1px solid #eaeaea',
                    overflow: 'hidden',
                    bgcolor: '#fff',
                    height: 240,
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center'
                  }}
                >
                  {afterImage ? (
                    <img src={afterImage} alt="After cleaning" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                  ) : (
                    <Typography color="text.secondary" sx={{ fontWeight: 800 }}>
                      No image
                    </Typography>
                  )}
                </Box>
              </Box>

              <Box sx={{ flex: 1 }}>
                <Typography sx={{ fontWeight: 900, fontSize: 16, mb: 1 }}>Power (W)</Typography>
                <Typography sx={{ fontWeight: 900, fontSize: 34, mb: 0.5 }}>
                  {afterPower !== null && afterPower !== undefined ? formatNumber(afterPower, 2) : '—'}
                </Typography>
                {afterPowerStored === null && liveChannelPowerW !== null ? (
                  <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 1, fontWeight: 700 }}>
                    Live reading from solar API (channel P{channelIdx})
                  </Typography>
                ) : null}

                <Typography sx={{ fontWeight: 900, fontSize: 16, mb: 1 }}>Health Status</Typography>
                <Chip
                  icon={<CheckCircle />}
                  label={afterHealth || '—'}
                  color={afterHealthColor}
                  sx={{ fontWeight: 900, fontSize: 14, px: 1.25, py: 0.5 }}
                />

                <Box sx={{ mt: 2 }}>
                  <Typography sx={{ fontWeight: 900, fontSize: 16, mb: 0.5 }}>Deviation %</Typography>
                  <Typography sx={{ fontWeight: 900, fontSize: 28 }}>
                    {Number.isFinite(Number(afterDeviation)) ? `${formatNumber(afterDeviation, 1)}%` : '—'}
                  </Typography>
                </Box>
              </Box>
            </Box>
          </Paper>
        </Grid>

        <Grid item xs={12}>
          <Paper elevation={0} sx={{ p: 2.5, borderRadius: 2, border: '1px solid #eaeaea' }}>
            <Typography fontWeight={900} sx={{ fontSize: 20, mb: 1.5 }}>
              Comparison Summary
            </Typography>

            <Grid container spacing={2} alignItems="center">
              <Grid item xs={12} md={4}>
                <Typography sx={{ fontWeight: 900, fontSize: 16, mb: 0.5 }}>Power Difference (W)</Typography>
                <Typography sx={{ fontWeight: 900, fontSize: 34 }}>
                  {beforePower !== null && afterPower !== null ? formatNumber(afterPower - beforePower, 2) : '—'}
                </Typography>
              </Grid>

              <Grid item xs={12} md={4}>
                <Typography sx={{ fontWeight: 900, fontSize: 16, mb: 0.5 }}>Improvement %</Typography>
                <Typography sx={{ fontWeight: 900, fontSize: 34, mb: 1 }}>
                  {toFinite(improvementPercent) !== null ? `${formatNumber(improvementPercent, 2)}%` : '—'}
                </Typography>
                <LinearProgress
                  variant="determinate"
                  value={progressValue}
                  sx={{ height: 10, borderRadius: 5, bgcolor: '#e5e7eb' }}
                />
              </Grid>

              <Grid item xs={12} md={4}>
                <Typography sx={{ fontWeight: 900, fontSize: 16, mb: 0.5 }}>Verification Status</Typography>
                <Chip
                  icon={resolution === 'Resolved' ? <CheckCircle /> : <ErrorOutline />}
                  label={resolution || '—'}
                  color={resolutionColor}
                  sx={{ fontWeight: 900, fontSize: 14, px: 1.25, py: 0.5 }}
                />
              </Grid>
            </Grid>

            <Box sx={{ mt: 2 }}>
              <Typography sx={{ fontWeight: 900, fontSize: 16, mb: 0.5 }}>Energy Recovered (Wh)</Typography>
              <Typography sx={{ fontWeight: 900, fontSize: 28 }}>
                {energyRecoveredWh !== null ? formatNumber(energyRecoveredWh, 2) : '—'}
              </Typography>
            </Box>
          </Paper>
        </Grid>
      </Grid>
    </Box>
  );
};

export default MaintenanceComparisonAnalysis;
