import React, { useMemo, useState } from 'react';
import {
  Box,
  Breadcrumbs,
  Button,
  FormControl,
  Grid,
  InputLabel,
  Link,
  MenuItem,
  Paper,
  Select,
  Stack,
  Typography
} from '@mui/material';
import { Download } from '@mui/icons-material';
import {
  Area,
  AreaChart,
  CartesianGrid,
  Legend,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis
} from 'recharts';

const panelNameFromId = (panelId) => {
  if (!panelId) return 'All Panels';
  const map = {
    'PL01-B02-INV03-STR05-P01': 'Panel SN-2041',
    'PL01-B02-INV03-STR05-P02': 'Panel SN-2042',
    'PL01-B02-INV03-STR05-P03': 'Panel SN-2043'
  };
  return map[panelId] || panelId;
};

const getStaticSeries = (panelId) => {
  const base =
    panelId === 'PL01-B02-INV03-STR05-P02'
      ? { v: 6.9, e: 91 }
      : panelId === 'PL01-B02-INV03-STR05-P03'
        ? { v: 6.6, e: 88 }
        : { v: 7.2, e: 94 };

  const points = ['00:00', '04:00', '08:00', '12:00', '16:00', '20:00', '24:00'];

  const voltage = points.map((t, idx) => {
    const bump = Math.sin((idx / (points.length - 1)) * Math.PI) * 0.55;
    const wobble = (idx % 2 === 0 ? 1 : -1) * 0.08;
    const panel = base.v + bump + wobble;
    const inverter = base.v + bump * 0.92;
    return {
      time: t,
      panelVoltage: Number(panel.toFixed(3)),
      inverterAvg: Number(inverter.toFixed(3))
    };
  });

  const efficiency = points.map((t, idx) => {
    const bump = Math.sin((idx / (points.length - 1)) * Math.PI) * 6.5;
    const drift = idx * 0.2;
    const value = base.e + bump - drift;
    return {
      time: t,
      efficiency: Number(value.toFixed(1))
    };
  });

  return { voltage, efficiency };
};

