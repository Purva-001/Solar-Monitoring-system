import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  Alert,
  Box,
  Grid,
  IconButton,
  Paper,
  Skeleton,
  Typography
} from '@mui/material';
import { Refresh } from '@mui/icons-material';
import {
  CartesianGrid,
  Legend,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis
} from 'recharts';
import MetricLineChart from './solarHistory/MetricLineChart';
import { fetchSolarHistory, fetchSolarIvPvSnapshot } from '../services/solarHistoryApi';
import { absNumber } from '../utils/numbers';
import './SolarHistory.css';

const defaultAssetId = 'SolarPanel_01';
const REFRESH_MS = 30000;

const SolarHistory = ({ assetId = defaultAssetId, isActive = true }) => {
  const [data, setData] = useState([]);
  const [ivPvLatest, setIvPvLatest] = useState(null);
  const [ivPvError, setIvPvError] = useState(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState(null);
  const [lastUpdated, setLastUpdated] = useState(null);
  const didInitFetchRef = useRef(false);
  const prevActiveRef = useRef(isActive);
  const dataRef = useRef([]);
  const ivPvLatestRef = useRef(null);

  const formatDateTime = (ms) => {
    try {
      return new Intl.DateTimeFormat(undefined, {
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit'
      }).format(new Date(ms));
    } catch {
      return new Date(ms).toLocaleString();
    }
  };

  const toMetricValue = (v) => {
    if (v != null && typeof v === 'object' && 'value' in v) return v.value;
    return v;
  };

  const pick = (row, key) => {
    const v = toMetricValue(row?.[key]);
    return v == null ? null : v;
  };

  const extractTimestampMs = (row) => {
    const candidate =
      row?.tsMs ??
      row?.timestampMs ??
      row?.timestamp ??
      row?.ts ??
      row?.time ??
      row?.datetime ??
      row?.V1?.timestamp ??
      row?.P1?.timestamp ??
      row?.I?.timestamp;

    const n = Number(candidate);
    if (!Number.isFinite(n) || n <= 0) return null;

    // Heuristic: if it's in seconds (e.g. 1770804910), convert to ms.
    return n < 1e12 ? n * 1000 : n;
  };

  const normalizeRows = (rows) => {
    if (!Array.isArray(rows)) return [];
    return rows
      .map((r) => {
        const tsMs = extractTimestampMs(r);

        const v1 = absNumber(pick(r, 'V1'));
        const v2 = absNumber(pick(r, 'V2'));
        const v3 = absNumber(pick(r, 'V3'));
        const v4 = absNumber(pick(r, 'V4'));

        const rowI_mA = absNumber(pick(r, 'I'));

        const rawI1 = pick(r, 'I1');
        const rawI2 = pick(r, 'I2');
        const rawI3 = pick(r, 'I3');
        const rawI4 = pick(r, 'I4');

        const hasPanelCurrents = [rawI1, rawI2, rawI3, rawI4].some((v) => v != null);

        const i1_mA = absNumber(hasPanelCurrents ? rawI1 : rowI_mA);
        const i2_mA = absNumber(hasPanelCurrents ? rawI2 : rowI_mA);
        const i3_mA = absNumber(hasPanelCurrents ? rawI3 : rowI_mA);
        const i4_mA = absNumber(hasPanelCurrents ? rawI4 : rowI_mA);

        const i1 = i1_mA / 1000.0;
        const i2 = i2_mA / 1000.0;
        const i3 = i3_mA / 1000.0;
        const i4 = i4_mA / 1000.0;

        const rawP1 = pick(r, 'P1');
        const rawP2 = pick(r, 'P2');
        const rawP3 = pick(r, 'P3');
        const rawP4 = pick(r, 'P4');

        const p1 = absNumber(rawP1 != null ? rawP1 : (Number.isFinite(i1) && Number.isFinite(v1) ? i1 * v1 : 0));
        const p2 = absNumber(rawP2 != null ? rawP2 : (Number.isFinite(i2) && Number.isFinite(v2) ? i2 * v2 : 0));
        const p3 = absNumber(rawP3 != null ? rawP3 : (Number.isFinite(i3) && Number.isFinite(v3) ? i3 * v3 : 0));
        const p4 = absNumber(rawP4 != null ? rawP4 : (Number.isFinite(i4) && Number.isFinite(v4) ? i4 * v4 : 0));

        const totalCurrentA = hasPanelCurrents ? (i1 + i2 + i3 + i4) : (rowI_mA / 1000.0);
        const totalCurrentmA = Number.isFinite(rowI_mA) && rowI_mA > 0 ? rowI_mA : (totalCurrentA * 1000.0);

        return {
          ...r,
          tsMs,
          timeLabel: tsMs ? new Date(tsMs).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : '',
          dateTimeLabel: tsMs ? formatDateTime(tsMs) : '',
          V1: v1,
          V2: v2,
          V3: v3,
          V4: v4,
          P1: p1,
          P2: p2,
          P3: p3,
          P4: p4,
          I1_mA: i1_mA,
          I2_mA: i2_mA,
          I3_mA: i3_mA,
          I4_mA: i4_mA,
          I_mA: absNumber(totalCurrentmA),
          I: absNumber(totalCurrentA),
        };
      })
      .sort((a, b) => Number(a.tsMs || 0) - Number(b.tsMs || 0));
  };

  const fetchHistory = async () => {
    const hasData = Array.isArray(dataRef.current) && dataRef.current.length > 0;
    const hadIvPv = ivPvLatestRef.current != null;

    try {
      if (!hasData) {
        setLoading(true);
      } else {
        setRefreshing(true);
      }
      setError(null);

      const [histRes, snapRes] = await Promise.allSettled([
        fetchSolarHistory({ assetId }),
        fetchSolarIvPvSnapshot({ timeoutMs: 10000 }),
      ]);

      if (histRes.status === 'rejected') {
        const reason = histRes.reason;
        throw reason instanceof Error ? reason : new Error(String(reason));
      }

      const rows = histRes.value;
      if (!Array.isArray(rows)) {
        throw new Error('Invalid API response: expected an array');
      }

      const normalized = normalizeRows(rows);
      dataRef.current = normalized;
      setData(normalized);

      if (snapRes.status === 'fulfilled') {
        const raw = snapRes.value;
        const snapArr = Array.isArray(raw) ? raw : raw != null && typeof raw === 'object' ? [raw] : [];
        const normSnap = normalizeRows(snapArr);
        const last = normSnap.length ? normSnap[normSnap.length - 1] : null;
        ivPvLatestRef.current = last;
        setIvPvLatest(last);
        setIvPvError(null);
      } else {
        const msg =
          (snapRes.reason && snapRes.reason.message) ||
          String(snapRes.reason || 'Failed to load I–V / P–V snapshot');
        setIvPvError(msg);
        if (!hadIvPv) {
          ivPvLatestRef.current = null;
          setIvPvLatest(null);
        }
      }

      setLastUpdated(new Date());
    } catch (e) {
      if (!hasData) {
        dataRef.current = [];
        setData([]);
      }
      setError(e?.message || 'Failed to fetch historical data');
    } finally {
      setRefreshing(false);
      setLoading(false);
    }
  };

  useEffect(() => {
    if (!isActive) {
      prevActiveRef.current = false;
      return undefined;
    }

    const becameActive = prevActiveRef.current === false;
    prevActiveRef.current = true;

    if (!didInitFetchRef.current || becameActive) {
      didInitFetchRef.current = true;
      fetchHistory();
    }
    const id = setInterval(fetchHistory, REFRESH_MS);
    return () => clearInterval(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [assetId, isActive]);

  const ivCurve = useMemo(() => {
    if (!ivPvLatest) return [];

    const row = ivPvLatest;
    const points = [
      { voltage: absNumber(row?.V1 ?? 0), current: absNumber(row?.I1_mA ?? row?.I_mA ?? 0), label: 'V1' },
      { voltage: absNumber(row?.V2 ?? 0), current: absNumber(row?.I2_mA ?? row?.I_mA ?? 0), label: 'V2' },
      { voltage: absNumber(row?.V3 ?? 0), current: absNumber(row?.I3_mA ?? row?.I_mA ?? 0), label: 'V3' },
      { voltage: absNumber(row?.V4 ?? 0), current: absNumber(row?.I4_mA ?? row?.I_mA ?? 0), label: 'V4' }
    ];

    return points
      .filter((p) => Number.isFinite(Number(p.voltage)))
      .map((p) => ({
        voltage: Number(Number(p.voltage).toFixed(4)),
        current: Number(Number(p.current).toFixed(0)),
        label: p.label
      }))
      .sort((a, b) => a.voltage - b.voltage);
  }, [ivPvLatest]);

  const pvCurve = useMemo(() => {
    if (!ivPvLatest) return [];

    const row = ivPvLatest;
    const points = [
      {
        voltage: absNumber(row?.V1 ?? 0),
        power: absNumber(row?.P1 ?? 0),
        label: 'P1'
      },
      {
        voltage: absNumber(row?.V2 ?? 0),
        power: absNumber(row?.P2 ?? 0),
        label: 'P2'
      },
      {
        voltage: absNumber(row?.V3 ?? 0),
        power: absNumber(row?.P3 ?? 0),
        label: 'P3'
      },
      {
        voltage: absNumber(row?.V4 ?? 0),
        power: absNumber(row?.P4 ?? 0),
        label: 'P4'
      }
    ];

    return points
      .filter((p) => Number.isFinite(Number(p.voltage)))
      .map((p) => ({
        voltage: Number(Number(p.voltage).toFixed(4)),
        power: Number(Number(p.power).toFixed(4)),
        label: p.label
      }))
      .sort((a, b) => a.voltage - b.voltage);
  }, [ivPvLatest]);

  return (
    <Box className="solarHistoryPage">
      <Box className="solarHistoryHeader">
        <Box>
          <Typography variant="h4" fontWeight={900} sx={{ mb: 0.35 }}>
            Solar History
          </Typography>
          <Typography variant="body1" color="text.secondary" sx={{ display: 'block', fontWeight: 800 }}>
            Asset: {assetId}
          </Typography>
          <Typography variant="body1" color="text.secondary" sx={{ display: 'block', fontWeight: 800 }}>
            Last updated: {lastUpdated ? lastUpdated.toLocaleString() : '—'}
          </Typography>
        </Box>

        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          {refreshing && (
            <Typography variant="body2" color="text.secondary" sx={{ mr: 1, fontWeight: 800 }}>
              Refreshing…
            </Typography>
          )}
          <IconButton
            onClick={fetchHistory}
            sx={{ bgcolor: '#eef2ff', '&:hover': { bgcolor: '#e0e7ff' } }}
            aria-label="Refresh history"
          >
            <Refresh fontSize="small" />
          </IconButton>
        </Box>
      </Box>

      {error ? (
        <Alert severity="error" sx={{ mb: 2 }}>
          {error}
        </Alert>
      ) : null}

      {!error && ivPvError ? (
        <Alert severity="warning" sx={{ mb: 2 }}>
          I–V / P–V snapshot (live API): {ivPvError}
        </Alert>
      ) : null}

      {loading ? (
        <Paper elevation={0} sx={{ p: 4, borderRadius: 2, border: '1px solid #eaeaea', bgcolor: '#fff' }}>
          <Grid container spacing={2} sx={{ mb: 2 }}>
            {Array.from({ length: 8 }).map((_, idx) => (
              <Grid item xs={12} sm={6} md={4} lg={3} key={idx}>
                <Paper elevation={0} sx={{ p: 2.25, borderRadius: 2, border: '1px solid #eaeaea' }}>
                  <Skeleton variant="rounded" width={38} height={38} />
                  <Skeleton variant="text" sx={{ mt: 1.5 }} width="40%" />
                  <Skeleton variant="text" width="60%" />
                </Paper>
              </Grid>
            ))}
          </Grid>

          <Paper elevation={0} sx={{ p: 2.5, borderRadius: 2, border: '1px solid #eaeaea' }}>
            <Skeleton variant="text" width="30%" />
            <Skeleton variant="text" width="50%" />
            <Skeleton variant="rounded" sx={{ mt: 2 }} height={280} />
          </Paper>
        </Paper>
      ) : !error && (!data || data.length === 0) && !ivPvLatest ? (
        <Paper elevation={0} sx={{ p: 4, borderRadius: 2, border: '1px solid #eaeaea', bgcolor: '#fff' }}>
          <Typography variant="h6" fontWeight={900} sx={{ mb: 0.75 }}>
            No historical data available
          </Typography>
          <Typography variant="body1" color="text.secondary">
            Try refreshing, or check if the backend proxy is running.
          </Typography>
        </Paper>
      ) : (
        <>
          <Grid container spacing={2}>
            <Grid item xs={12} md={6}>
              <Paper elevation={0} sx={{ p: 2.5, borderRadius: 2, border: '1px solid #eaeaea', height: '100%' }}>
                <Box sx={{ mb: 1.5 }}>
                  <Typography fontWeight={900}>I-V Curve</Typography>
                  <Typography variant="caption" color="text.secondary">
                    Current (mA) vs Voltage (V) from the live solar API snapshot
                  </Typography>
                </Box>
                <Box sx={{ height: 320 }}>
                  <ResponsiveContainer width="100%" height="100%">
                    <LineChart data={ivCurve} margin={{ top: 10, right: 24, left: 28, bottom: 6 }}>
                      <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
                      <XAxis
                        dataKey="voltage"
                        type="number"
                        stroke="#666"
                        tickMargin={10}
                        tickFormatter={(v) => `${absNumber(v).toFixed(2)} V`}
                      />
                      <YAxis
                        stroke="#666"
                        width={72}
                        tickMargin={10}
                        tickFormatter={(v) => `${absNumber(v).toFixed(0)} mA`}
                      />
                      <Tooltip
                        formatter={(v) => `${absNumber(v).toFixed(0)} mA`}
                        labelFormatter={(l) => `Voltage: ${absNumber(l).toFixed(4)} V`}
                      />
                      <Legend />
                      <Line
                        type="monotone"
                        dataKey="current"
                        name="Current"
                        stroke="#2563eb"
                        strokeWidth={3}
                        dot={{ r: 5 }}
                        isAnimationActive={false}
                      />
                    </LineChart>
                  </ResponsiveContainer>
                </Box>
              </Paper>
            </Grid>

            <Grid item xs={12} md={6}>
              <Paper elevation={0} sx={{ p: 2.5, borderRadius: 2, border: '1px solid #eaeaea', height: '100%' }}>
                <Box sx={{ mb: 1.5 }}>
                  <Typography fontWeight={900}>P-V Curve</Typography>
                  <Typography variant="caption" color="text.secondary">
                    Power (W) vs Voltage (V) from the live solar API snapshot
                  </Typography>
                </Box>
                <Box sx={{ height: 320 }}>
                  <ResponsiveContainer width="100%" height="100%">
                    <LineChart data={pvCurve} margin={{ top: 10, right: 24, left: 28, bottom: 6 }}>
                      <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
                      <XAxis
                        dataKey="voltage"
                        type="number"
                        stroke="#666"
                        tickMargin={10}
                        tickFormatter={(v) => `${absNumber(v).toFixed(2)} V`}
                      />
                      <YAxis
                        stroke="#666"
                        width={72}
                        tickMargin={10}
                        tickFormatter={(v) => `${absNumber(v).toFixed(2)} W`}
                      />
                      <Tooltip
                        formatter={(v) => `${absNumber(v).toFixed(4)} W`}
                        labelFormatter={(l) => `Voltage: ${absNumber(l).toFixed(4)} V`}
                      />
                      <Legend />
                      <Line
                        type="monotone"
                        dataKey="power"
                        name="Power"
                        stroke="#22c55e"
                        strokeWidth={3}
                        dot={{ r: 5 }}
                        isAnimationActive={false}
                      />
                    </LineChart>
                  </ResponsiveContainer>
                </Box>
              </Paper>
            </Grid>

            <Grid item xs={12}>
              <MetricLineChart
                title="Voltage (V)"
                subtitle="Historical voltage readings (solar history API)"
                data={data}
                yUnit="V"
                yDecimals={2}
                lines={[
                  { dataKey: 'V1', name: 'V1' },
                  { dataKey: 'V2', name: 'V2' },
                  { dataKey: 'V3', name: 'V3' },
                  { dataKey: 'V4', name: 'V4' }
                ]}
              />
            </Grid>

            <Grid item xs={12}>
              <MetricLineChart
                title="Power (W)"
                subtitle="Historical power readings (solar history API)"
                data={data}
                yUnit="W"
                yDecimals={2}
                lines={[
                  { dataKey: 'P1', name: 'P1' },
                  { dataKey: 'P2', name: 'P2' },
                  { dataKey: 'P3', name: 'P3' },
                  { dataKey: 'P4', name: 'P4' }
                ]}
              />
            </Grid>

            <Grid item xs={12}>
              <MetricLineChart
                title="Current (A)"
                subtitle="Historical current readings (solar history API)"
                data={data}
                yUnit="A"
                yDecimals={0}
                lines={[{ dataKey: 'I', name: 'I' }]}
              />
            </Grid>
          </Grid>
        </>
      )}
    </Box>
  );
};

export default SolarHistory;
