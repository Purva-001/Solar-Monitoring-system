import React, { useEffect, useMemo, useState } from 'react';
import {
  Box,
  Card,
  CardContent,
  Grid,
  IconButton,
  Paper,
  Stack,
  Typography,
  Button,
  Dialog
} from '@mui/material';
import {
  Bolt,
  ErrorOutline,
  GridView,
  Refresh,
  Search,
  WarningAmber,
  Videocam,
  Close as CloseIcon
} from '@mui/icons-material';
import {
  Area,
  AreaChart,
  CartesianGrid,
  Cell,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis
} from 'recharts';
import { absNumber } from '../utils/numbers';
import { unwrapPanelReadingsPayload } from '../utils/solarReadings';
import LiveCameraFeed from './LiveCameraFeed';

const DashboardHome = () => {
  const [readingsData, setReadingsData] = useState(null);
  const [readingsError, setReadingsError] = useState(null);
  const [lastUpdated, setLastUpdated] = useState(null);
  const [powerSeries, setPowerSeries] = useState([]);
  const [isCameraOpen, setIsCameraOpen] = useState(false);

  const trunc2 = (n) => {
    const num = Number(n);
    if (!Number.isFinite(num)) return 0;
    return Math.trunc(num * 100) / 100;
  };

  const pickReadingValue = (obj, key) => {
    const raw = obj?.[key];
    if (raw && typeof raw === 'object' && 'value' in raw) return raw.value;
    return raw;
  };

  const rangeMs = 60 * 60 * 1000;

  useEffect(() => {
    let cancelled = false;

    const fetchReadings = async () => {
      try {
        const apiUrl = '/api/panel/readings';

        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 10000);

        const res = await fetch(apiUrl, {
          method: 'GET',
          headers: { Accept: 'application/json' },
          signal: controller.signal,
        });

        clearTimeout(timeoutId);

        const raw = await res.json();
        const data = unwrapPanelReadingsPayload(raw) ?? raw;
        if (cancelled) return;

        setReadingsData(data);
        setReadingsError(null);
        const ts = new Date();
        setLastUpdated(ts);

        const p1 = absNumber(pickReadingValue(data, 'P1') ?? data?.power?.P1 ?? data?.panel1power ?? 0);
        const p2 = absNumber(pickReadingValue(data, 'P2') ?? data?.power?.P2 ?? data?.panel2power ?? 0);
        const p3 = absNumber(pickReadingValue(data, 'P3') ?? data?.power?.P3 ?? data?.panel3power ?? 0);
        const p4 = absNumber(pickReadingValue(data, 'P4') ?? data?.power?.P4 ?? data?.panel4power ?? 0);
        const totalW = p1 + p2 + p3 + p4;

        const tsMs = ts.getTime();

        setPowerSeries((prev) => {
          const next = [
            ...prev,
            {
              tsMs,
              time: ts.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
              w: Number(totalW.toFixed(2))
            }
          ];
          const cutoff = tsMs - (7 * 24 * 60 * 60 * 1000);
          const trimmed = next.filter((p) => Number(p.tsMs || 0) >= cutoff);
          return trimmed.length > 10000 ? trimmed.slice(trimmed.length - 10000) : trimmed;
        });
      } catch (e) {
        if (cancelled) return;
        setReadingsData(null);
        setReadingsError(e?.message || 'Failed to fetch sensor readings');
      }
    };

    fetchReadings();
    const id = setInterval(fetchReadings, 5000);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, []);

  const kpis = useMemo(
    () => {
      const classify = (p) => {
        const ap = Math.abs(Number(p) || 0);
        if (ap >= 5) return 'healthy';
        if (ap >= 1) return 'warning';
        return 'critical';
      };

      const powerKeys = ['P1', 'P2', 'P3', 'P4'];
      const totalPanels =
        powerKeys.filter((k, idx) => {
          const i = idx + 1;
          return (
            pickReadingValue(readingsData, k) != null ||
            readingsData?.power?.[k] != null ||
            readingsData?.[`panel${i}power`] != null
          );
        }).length || powerKeys.length;

      const p1 = absNumber(pickReadingValue(readingsData, 'P1') ?? readingsData?.power?.P1 ?? readingsData?.panel1power ?? 0);
      const p2 = absNumber(pickReadingValue(readingsData, 'P2') ?? readingsData?.power?.P2 ?? readingsData?.panel2power ?? 0);
      const p3 = absNumber(pickReadingValue(readingsData, 'P3') ?? readingsData?.power?.P3 ?? readingsData?.panel3power ?? 0);
      const p4 = absNumber(pickReadingValue(readingsData, 'P4') ?? readingsData?.power?.P4 ?? readingsData?.panel4power ?? 0);
      const classes = [classify(p1), classify(p2), classify(p3), classify(p4)];

      const healthy = classes.filter((c) => c === 'healthy').length;
      const warning = classes.filter((c) => c === 'warning').length;
      const critical = classes.filter((c) => c === 'critical').length;

      const totalW = p1 + p2 + p3 + p4;

      return [
        { label: 'Total Panels', value: String(totalPanels), icon: <GridView />, color: '#2563eb' },
        { label: 'Active', value: String(healthy), icon: <Bolt />, color: '#22c55e' },
        { label: 'Warning', value: String(warning), icon: <WarningAmber />, color: '#f59e0b' },
        { label: 'Critical', value: String(critical), icon: <ErrorOutline />, color: '#ef4444' },
        { label: 'Total Power', value: `${trunc2(totalW).toFixed(2)} W`, icon: <Bolt />, color: '#16a34a' },
      ];
    },
    [readingsData]
  );

  const filteredPowerSeries = useMemo(() => {
    const now = Date.now();
    const cutoff = now - rangeMs;
    return (powerSeries || []).filter((p) => Number(p.tsMs || 0) >= cutoff);
  }, [powerSeries, rangeMs]);

  const yDomain = useMemo(() => {
    if (!filteredPowerSeries || filteredPowerSeries.length === 0) return [0, 10];
    const vals = filteredPowerSeries.map((p) => Number(p.w || 0)).filter((n) => Number.isFinite(n));
    if (vals.length === 0) return [0, 10];
    const min = Math.min(...vals);
    const max = Math.max(...vals);
    const pad = Math.max(1, (max - min) * 0.1);
    return [Math.max(0, min - pad), max + pad];
  }, [filteredPowerSeries]);

  const healthDist = useMemo(
    () => {
      const classify = (p) => {
        const ap = Math.abs(Number(p) || 0);
        if (ap >= 5) return 'healthy';
        if (ap >= 1) return 'warning';
        return 'critical';
      };

      const powerKeys = ['P1', 'P2', 'P3', 'P4'];
      const totalPanels =
        powerKeys.filter((k, idx) => {
          const i = idx + 1;
          return (
            pickReadingValue(readingsData, k) != null ||
            readingsData?.power?.[k] != null ||
            readingsData?.[`panel${i}power`] != null
          );
        }).length || powerKeys.length;

      const p1 = absNumber(pickReadingValue(readingsData, 'P1') ?? readingsData?.power?.P1 ?? readingsData?.panel1power ?? 0);
      const p2 = absNumber(pickReadingValue(readingsData, 'P2') ?? readingsData?.power?.P2 ?? readingsData?.panel2power ?? 0);
      const p3 = absNumber(pickReadingValue(readingsData, 'P3') ?? readingsData?.power?.P3 ?? readingsData?.panel3power ?? 0);
      const p4 = absNumber(pickReadingValue(readingsData, 'P4') ?? readingsData?.power?.P4 ?? readingsData?.panel4power ?? 0);
      const classes = [classify(p1), classify(p2), classify(p3), classify(p4)];

      const healthy = classes.filter((c) => c === 'healthy').length;
      const warning = classes.filter((c) => c === 'warning').length;
      const critical = classes.filter((c) => c === 'critical').length;

      const total = Math.max(1, totalPanels);

      return [
        { name: 'Healthy', value: Math.round((healthy / total) * 100), color: '#22c55e' },
        { name: 'Warning', value: Math.round((warning / total) * 100), color: '#f59e0b' },
        { name: 'Critical', value: Math.round((critical / total) * 100), color: '#ef4444' }
      ];
    },
    [readingsData]
  );

  const totalPanels = useMemo(() => {
    const powerKeys = ['P1', 'P2', 'P3', 'P4'];
    return (
      powerKeys.filter((k, idx) => {
        const i = idx + 1;
        return (
          pickReadingValue(readingsData, k) != null ||
          readingsData?.power?.[k] != null ||
          readingsData?.[`panel${i}power`] != null
        );
      }).length || powerKeys.length
    );
  }, [readingsData]);

  return (
    <Box
      sx={{
        mb: 3,
        p: { xs: 1.5, md: 2.5 },
        borderRadius: 3,
        bgcolor: '#f8fafc',
      }}
    >
      {/* Header */}
      <Paper
        elevation={0}
        sx={{
          p: { xs: 1.75, md: 2.25 },
          mb: 2.25,
          borderRadius: 2.5,
          border: '1px solid #dbeafe',
          background: 'linear-gradient(135deg, #eff6ff 0%, #f0fdf4 100%)',
        }}
      >
        <Box sx={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 2 }}>
          <Box>
            <Typography variant="h4" fontWeight={900} sx={{ letterSpacing: '-0.02em' }}>
              GreenEnergy Park A
            </Typography>
            <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
              Last updated: {lastUpdated ? lastUpdated.toLocaleString() : '—'}
            </Typography>
            {readingsError && (
              <Typography variant="body2" color="error" sx={{ display: 'block', mt: 0.75 }}>
                {readingsError}
              </Typography>
            )}
          </Box>

          <Stack direction="row" spacing={1} alignItems="center">
            {/* Faint / muted Live Camera button */}
            <Button
              variant="contained"
              startIcon={<Videocam sx={{ fontSize: 18 }} />}
              onClick={() => setIsCameraOpen(true)}
              disableElevation
              sx={{
                borderRadius: 2,
                fontWeight: 700,
                textTransform: 'none',
                fontSize: '0.85rem',
                bgcolor: '#bfdbfe',        /* faint blue background */
                color: '#1e40af',          /* dark blue text */
                boxShadow: 'none',
                border: '1px solid #93c5fd',
                '&:hover': {
                  bgcolor: '#93c5fd',      /* slightly deeper on hover */
                  boxShadow: 'none',
                }
              }}
            >
              Live Camera
            </Button>
            <IconButton sx={{ bgcolor: '#ffffff', border: '1px solid #e2e8f0', '&:hover': { bgcolor: '#f8fafc' } }}>
              <Search fontSize="small" />
            </IconButton>
            <IconButton sx={{ bgcolor: '#ffffff', border: '1px solid #e2e8f0', '&:hover': { bgcolor: '#f8fafc' } }}>
              <Refresh fontSize="small" />
            </IconButton>
          </Stack>
        </Box>
      </Paper>

      {/* KPI Cards */}
      <Grid container spacing={1.75} sx={{ mb: 2.5 }}>
        {kpis.map((kpi) => (
          <Grid item xs={12} sm={6} md={4} lg={2} key={kpi.label}>
            <Card
              elevation={0}
              sx={{
                borderRadius: 2.5,
                border: '1px solid #e2e8f0',
                bgcolor: '#fff',
                boxShadow: '0 2px 8px rgba(15,23,42,0.04)'
              }}
            >
              <CardContent sx={{ p: 2.25 }}>
                <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 1.5 }}>
                  <Box
                    sx={{
                      width: 38,
                      height: 38,
                      borderRadius: 2,
                      display: 'grid',
                      placeItems: 'center',
                      bgcolor: `${kpi.color}15`,
                      color: kpi.color
                    }}
                  >
                    {kpi.icon}
                  </Box>
                </Box>

                <Typography variant="body1" color="text.secondary" sx={{ display: 'block', mb: 0.75, fontWeight: 800 }}>
                  {kpi.label}
                </Typography>
                <Typography variant="h4" fontWeight={900} sx={{ lineHeight: 1.1, letterSpacing: '-0.02em' }}>
                  {kpi.value}
                </Typography>
                {kpi.sub ? (
                  <Typography variant="body2" color="text.secondary" sx={{ display: 'block', mt: 0.75 }}>
                    Peak at {kpi.sub}
                  </Typography>
                ) : null}
              </CardContent>
            </Card>
          </Grid>
        ))}
      </Grid>

      {/* Charts Row */}
      <Grid container spacing={1.75}>
        {/* Power Output Chart */}
        <Grid item xs={12} md={8}>
          <Paper elevation={0} sx={{ p: 2.25, borderRadius: 2.5, border: '1px solid #e2e8f0', boxShadow: '0 2px 8px rgba(15,23,42,0.04)' }}>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', mb: 1.5 }}>
              <Box>
                <Typography variant="h5" fontWeight={900}>Power Output vs Time</Typography>
                <Typography variant="body2" color="text.secondary">
                  Performance measured in watts (W)
                </Typography>
              </Box>
              <Typography variant="body2" sx={{ color: '#22c55e', fontWeight: 900 }}>
                LIVE GENERATION
              </Typography>
            </Box>

            <Box sx={{ height: 320 }}>
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={filteredPowerSeries} margin={{ top: 10, right: 20, left: 0, bottom: 0 }}>
                  <defs>
                    <linearGradient id="powerFill" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="#22c55e" stopOpacity={0.25} />
                      <stop offset="100%" stopColor="#22c55e" stopOpacity={0.02} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
                  <XAxis dataKey="time" stroke="#666" minTickGap={24} />
                  <YAxis domain={yDomain} stroke="#666" tickFormatter={(v) => `${Number(v).toFixed(0)} W`} />
                  <Tooltip formatter={(v) => [`${Number(v).toFixed(2)} W`, 'Power']} />
                  <Area type="monotone" dataKey="w" stroke="#22c55e" strokeWidth={3} fill="url(#powerFill)" dot={false} />
                </AreaChart>
              </ResponsiveContainer>
            </Box>
          </Paper>
        </Grid>

        {/* Health Distribution Chart */}
        <Grid item xs={12} md={4}>
          <Paper elevation={0} sx={{ p: 2.25, borderRadius: 2.5, border: '1px solid #e2e8f0', boxShadow: '0 2px 8px rgba(15,23,42,0.04)' }}>
            <Box sx={{ mb: 1.5 }}>
              <Typography variant="h5" fontWeight={900}>Panel Health Distribution</Typography>
              <Typography variant="body2" color="text.secondary">
                Asset status breakdown
              </Typography>
            </Box>

            <Box sx={{ height: 320, position: 'relative' }}>
              <ResponsiveContainer width="100%" height="100%">
                <PieChart>
                  <Pie
                    data={healthDist}
                    dataKey="value"
                    nameKey="name"
                    cx="50%"
                    cy="50%"
                    innerRadius={70}
                    outerRadius={92}
                    paddingAngle={2}
                    stroke="none"
                  >
                    {healthDist.map((entry) => (
                      <Cell key={entry.name} fill={entry.color} />
                    ))}
                  </Pie>
                  <Tooltip formatter={(v) => `${v}%`} />
                </PieChart>
              </ResponsiveContainer>

              <Box
                sx={{
                  position: 'absolute',
                  top: '50%',
                  left: '50%',
                  transform: 'translate(-50%, -50%)',
                  textAlign: 'center'
                }}
              >
                <Typography variant="h4" fontWeight={900}>
                  {totalPanels}
                </Typography>
                <Typography variant="body2" color="text.secondary" sx={{ fontWeight: 900 }}>
                  TOTAL ASSETS
                </Typography>
              </Box>
            </Box>

            <Box sx={{ mt: 2, display: 'flex', flexDirection: 'column', gap: 1 }}>
              {healthDist.map((row) => (
                <Box key={row.name} sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                  <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                    <Box sx={{ width: 10, height: 10, borderRadius: '50%', bgcolor: row.color }} />
                    <Typography variant="body2" color="text.secondary" sx={{ fontWeight: 800 }}>
                      {row.name}
                    </Typography>
                  </Box>
                  <Typography variant="body2" fontWeight={900}>
                    {row.value}%
                  </Typography>
                </Box>
              ))}
            </Box>
          </Paper>
        </Grid>
      </Grid>

      {/* Live Camera Dialog */}
      <Dialog
        open={isCameraOpen}
        onClose={() => setIsCameraOpen(false)}
        maxWidth="md"
        fullWidth
        PaperProps={{ sx: { borderRadius: 3, bgcolor: 'transparent', boxShadow: 'none' } }}
      >
        <Box sx={{ position: 'relative' }}>
          <IconButton
            onClick={() => setIsCameraOpen(false)}
            sx={{
              position: 'absolute',
              right: 8,
              top: 8,
              zIndex: 100,
              bgcolor: 'rgba(255,255,255,0.8)',
              '&:hover': { bgcolor: 'white' }
            }}
          >
            <CloseIcon />
          </IconButton>
          <LiveCameraFeed />
        </Box>
      </Dialog>
    </Box>
  );
};

export default DashboardHome;