const HistoricalAnalysis = ({ panelId }) => {
  const [timeRange, setTimeRange] = useState('7d');
  const [resolution, setResolution] = useState('1h');

  const deviceLabel = panelNameFromId(panelId);
  const series = useMemo(() => getStaticSeries(panelId), [panelId]);

  return (
    <Box sx={{ p: 3 }}>
      <Breadcrumbs aria-label="breadcrumb" sx={{ mb: 2, color: 'text.secondary' }}>
        <Link underline="hover" color="inherit" href="#">
          Dashboard
        </Link>
        <Typography color="text.primary">Historical Analysis</Typography>
      </Breadcrumbs>

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
          <Typography variant="h4" fontWeight={800} sx={{ mb: 0.5 }}>
            Analysis & Historical Data
          </Typography>
          <Typography variant="body2" color="text.secondary">
            In-depth performance metrics, panel comparisons, and maintenance history logs.
          </Typography>
        </Box>

        <Button
          variant="contained"
          color="success"
          startIcon={<Download />}
          sx={{ textTransform: 'none', px: 2.5, py: 1.1, borderRadius: 2 }}
          onClick={() => {}}
        >
          Export Report
        </Button>
      </Box>

      <Paper sx={{ p: 2, mb: 3, borderRadius: 2 }} elevation={0}>
        <Stack direction={{ xs: 'column', md: 'row' }} spacing={2}>
          <FormControl size="small" sx={{ minWidth: 160 }}>
            <InputLabel>Last</InputLabel>
            <Select
              label="Last"
              value={timeRange}
              onChange={(e) => setTimeRange(e.target.value)}
            >
              <MenuItem value="24h">24 Hours</MenuItem>
              <MenuItem value="7d">7 Days</MenuItem>
              <MenuItem value="30d">30 Days</MenuItem>
            </Select>
          </FormControl>

          <FormControl size="small" sx={{ minWidth: 220 }}>
            <InputLabel>Device</InputLabel>
            <Select label="Device" value={panelId || 'all'} onChange={() => {}}>
              <MenuItem value={panelId || 'all'}>{deviceLabel}</MenuItem>
            </Select>
          </FormControl>

          <FormControl size="small" sx={{ minWidth: 200 }}>
            <InputLabel>Resolution</InputLabel>
            <Select
              label="Resolution"
              value={resolution}
              onChange={(e) => setResolution(e.target.value)}
            >
              <MenuItem value="15m">15 Min</MenuItem>
              <MenuItem value="1h">1 Hour</MenuItem>
              <MenuItem value="1d">1 Day</MenuItem>
            </Select>
          </FormControl>

          <Button
            variant="outlined"
            sx={{ textTransform: 'none', borderRadius: 2, px: 2.25 }}
            onClick={() => {}}
          >
            Add Filter
          </Button>
        </Stack>
      </Paper>

      <Grid container spacing={3}>
        <Grid item xs={12}>
          <Paper sx={{ p: 2.5, borderRadius: 2 }} elevation={0}>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', mb: 2 }}>
              <Typography variant="h6" fontWeight={800}>
                Voltage vs Time Analysis
              </Typography>
              <Typography variant="caption" color="text.secondary">
                Device: {deviceLabel}
              </Typography>
            </Box>

            <Box sx={{ height: 340 }}>
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={series.voltage} margin={{ top: 10, right: 30, left: 0, bottom: 0 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#eaeaea" />
                  <XAxis dataKey="time" stroke="#666" />
                  <YAxis stroke="#666" domain={['dataMin - 0.5', 'dataMax + 0.5']} />
                  <Tooltip />
                  <Legend />
                  <Line
                    type="monotone"
                    dataKey="panelVoltage"
                    name={deviceLabel}
                    stroke="#22c55e"
                    strokeWidth={3}
                    dot={false}
                  />
                  <Line
                    type="monotone"
                    dataKey="inverterAvg"
                    name="Inverter Average"
                    stroke="#3b82f6"
                    strokeWidth={2}
                    strokeDasharray="4 4"
                    dot={false}
                  />
                </LineChart>
              </ResponsiveContainer>
            </Box>
          </Paper>
        </Grid>

        <Grid item xs={12}>
          <Paper sx={{ p: 2.5, borderRadius: 2 }} elevation={0}>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', mb: 2 }}>
              <Typography variant="h6" fontWeight={800}>
                Efficiency Trends (%)
              </Typography>
              <Button variant="text" color="success" sx={{ textTransform: 'none' }} onClick={() => {}}>
                View Full Metrics
              </Button>
            </Box>

            <Box sx={{ height: 320 }}>
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={series.efficiency} margin={{ top: 10, right: 30, left: 0, bottom: 0 }}>
                  <defs>
                    <linearGradient id="effFill" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="#22c55e" stopOpacity={0.28} />
                      <stop offset="95%" stopColor="#22c55e" stopOpacity={0.02} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" stroke="#eaeaea" />
                  <XAxis dataKey="time" stroke="#666" />
                  <YAxis stroke="#666" domain={[0, 100]} />
                  <Tooltip />
                  <Area
                    type="monotone"
                    dataKey="efficiency"
                    name="Conversion Ratio"
                    stroke="#22c55e"
                    strokeWidth={2.5}
                    fill="url(#effFill)"
                    dot={false}
                  />
                </AreaChart>
              </ResponsiveContainer>
            </Box>
          </Paper>
        </Grid>

        <Grid item xs={12}>
          <Paper sx={{ p: 2.5, borderRadius: 2 }} elevation={0}>
            <Typography variant="h6" fontWeight={800} sx={{ mb: 1 }}>
              Maintenance History (Static)
            </Typography>
            <Typography variant="body2" color="text.secondary">
              {panelId
                ? `Showing sample maintenance events for ${deviceLabel}.`
                : 'Select a panel to view its historical maintenance logs.'}
            </Typography>

            <Box sx={{ mt: 2, display: 'grid', gap: 1.25 }}>
              <Paper variant="outlined" sx={{ p: 1.5, borderRadius: 2 }}>
                <Typography fontWeight={700} variant="body2">
                  2026-01-22
                </Typography>
                <Typography variant="body2" color="text.secondary">
                  Cleaning completed. Output normalized.
                </Typography>
              </Paper>
              <Paper variant="outlined" sx={{ p: 1.5, borderRadius: 2 }}>
                <Typography fontWeight={700} variant="body2">
                  2026-01-08
                </Typography>
                <Typography variant="body2" color="text.secondary">
                  Visual inspection: minor dust accumulation noted.
                </Typography>
              </Paper>
              <Paper variant="outlined" sx={{ p: 1.5, borderRadius: 2 }}>
                <Typography fontWeight={700} variant="body2">
                  2025-12-18
                </Typography>
                <Typography variant="body2" color="text.secondary">
                  Inverter connection check passed.
                </Typography>
              </Paper>
            </Box>
          </Paper>
        </Grid>
      </Grid>
    </Box>
  );
};

export default HistoricalAnalysis;
