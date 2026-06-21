import React, { useMemo, useRef, useState, useEffect } from 'react';
import {
  Alert,
  Box,
  Button,
  Chip,
  CircularProgress,
  Divider,
  Grid,
  IconButton,
  LinearProgress,
  Paper,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableRow,
  Tooltip,
  Typography
} from '@mui/material';
import {
  Add,
  Build,
  CheckCircle,
  Download,
  ErrorOutline,
  CenterFocusStrong,
  Info,
  Insights,
  LocationOn,
  PhotoCamera,
  Remove,
  TrendingUp,
  WarningAmber
} from '@mui/icons-material';
import {
  CartesianGrid,
  Legend,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip as RechartsTooltip,
  XAxis,
  YAxis,
} from 'recharts';
import axios from 'axios';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import './HealthReport.css';
import { absNumber } from '../utils/numbers';
import {
  unwrapPanelReadingsPayload,
  readingsChannelIndexForPanel,
  panelIdOrDefaultForReadings,
  powerFromChannelW,
  sensorCurrentToAmps,
} from '../utils/solarReadings';

const HealthReport = ({ panelId = null, onScheduleMaintenanceOpen, showPanelIdentification = true, showWeatherSummary = true }) => {
  const [reportData, setReportData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [readingsData, setReadingsData] = useState(null);
  const [readingsError, setReadingsError] = useState(null);
  const [perfSeries, setPerfSeries] = useState([]);
  const [weatherData, setWeatherData] = useState(null);
  const [weatherError, setWeatherError] = useState(null);
  const [imageTimestamp, setImageTimestamp] = useState(new Date().getTime());
  const [cameraError, setCameraError] = useState(null);
  const [cameraZoom, setCameraZoom] = useState(1);
  const [useMainCameraFallback, setUseMainCameraFallback] = useState(false);
  const reportCacheRef = useRef(new Map());

  const cameraUrl = process.env.REACT_APP_ESP32_CAMERA_URL || '/api/camera/latest-upload';
  const fallbackMainCameraUrl = process.env.REACT_APP_CAMERA_FALLBACK_URL || '/api/camera/latest-upload';

  const PANEL_META = useMemo(
    () => ({
      'PL01-B02-INV03-STR05-P01': { ratedPowerW: 40, installDate: '01-05-26', x: 12.4, y: 7.9 },
      'PL01-B02-INV03-STR05-P02': { ratedPowerW: 40, installDate: '01-05-26', x: 13.1, y: 7.9 },
      'PL01-B02-INV03-STR05-P03': { ratedPowerW: 40, installDate: '01-05-26', x: 13.8, y: 7.9 },
      'PL01-B02-INV03-STR05-P04': { ratedPowerW: 40, installDate: '01-05-26', x: 14.5, y: 7.9 },
    }),
    []
  );

  const parseInstallDateForAge = (installDateStr) => {
    if (!installDateStr) return null;
    const s = String(installDateStr).trim();
    const ddmmyy = /^(\d{2})-(\d{2})-(\d{2})$/.exec(s);
    if (ddmmyy) {
      const dd = parseInt(ddmmyy[1], 10);
      const mm = parseInt(ddmmyy[2], 10);
      let yy = parseInt(ddmmyy[3], 10);
      yy += yy >= 70 ? 1900 : 2000;
      const dt = new Date(yy, mm - 1, dd);
      return Number.isNaN(dt.getTime()) ? null : dt;
    }
    const d = new Date(s);
    return Number.isNaN(d.getTime()) ? null : d;
  };

  const formatAge = (installDateStr) => {
    const d = parseInstallDateForAge(installDateStr);
    if (!installDateStr || !d || Number.isNaN(d.getTime())) return '—';

    const now = new Date();
    let months = (now.getFullYear() - d.getFullYear()) * 12 + (now.getMonth() - d.getMonth());
    if (now.getDate() < d.getDate()) months -= 1;
    months = Math.max(0, months);
    const years = Math.floor(months / 12);
    const remMonths = months % 12;
    if (years <= 0) return `${remMonths} mo`;
    if (remMonths <= 0) return `${years} yr`;
    return `${years} yr ${remMonths} mo`;
  };

  const pickReadingValue = (obj, key) => {
    const raw = obj?.[key];
    if (raw && typeof raw === 'object' && 'value' in raw) return raw.value;
    return raw;
  };

  const readingsRow = useMemo(
    () => (readingsData ? unwrapPanelReadingsPayload(readingsData) ?? readingsData : null),
    [readingsData]
  );

  const readingsChannelIdx = useMemo(
    () => readingsChannelIndexForPanel(panelIdOrDefaultForReadings(panelId)),
    [panelId]
  );

  useEffect(() => {
    let cancelled = false;

    const cacheKey = panelId || '__default__';
    const cached = reportCacheRef.current.get(cacheKey);
    if (cached) {
      setReportData(cached);
      setLoading(false);
      setError(null);
    }

    const fetchHealthReport = async ({ bypassCache = false } = {}) => {
      try {
        if (bypassCache || !cached) {
          setLoading(true);
        }
        const url = panelId
          ? `/api/panel/health-report?panel_id=${panelId}`
          : '/api/panel/health-report';
        const response = await axios.get(url);
        if (cancelled) return;
        setReportData(response.data);
        reportCacheRef.current.set(cacheKey, response.data);
        setError(null);
      } catch (err) {
        console.error('Error fetching health report:', err);
        if (cancelled) return;
        setReportData(null);
        setError(err?.message || 'Failed to fetch AI health report');
      } finally {
        if (cancelled) return;
        setLoading(false);
      }
    };

    fetchHealthReport();

    return () => {
      cancelled = true;
    };
  }, [panelId]);

  const runAnalysis = async () => {
    const cacheKey = panelId || '__default__';
    try {
      setError(null);
      setLoading(true);
      const url = panelId
        ? `/api/panel/health-report?panel_id=${panelId}`
        : '/api/panel/health-report';
      const response = await axios.get(url);
      setReportData(response.data);
      reportCacheRef.current.set(cacheKey, response.data);
    } catch (err) {
      setError(err?.message || 'Failed to fetch AI health report');
    } finally {
      setLoading(false);
    }
  };

  const exportJson = () => {
    const payload = reportData || data || fallback;
    try {
      const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `health-report_${(payload?.panel_id || panelId || 'panel').toString()}_${new Date().toISOString().slice(0, 19).replace(/[:T]/g, '-')}.json`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
    } catch (e) {
      setError(e?.message || 'Failed to export report');
    }
  };

  useEffect(() => {
    let cancelled = false;

    const fetchWeather = async () => {
      try {
        const res = await fetch('/api/weather/wardha', { method: 'GET' });
        if (!res.ok) throw new Error(`Weather request failed: ${res.status}`);
        const data = await res.json();
        if (cancelled) return;
        setWeatherData(data);
        setWeatherError(null);
      } catch (e) {
        if (cancelled) return;
        setWeatherData(null);
        setWeatherError(e?.message || 'Failed to fetch Wardha weather');
      }
    };

    fetchWeather();
    const id = setInterval(fetchWeather, 60_000);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, []);

  useEffect(() => {
    let cancelled = false;

    const fetchReadings = async () => {
      try {
        const url = panelId ? `/api/panel/readings?panelId=${panelId}` : '/api/panel/readings';
        const res = await fetch(url, { method: 'GET' });
        if (!res.ok) throw new Error(`Readings request failed: ${res.status}`);
        const data = await res.json();
        if (cancelled) return;
        setReadingsData(data);
        setReadingsError(null);
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
  }, [panelId]);

  useEffect(() => {
    const id = setInterval(() => {
      setImageTimestamp(new Date().getTime());
    }, 2000);
    return () => clearInterval(id);
  }, []);

  const fallback = {
    panel_id: panelIdOrDefaultForReadings(panelId),
    string_id: 'String B-12',
    location: 'Sector 4, Row 12',
    last_maintenance: '2023-05-15',
    last_updated: '2023-10-27 10:45 AM',
    current_health: {
      condition: 'Fair',
      health_score: 84,
      voltage_voc: 45.2,
      current_isc: 9.8,
      temperature_c: 42.5,
      efficiency_percent: 18.4,
      max_power_w: 345.2,
    },
    defect: {
      type: 'Soiling / Hotspot',
      confidence: 98.4,
      affected_area: 'Bottom-left corner',
    },
    recommended_actions: [
      { title: 'Surface Cleaning', desc: 'Heavy soiling detected on bottom left corner.', priority: 'High', color: '#22c55e' },
      { title: 'Bypass Diode Check', desc: 'Potential failure in Sub-string 2 connector.', priority: 'Medium', color: '#f59e0b' },
    ],
    root_cause:
      'Local shading from dust accumulation in the lower corner is causing thermal stress on sub-string 3. Sustained heat may lead to delamination if not cleaned within 48 hours.',
    automation: [
      { title: 'Smart Cleaning Drone', desc: 'Scheduled for 04:00 AM', color: '#22c55e' },
      { title: 'Data Sync', desc: 'Real-time Stream Active', color: '#22c55e' },
      { title: 'Security', desc: 'Perimeter Guard Online', color: '#64748b' },
    ],
    curves: [
      { v: 0, i_actual: 9.9, i_ref: 10.2, p_actual: 0, p_ref: 0 },
      { v: 10, i_actual: 9.4, i_ref: 9.8, p_actual: 94, p_ref: 98 },
      { v: 20, i_actual: 8.7, i_ref: 9.2, p_actual: 174, p_ref: 184 },
      { v: 30, i_actual: 7.6, i_ref: 8.3, p_actual: 228, p_ref: 249 },
      { v: 38, i_actual: 6.4, i_ref: 7.4, p_actual: 243, p_ref: 281 },
      { v: 45, i_actual: 3.1, i_ref: 4.5, p_actual: 140, p_ref: 203 },
      { v: 50, i_actual: 0.2, i_ref: 0.5, p_actual: 10, p_ref: 25 },
    ],
    powerTrend: [
      { time: '06:00', mw: 0.7 },
      { time: '09:00', mw: 2.1 },
      { time: '12:00', mw: 1.6 },
      { time: '15:00', mw: 2.0 },
      { time: '18:00', mw: 2.6 },
      { time: '21:00', mw: 2.2 },
    ]
  };

  const deriveHealthScore = ({ defect, confidence01 }) => {
    const c = Number(confidence01);
    if (!Number.isFinite(c)) return undefined;

    const d = String(defect ?? '').toLowerCase().trim();
    if (!d || d === 'none' || d === 'clean') {
      return 95;
    }

    const raw = Math.round(100 - (c * 70));
    return Math.max(10, Math.min(90, raw));
  };

  const mapped = reportData
    ? {
        panel_id: reportData.panel_id,
        location: reportData.location,
        last_updated: reportData.timestamp ? new Date(reportData.timestamp).toLocaleString() : new Date().toLocaleString(),
        current_health: {
          condition:
            reportData.defect_analysis?.defect == null
              ? 'Normal'
              : (reportData.defect_analysis?.defect || reportData.current_health?.condition),
          health_score:
            reportData.current_health?.health_score ??
            deriveHealthScore({
              defect: reportData.defect_analysis?.defect,
              confidence01: reportData.defect_analysis?.confidence,
            }),
          voltage_voc:
            absNumber(
              reportData.current_health?.voltage_avg_volts ??
                reportData.sensor_data?.voltage?.V1
            ),
          current_isc:
            absNumber(
              reportData.current_health?.current_avg_amperes ??
                reportData.sensor_data?.current
            ),
          temperature_c: absNumber(reportData.current_health?.temperature_c),
          max_power_w:
            absNumber(
              reportData.current_health?.max_power_w ??
                reportData.sensor_data?.power?.P1
            ),
        },
        defect: reportData.defect_analysis
          ? {
              type: reportData.defect_analysis?.defect == null ? 'None' : reportData.defect_analysis?.defect,
              confidence: absNumber(reportData.defect_analysis?.confidence || 0) * 100,
              affected_area: reportData.defect_analysis?.affected_area,
            }
          : null,
      }
    : null;

  const readingsMapped = useMemo(() => {
    if (!readingsRow) return null;
    const idx = readingsChannelIdx;
    const vk = `V${idx}`;
    const ik = `I${idx}`;
    const pk = `P${idx}`;
    const legacyV = readingsRow?.[`panel${idx}voltage`];
    const legacyI = readingsRow?.[`panel${idx}current`];
    const legacyP = readingsRow?.[`panel${idx}power`];
    const iScalar = pickReadingValue(readingsRow, ik);
    const currentA =
      iScalar != null && Number.isFinite(absNumber(iScalar))
        ? sensorCurrentToAmps(iScalar)
        : legacyI != null && Number.isFinite(absNumber(legacyI))
          ? sensorCurrentToAmps(legacyI)
          : 0;
    return {
      current_health: {
        voltage_voc: absNumber(
          pickReadingValue(readingsRow, vk) ?? readingsRow?.voltage?.[vk] ?? legacyV
        ),
        current_isc: absNumber(currentA),
        max_power_w: absNumber(
          pickReadingValue(readingsRow, pk) ??
            readingsRow?.power?.[pk] ??
            legacyP ??
            powerFromChannelW(readingsRow, idx)
        ),
      },
    };
  }, [readingsRow, readingsChannelIdx]);

  const data = {
    ...fallback,
    ...(mapped || {}),
    current_health: {
      ...fallback.current_health,
      ...(mapped?.current_health || {}),
      ...(readingsMapped?.current_health || {}),
      temperature_c:
        weatherData?.temperature_c != null
          ? absNumber(weatherData.temperature_c)
          : fallback.current_health.temperature_c,
    },
    defect: {
      ...fallback.defect,
      ...((mapped?.defect || {}) || {})
    }
  };

  const MetricCard = ({ title, value, unit, color }) => (
    <Paper
      elevation={0}
      sx={{
        p: 2,
        borderRadius: 2,
        border: '1px solid #eaeaea',
        bgcolor: '#fff',
        height: '100%'
      }}
    >
      <Typography variant="body2" color="text.secondary" sx={{ display: 'block', mb: 0.75, fontWeight: 800 }}>
        {title}
      </Typography>
      <Box sx={{ display: 'flex', alignItems: 'baseline', gap: 1, flexWrap: 'nowrap' }}>
        <Typography variant="h4" fontWeight={900} sx={{ lineHeight: 1.05 }}>
          {value}
        </Typography>
        {unit ? (
          <Typography
            variant="h6"
            fontWeight={900}
            color="text.secondary"
            sx={{ whiteSpace: 'nowrap', lineHeight: 1.05 }}
          >
            {unit}
          </Typography>
        ) : null}
      </Box>
      <LinearProgress
        variant="determinate"
        value={Math.max(5, Math.min(100, absNumber(value) * 2))}
        sx={{
          mt: 1,
          height: 6,
          borderRadius: 10,
          bgcolor: '#eef2f7',
          '& .MuiLinearProgress-bar': { bgcolor: color }
        }}
      />
    </Paper>
  );

  const showData = reportData ? data : fallback;
  const showHealthScore = Number(showData.current_health.health_score || 0);
  const showConfidencePct = absNumber(showData?.defect?.confidence || 0);
  const confidenceColor =
    showConfidencePct >= 90 ? '#16a34a' : showConfidencePct >= 70 ? '#f59e0b' : '#ef4444';

  const panelMeta = PANEL_META[showData.panel_id] || { ratedPowerW: 10, installDate: showData?.last_maintenance };
  const expectedPowerW = absNumber(panelMeta?.ratedPowerW ?? 10);
  const latestPowerW = absNumber(showData?.current_health?.max_power_w);
  const outputVsExpectedPct = expectedPowerW > 0 ? (latestPowerW / expectedPowerW) * 100 : null;
  const showStatus =
    showHealthScore >= 90
      ? { label: 'HEALTHY', color: '#22c55e', icon: CheckCircle }
      : showHealthScore >= 75
        ? { label: 'NEEDS ATTENTION', color: '#f59e0b', icon: WarningAmber }
        : { label: 'CRITICAL', color: '#ef4444', icon: ErrorOutline };

  const operatingStateLabel =
    showStatus.label === 'HEALTHY'
      ? 'Normal'
      : showStatus.label === 'NEEDS ATTENTION'
        ? 'Warning'
        : 'Fault';

  const [, setMaintenanceDefectStatus] = useState({ electrical: 'PENDING', crack: 'PENDING' });

  useEffect(() => {
    const pid = showData?.panel_id;
    if (!pid) return;
    try {
      const raw = localStorage.getItem(`defectStatus::${pid}`);
      if (!raw) {
        setMaintenanceDefectStatus({ electrical: 'PENDING', crack: 'PENDING' });
        return;
      }
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed === 'object') {
        setMaintenanceDefectStatus({
          electrical: String(parsed.electrical || 'PENDING'),
          crack: String(parsed.crack || 'PENDING'),
        });
      }
    } catch {
      setMaintenanceDefectStatus({ electrical: 'PENDING', crack: 'PENDING' });
    }
  }, [showData?.panel_id]);

  useEffect(() => {
    const pid = showData?.panel_id;
    if (!pid) return;
    const onStorage = (e) => {
      if (e?.key !== `defectStatus::${pid}`) return;
      try {
        const parsed = JSON.parse(e.newValue || '{}');
        if (parsed && typeof parsed === 'object') {
          setMaintenanceDefectStatus({
            electrical: String(parsed.electrical || 'PENDING'),
            crack: String(parsed.crack || 'PENDING'),
          });
        }
      } catch {
        // ignore
      }
    };
    window.addEventListener('storage', onStorage);
    return () => window.removeEventListener('storage', onStorage);
  }, [showData?.panel_id]);

  useEffect(() => {
    const pid = showData?.panel_id;
    if (!pid) return;
    const pw = Number(latestPowerW);
    if (!Number.isFinite(pw)) return;
    try {
      localStorage.setItem(`panelPowerW::${pid}`, String(pw));
    } catch {
      // ignore
    }
  }, [latestPowerW, showData?.panel_id]);

  useEffect(() => {
    const expected = Number.isFinite(expectedPowerW) ? Number(expectedPowerW) : null;
    if (expected == null) return;

    const outputNum = readingsRow
      ? powerFromChannelW(readingsRow, readingsChannelIdx)
      : 0;
    if (!Number.isFinite(outputNum)) return;

    const now = new Date();
    const t = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });

    setPerfSeries((prev) => {
      const next = Array.isArray(prev) ? prev.slice() : [];
      const last = next[next.length - 1];
      if (last && last.t === t) {
        next[next.length - 1] = { ...last, expected, output: Math.max(0, outputNum) };
      } else {
        next.push({ t, expected, output: Math.max(0, outputNum) });
      }
      return next.slice(Math.max(0, next.length - 30));
    });
  }, [readingsRow, readingsChannelIdx, expectedPowerW]);

  const performanceChartData = useMemo(() => {
    if (perfSeries.length >= 2) return perfSeries;
    const expected = Number.isFinite(expectedPowerW) ? Number(expectedPowerW) : 0;
    const output = Number.isFinite(latestPowerW) ? Number(latestPowerW) : 0;
    return [
      { t: '—', expected, output },
      { t: 'Now', expected, output },
    ];
  }, [perfSeries, expectedPowerW, latestPowerW]);

  const aiRecommendationMarkdown =
    (typeof reportData?.health_report === 'string' && reportData.health_report.trim())
      ? reportData.health_report
      : null;

  const markdownComponents = useMemo(
    () => ({
      h1: ({ children, ...props }) => (
        <Typography variant="h5" fontWeight={900} sx={{ mt: 0, mb: 1.25 }} {...props}>
          {children}
        </Typography>
      ),
      h2: ({ children, ...props }) => (
        <Typography variant="h6" fontWeight={900} sx={{ mt: 1.75, mb: 1 }} {...props}>
          {children}
        </Typography>
      ),
      h3: ({ children, ...props }) => (
        <Typography variant="subtitle1" fontWeight={900} sx={{ mt: 1.25, mb: 0.75 }} {...props}>
          {children}
        </Typography>
      ),
      p: ({ children, ...props }) => (
        <Typography variant="body1" color="text.secondary" sx={{ mb: 1, lineHeight: 1.8 }} {...props}>
          {children}
        </Typography>
      ),
      ul: ({ children, ...props }) => (
        <Box component="ul" sx={{ pl: 2.25, mb: 1.25, mt: 0.5, color: 'text.secondary' }} {...props}>
          {children}
        </Box>
      ),
      ol: ({ children, ...props }) => (
        <Box component="ol" sx={{ pl: 2.25, mb: 1.25, mt: 0.5, color: 'text.secondary' }} {...props}>
          {children}
        </Box>
      ),
      li: ({ children, ...props }) => (
        <Box component="li" sx={{ mb: 0.5, lineHeight: 1.7 }} {...props}>
          <Typography component="span" variant="body2" color="text.secondary">
            {children}
          </Typography>
        </Box>
      ),
      table: ({ children, ...props }) => (
        <Box
          sx={{
            width: '100%',
            overflowX: 'auto',
            mb: 1.5,
            border: '1px solid #eaeaea',
            borderRadius: 2,
          }}
        >
          <Box component="table" sx={{ width: '100%', borderCollapse: 'collapse' }} {...props}>
            {children}
          </Box>
        </Box>
      ),
      th: ({ children, ...props }) => (
        <Box
          component="th"
          sx={{
            textAlign: 'left',
            fontSize: 14,
            fontWeight: 900,
            color: '#111827',
            p: 1,
            borderBottom: '1px solid #eaeaea',
            bgcolor: '#f8fafc',
            whiteSpace: 'nowrap',
          }}
          {...props}
        >
          {children}
        </Box>
      ),
      td: ({ children, ...props }) => (
        <Box component="td" sx={{ fontSize: 14, p: 1, borderBottom: '1px solid #f1f5f9', color: '#334155' }} {...props}>
          {children}
        </Box>
      ),
      code: ({ children, ...props }) => (
        <Box
          component="code"
          sx={{
            fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace',
            fontSize: 13,
            bgcolor: '#f1f5f9',
            color: '#0f172a',
            px: 0.75,
            py: 0.25,
            borderRadius: 1,
          }}
          {...props}
        >
          {children}
        </Box>
      ),
      img: ({ alt, src, ...props }) => {
        const rawSrc = typeof src === 'string' ? src : '';
        const preferJpgSrc = rawSrc
          ? rawSrc.replace(/\.png(\?.*)?$/i, '.jpg$1')
          : rawSrc;

        const initialSrc = rawSrc && /\.png(\?.*)?$/i.test(rawSrc) ? preferJpgSrc : rawSrc;

        return (
          <Box
            component="img"
            alt={alt || ''}
            src={initialSrc}
            onError={(e) => {
              const el = e?.currentTarget;
              if (!el) return;
              if (rawSrc && el.src && el.src.includes(preferJpgSrc) && rawSrc !== preferJpgSrc) {
                el.src = rawSrc;
              }
            }}
            sx={{
              display: 'block',
              maxWidth: '100%',
              height: 'auto',
              borderRadius: 2,
              border: '1px solid #eaeaea',
              my: 1.5,
            }}
            {...props}
          />
        );
      },
    }),
    []
  );

  const pickMarkdownSection = (md, titles) => {
    if (!md) return null;
    const t = new Set((titles || []).map((x) => String(x || '').trim().toLowerCase()).filter(Boolean));
    const lines = String(md).replace(/\r\n/g, '\n').split('\n');

    const isHeading = (line) => /^#{1,6}\s+/.test(line);
    const headingLevel = (line) => (line.match(/^#{1,6}/)?.[0]?.length || 0);
    const headingTitle = (line) => String(line.replace(/^#{1,6}\s+/, '')).trim().toLowerCase();

    for (let i = 0; i < lines.length; i += 1) {
      const line = lines[i];
      if (!isHeading(line)) continue;
      if (!t.has(headingTitle(line))) continue;

      const level = headingLevel(line);
      const start = i;
      let end = lines.length;
      for (let j = i + 1; j < lines.length; j += 1) {
        if (!isHeading(lines[j])) continue;
        if (headingLevel(lines[j]) <= level) {
          end = j;
          break;
        }
      }
      const chunk = lines.slice(start, end).join('\n').trim();
      return chunk || null;
    }

    return null;
  };

  const truncateMarkdownLines = (md, maxLines = 14) => {
    if (!md) return md;
    const lines = String(md).replace(/\r\n/g, '\n').split('\n');
    if (lines.length <= maxLines) return md;
    return `${lines.slice(0, maxLines).join('\n').trim()}\n\n...`;
  };

  const sanitizeSummaryMarkdown = (md) => {
    if (!md) return md;
    const defectType = String(showData?.defect?.type || '').trim().toLowerCase();
    const hasNoDefect = defectType === 'none' || defectType === '';
    if (!hasNoDefect) return md;

    const s = String(md);
    // Replace the Summary table cell for Defect Detected when Gemini still returns "Clean".
    // Expected row: | **Defect Detected** | Clean |
    return s.replace(
      /\|\s*\*\*Defect Detected\*\*\s*\|\s*clean\s*\|/gi,
      '| **Defect Detected** | None |'
    );
  };

  const summaryMarkdown = pickMarkdownSection(aiRecommendationMarkdown, ['summary']);
  const rootCauseMarkdown = pickMarkdownSection(aiRecommendationMarkdown, ['root cause analysis', 'root cause']);
  const recommendationsMarkdown = pickMarkdownSection(aiRecommendationMarkdown, [
    'recommendations',
    'recommended actions',
    'recommended action',
  ]);

  const summaryMarkdownDisplay = sanitizeSummaryMarkdown(summaryMarkdown || aiRecommendationMarkdown);

  const containsKbNotFound = /not\s+found\s+in\s+retrieved\s+knowledge/i.test(
    String(aiRecommendationMarkdown || '')
  );

  const defaultRecommendationsClean = `## Recommendations\n\n- Continue monitoring for 24 hours\n- Schedule routine cleaning if dust is visible\n- Re-scan after next peak sun window`;

  const defaultRecommendationsIssue = `## Recommendations\n\n- Inspect panel surface for dust/soiling and clean if needed\n- Check connectors and junction box for heating/loose contact\n- Re-scan and compare confidence after maintenance`;

  const defaultRootCauseClean = `## Root Cause Analysis\n\nNo defect detected in the latest scan. Minor variation may be due to temporary weather/irradiance changes or sensor noise.`;

  const defaultRootCauseIssue = `## Root Cause Analysis\n\nThe detected defect may be caused by surface soiling/dust buildup, localized heating (hotspot), or a connector/junction issue leading to reduced effective output.`;

  const isClean = String(showData?.defect?.type || showData?.current_health?.condition || '')
    .toLowerCase()
    .includes('clean');

  const recommendationsBase =
    recommendationsMarkdown ||
    aiRecommendationMarkdown ||
    (isClean ? defaultRecommendationsClean : defaultRecommendationsIssue);

  const rootCauseBase = rootCauseMarkdown || showData?.root_cause || (isClean ? defaultRootCauseClean : defaultRootCauseIssue);

  const recommendationsShort = truncateMarkdownLines(
    containsKbNotFound
      ? (isClean ? defaultRecommendationsClean : defaultRecommendationsIssue)
      : recommendationsBase,
    16
  );

  return (
    <Box
      sx={{
        '& .MuiTypography-root': { fontWeight: 800 },
        '& .MuiTypography-h3': { fontSize: { xs: '2.4rem', md: '3.2rem' }, fontWeight: 900 },
        '& .MuiTypography-h4': { fontSize: { xs: '2.0rem', md: '2.5rem' }, fontWeight: 900 },
        '& .MuiTypography-h5': { fontSize: { xs: '1.6rem', md: '2.0rem' }, fontWeight: 900 },
        '& .MuiTypography-h6': { fontSize: { xs: '1.35rem', md: '1.6rem' }, fontWeight: 900 },
        '& .MuiTypography-body1': { fontSize: { xs: '1.15rem', md: '1.35rem' }, fontWeight: 800 },
        '& .MuiTypography-body2': { fontSize: { xs: '1.05rem', md: '1.25rem' }, fontWeight: 800 },
        '& .MuiTypography-caption': { fontSize: { xs: '0.95rem', md: '1.1rem' }, fontWeight: 900, letterSpacing: '0.6px' },
        '& .MuiChip-label': { fontSize: { xs: '1.05rem', md: '1.2rem' }, fontWeight: 900 },
        '& .MuiTableCell-root': { fontSize: { xs: '1.05rem', md: '1.2rem' }, fontWeight: 800 },
        '& .MuiButton-root': { fontSize: { xs: '1.05rem', md: '1.2rem' }, fontWeight: 900 },
        '& .recharts-text': { fontSize: 18, fontWeight: 900 },
      }}
    >
      {showWeatherSummary && (
        <Paper elevation={0} sx={{ p: 2, mb: 2, borderRadius: 2, border: '1px solid #eaeaea' }}>
          <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 2, flexWrap: 'wrap' }}>
            <Box>
              <Typography variant="caption" color="text.secondary" sx={{ display: 'block' }}>
                CITY
              </Typography>
              <Typography fontWeight={900}>
                {weatherData?.city || 'Wardha'}
              </Typography>
            </Box>

            <Box>
              <Typography variant="caption" color="text.secondary" sx={{ display: 'block' }}>
                WEATHER
              </Typography>
              <Typography fontWeight={900}>
                {weatherData?.condition ?? '—'}
              </Typography>
            </Box>

            <Box>
              <Typography variant="caption" color="text.secondary" sx={{ display: 'block' }}>
                TEMPERATURE
              </Typography>
              <Typography fontWeight={900}>
                {weatherData?.temperature_c != null ? `${Number(weatherData.temperature_c).toFixed(1)} °C` : '—'}
              </Typography>
            </Box>

            <Box>
              <Typography variant="caption" color="text.secondary" sx={{ display: 'block' }}>
                HUMIDITY
              </Typography>
              <Typography fontWeight={900}>
                {weatherData?.humidity_percent != null ? `${Number(weatherData.humidity_percent).toFixed(0)}%` : '—'}
              </Typography>
            </Box>
          </Box>

          {weatherError && (
            <Alert severity="warning" sx={{ mt: 1.5 }}>
              {weatherError}
            </Alert>
          )}
        </Paper>
      )}

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
          <Typography variant="h3" fontWeight={900} sx={{ mb: 0.5 }}>
            Panel Health Report: {showData.panel_id}
          </Typography>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            <Box sx={{ width: 8, height: 8, borderRadius: '50%', bgcolor: '#22c55e' }} />
            <Typography variant="body1" color="text.secondary" sx={{ fontWeight: 700 }}>
              Last updated: {showData.last_updated}
            </Typography>
          </Box>
        </Box>

        <Box sx={{ display: 'flex', gap: 1.25, flexWrap: 'wrap' }}>
          <Button
            variant="outlined"
            startIcon={<Download />}
            sx={{ textTransform: 'none', borderRadius: 2 }}
            onClick={exportJson}
          >
            Export
          </Button>
          <Button
            variant="outlined"
            startIcon={<Insights />}
            sx={{ textTransform: 'none', borderRadius: 2 }}
            onClick={runAnalysis}
            disabled={loading}
          >
            Re-run Analysis
          </Button>
          <Button
            variant="contained"
            color="success"
            startIcon={<Build />}
            sx={{ textTransform: 'none', borderRadius: 2 }}
            onClick={() => onScheduleMaintenanceOpen?.(showData.panel_id)}
          >
            Schedule Maintenance
          </Button>
        </Box>
      </Box>

      {error && <Alert severity="error" sx={{ mb: 2 }}>{error}</Alert>}

      {readingsError && <Alert severity="warning" sx={{ mb: 2 }}>{readingsError}</Alert>}

      {reportData?.gemini_error && (
        <Alert severity="warning" sx={{ mb: 2 }}>
          {String(reportData.gemini_error)}
        </Alert>
      )}

      {loading && (
        <Paper sx={{ p: 2, mb: 2, borderRadius: 2, border: '1px solid #eaeaea' }} elevation={0}>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
            <CircularProgress size={18} />
            <Typography variant="body2" color="text.secondary">
              Auto-updating health report...
            </Typography>
          </Box>
        </Paper>
      )}

          <Grid container spacing={2.5}>
            {showPanelIdentification && (
              <Grid item xs={12} md={6}>
          <Paper elevation={0} sx={{ p: 2.5, borderRadius: 2, border: '1px solid #eaeaea' }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 2 }}>
              <Info sx={{ color: '#22c55e' }} />
              <Typography variant="h6" fontWeight={900}>Panel Identification & Status</Typography>
            </Box>

            <Paper variant="outlined" sx={{ borderRadius: 2, overflow: 'hidden' }}>
              <Table size="small">
                <TableBody>
                  <TableRow>
                    <TableCell sx={{ fontWeight: 900, fontSize: 15 }}>Panel ID</TableCell>
                    <TableCell>{showData.panel_id}</TableCell>
                    <TableCell sx={{ fontWeight: 900, fontSize: 15 }}>String ID</TableCell>
                    <TableCell>
                      <Chip label={showData.string_id} size="small" sx={{ bgcolor: '#f1f5f9' }} />
                    </TableCell>
                  </TableRow>
                  <TableRow>
                    <TableCell sx={{ fontWeight: 900, fontSize: 15 }}>Coordinates (X,Y)</TableCell>
                    <TableCell>
                      {panelMeta?.x != null && panelMeta?.y != null
                        ? `${absNumber(panelMeta.x).toFixed(2)}, ${absNumber(panelMeta.y).toFixed(2)}`
                        : '—'}
                    </TableCell>
                    <TableCell sx={{ fontWeight: 900, fontSize: 15 }}>Last Inspection</TableCell>
                    <TableCell>{showData.last_updated}</TableCell>
                  </TableRow>
                  <TableRow>
                    <TableCell sx={{ fontWeight: 900, fontSize: 15 }}>Rated Power</TableCell>
                    <TableCell>{absNumber(expectedPowerW).toFixed(0)} W</TableCell>
                    <TableCell sx={{ fontWeight: 900, fontSize: 15 }}>Operating State</TableCell>
                    <TableCell>
                      <Chip
                        label={operatingStateLabel}
                        size="small"
                        sx={{ bgcolor: `${showStatus.color}14`, color: showStatus.color, fontWeight: 800 }}
                      />
                    </TableCell>
                  </TableRow>
                  <TableRow>
                    <TableCell sx={{ fontWeight: 900, fontSize: 15 }}>Install Date</TableCell>
                    <TableCell>{panelMeta?.installDate || '—'}</TableCell>
                    <TableCell sx={{ fontWeight: 900, fontSize: 15 }}>Panel Age</TableCell>
                    <TableCell>{formatAge(panelMeta?.installDate)}</TableCell>
                  </TableRow>
                  <TableRow>
                    <TableCell sx={{ fontWeight: 900, fontSize: 15 }}>Output vs Expected</TableCell>
                    <TableCell>
                      {outputVsExpectedPct == null || !Number.isFinite(outputVsExpectedPct)
                        ? '—'
                        : `${outputVsExpectedPct.toFixed(0)}%`}
                    </TableCell>
                    <TableCell sx={{ fontWeight: 900, fontSize: 15 }}>Expected Output</TableCell>
                    <TableCell>{absNumber(expectedPowerW).toFixed(0)} W</TableCell>
                  </TableRow>
                </TableBody>
              </Table>
            </Paper>

            <Grid container spacing={2} sx={{ mt: 2 }}>
              <Grid item xs={12} sm={6}>
                <Paper
                  elevation={0}
                  sx={{
                    p: 2.25,
                    borderRadius: 2,
                    border: '1px solid #eaeaea',
                    bgcolor: `${showStatus.color}10`
                  }}
                >
                  <Typography variant="caption" sx={{ color: showStatus.color, fontWeight: 900 }}>
                    CURRENT HEALTH STATUS
                  </Typography>
                  <Typography variant="h5" fontWeight={900} sx={{ mt: 0.75, color: showStatus.color }}>
                    {showStatus.label}
                  </Typography>
                  <Typography variant="body2" color="text.secondary" sx={{ mt: 0.75 }}>
                    Minor efficiency drop detected ({showHealthScore.toFixed(0)}%)
                  </Typography>
                </Paper>
              </Grid>
              <Grid item xs={12} sm={6}>
                <Paper elevation={0} sx={{ p: 2.25, borderRadius: 2, border: '1px solid #eaeaea' }}>
                  <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
                    <Box
                      sx={{
                        width: 42,
                        height: 42,
                        borderRadius: '50%',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        bgcolor: '#dcfce7',
                        color: '#16a34a'
                      }}
                    >
                      <Insights />
                    </Box>
                    <Box>
                      <Typography variant="caption" color="text.secondary" sx={{ display: 'block' }}>
                        MAX POWER OUTPUT
                      </Typography>
                      <Typography variant="h5" fontWeight={900}>
                        {absNumber(showData.current_health.max_power_w).toFixed(1)} W
                      </Typography>
                    </Box>
                  </Box>
                </Paper>
              </Grid>
            </Grid>
          </Paper>

          <Grid container spacing={2} sx={{ mt: 0.5, alignItems: 'stretch' }}>
            <Grid item xs={12} sm={6} md={4}>
              <MetricCard title="VOLTAGE (VOC)" value={absNumber(showData.current_health.voltage_voc).toFixed(1)} unit="V" color="#22c55e" />
            </Grid>
            <Grid item xs={12} sm={6} md={4}>
              <MetricCard title="CURRENT (ISC)" value={absNumber(showData.current_health.current_isc).toFixed(1)} unit="A" color="#22c55e" />
            </Grid>
            <Grid item xs={12} sm={6} md={4}>
              <MetricCard
                title="TEMPERATURE"
                value={
                  weatherData?.temperature_c != null
                    ? absNumber(weatherData.temperature_c).toFixed(1)
                    : absNumber(showData.current_health.temperature_c).toFixed(1)
                }
                unit="°C"
                color="#f59e0b"
              />
            </Grid>
          </Grid>

          <Paper elevation={0} sx={{ p: 2.5, mt: 2.5, borderRadius: 2, border: '1px solid #eaeaea' }}>
            <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 2, flexWrap: 'wrap', mb: 1.5 }}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                <TrendingUp sx={{ color: '#22c55e' }} />
                <Typography fontWeight={900} variant="h6">
                  Performance Charts
                </Typography>
              </Box>
              <Chip
                label={`Output vs Expected: ${outputVsExpectedPct == null || !Number.isFinite(outputVsExpectedPct) ? '—' : `${outputVsExpectedPct.toFixed(0)}%`}`}
                size="small"
                sx={{ bgcolor: '#dcfce7', color: '#16a34a', fontWeight: 900, fontSize: 14 }}
              />
            </Box>

            <Typography variant="body2" color="text.secondary" sx={{ fontWeight: 900, mb: 1.5 }}>
              Output vs Expected (W)
            </Typography>

            <Box sx={{ width: '100%', height: 260 }}>
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={performanceChartData} margin={{ top: 10, right: 18, left: 6, bottom: 10 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
                  <XAxis dataKey="t" tick={{ fontWeight: 900, fontSize: 18 }} />
                  <YAxis tick={{ fontWeight: 900, fontSize: 18 }} />
                  <RechartsTooltip
                    contentStyle={{ fontWeight: 900, borderRadius: 10, border: '1px solid #e5e7eb' }}
                    formatter={(v) => [`${Number(v).toFixed(2)} W`, 'Power']}
                  />
                  <Legend wrapperStyle={{ fontWeight: 900, fontSize: 18 }} />
                  <Line
                    type="monotone"
                    dataKey="expected"
                    name="Expected"
                    stroke="#16a34a"
                    strokeWidth={3}
                    dot={{ r: 2 }}
                    activeDot={{ r: 5 }}
                  />
                  <Line
                    type="monotone"
                    dataKey="output"
                    name="Output"
                    stroke="#0ea5e9"
                    strokeWidth={3}
                    dot={{ r: 2 }}
                    activeDot={{ r: 5 }}
                  />
                </LineChart>
              </ResponsiveContainer>
            </Box>
          </Paper>


        </Grid>
        )}

        <Grid item xs={12} md={6}>
          <Paper elevation={0} sx={{ p: 2.5, mt: 2.5, borderRadius: 2, border: '1px solid #eaeaea' }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 2 }}>
              <PhotoCamera sx={{ color: '#22c55e' }} />
              <Typography fontWeight={900}>AI Visual Inspection</Typography>
            </Box>

              <Grid container spacing={2}>
              <Grid item xs={12} md={8}>
                <Box
                  sx={{
                    position: 'relative',
                    height: { xs: 260, md: 360 },
                    borderRadius: 2,
                    overflow: 'hidden',
                    bgcolor: '#0b1220',
                    border: '1px solid #0f172a',
                    backgroundImage:
                      'linear-gradient(135deg, rgba(34,197,94,0.15) 0%, rgba(59,130,246,0.08) 55%, rgba(15,23,42,0.35) 100%)'
                  }}
                >
                  {cameraError && (
                    <Alert severity="warning" sx={{ position: 'absolute', top: 10, left: 10, right: 10, zIndex: 3 }}>
                      {cameraError}
                    </Alert>
                  )}

                  <Box
                    sx={{
                      position: 'absolute',
                      top: 12,
                      right: 12,
                      display: 'flex',
                      flexDirection: 'column',
                      gap: 1,
                      zIndex: 4,
                    }}
                  >
                    <Tooltip title="Zoom in">
                      <IconButton
                        size="small"
                        onClick={() => setCameraZoom((z) => Math.min(2.5, Number(z || 1) + 0.25))}
                        sx={{ bgcolor: 'rgba(255,255,255,0.92)', border: '1px solid #eaeaea' }}
                      >
                        <Add fontSize="small" />
                      </IconButton>
                    </Tooltip>
                    <Tooltip title="Zoom out">
                      <IconButton
                        size="small"
                        onClick={() => setCameraZoom((z) => Math.max(1, Number(z || 1) - 0.25))}
                        sx={{ bgcolor: 'rgba(255,255,255,0.92)', border: '1px solid #eaeaea' }}
                      >
                        <Remove fontSize="small" />
                      </IconButton>
                    </Tooltip>
                    <Tooltip title="Reset zoom">
                      <IconButton
                        size="small"
                        onClick={() => setCameraZoom(1)}
                        sx={{ bgcolor: 'rgba(255,255,255,0.92)', border: '1px solid #eaeaea' }}
                      >
                        <CenterFocusStrong fontSize="small" />
                      </IconButton>
                    </Tooltip>
                  </Box>

                  <Box
                    sx={{
                      position: 'absolute',
                      inset: 0,
                      transform: `scale(${cameraZoom})`,
                      transformOrigin: 'center center',
                      transition: 'transform 120ms ease-out',
                    }}
                  >
                    <img
                      src={
                        useMainCameraFallback
                          ? `${fallbackMainCameraUrl}?t=${imageTimestamp}`
                          : `${cameraUrl}?t=${imageTimestamp}`
                      }
                      alt="AI visual inspection"
                      crossOrigin="anonymous"
                      referrerPolicy="no-referrer"
                      onError={() => {
                        if (!useMainCameraFallback) {
                          setUseMainCameraFallback(true);
                          setCameraError('Camera feed not available. Showing fallback image.');
                          return;
                        }
                        setCameraError('Camera feed not available. Showing fallback image.');
                      }}
                      onLoad={() => {
                        setCameraError(null);
                      }}
                      style={{
                        position: 'absolute',
                        inset: 0,
                        width: '100%',
                        height: '100%',
                        objectFit: 'cover',
                        opacity: 0.98,
                      }}
                    />
                  </Box>

                  <Box
                    sx={{
                      position: 'absolute',
                      inset: 0,
                      pointerEvents: 'none',
                      background:
                        'repeating-linear-gradient(0deg, rgba(255,255,255,0.04), rgba(255,255,255,0.04) 1px, transparent 1px, transparent 18px), repeating-linear-gradient(90deg, rgba(255,255,255,0.04), rgba(255,255,255,0.04) 1px, transparent 1px, transparent 18px)'
                    }}
                  />

                  <Box
                    sx={{
                      position: 'absolute',
                      left: '34%',
                      top: '28%',
                      width: '30%',
                      height: '42%',
                      border: '2px solid rgba(239, 68, 68, 0.85)',
                      borderRadius: 1.5,
                      pointerEvents: 'none',
                    }}
                  />

                  <Box
                    sx={{
                      position: 'absolute',
                      left: 12,
                      bottom: 12,
                      display: 'flex',
                      alignItems: 'center',
                      gap: 1.25,
                      bgcolor: 'rgba(2,6,23,0.55)',
                      border: '1px solid rgba(255,255,255,0.12)',
                      px: 1.25,
                      py: 0.85,
                      borderRadius: 2,
                    }}
                  >
                    <Typography variant="caption" sx={{ color: '#e2e8f0' }}>
                      Panel: <span style={{ fontWeight: 900 }}>{showData.panel_id}</span>
                    </Typography>
                    <Divider orientation="vertical" flexItem sx={{ borderColor: 'rgba(255,255,255,0.12)' }} />
                    <Typography variant="caption" sx={{ color: '#a7f3d0', fontWeight: 900 }}>
                      {cameraError ? 'Fallback image' : 'Live feed'}
                    </Typography>
                    <Divider orientation="vertical" flexItem sx={{ borderColor: 'rgba(255,255,255,0.12)' }} />
                    <Typography variant="caption" sx={{ color: '#cbd5e1' }}>
                      Zoom: <span style={{ fontWeight: 900 }}>{cameraZoom.toFixed(2)}x</span>
                    </Typography>
                  </Box>
                </Box>
              </Grid>

              <Grid item xs={12} md={4}>
                <Paper elevation={0} sx={{ p: 2.25, borderRadius: 2, border: '1px solid #eaeaea', height: '100%' }}>
                  <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 1, mb: 1.75 }}>
                    <Typography fontWeight={900}>
                      AI Diagnosis
                    </Typography>
                  </Box>

                  <Typography variant="caption" color="text.secondary" sx={{ display: 'block' }}>
                    DEFECT TYPE
                  </Typography>
                  <Typography fontWeight={900} sx={{ mb: 1.25 }}>
                    {String(showData?.defect?.type || showData?.current_health?.condition || '—')}
                  </Typography>

                  <Typography variant="caption" color="text.secondary" sx={{ display: 'block' }}>
                    CONFIDENCE
                  </Typography>
                  <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 1 }}>
                    <LinearProgress
                      variant="determinate"
                      value={Math.max(0, Math.min(100, showConfidencePct))}
                      sx={{
                        flex: 1,
                        height: 8,
                        borderRadius: 10,
                        bgcolor: '#eef2f7',
                        '& .MuiLinearProgress-bar': { bgcolor: confidenceColor },
                      }}
                    />
                    <Typography fontWeight={900} sx={{ minWidth: 56, textAlign: 'right' }}>
                      {showConfidencePct.toFixed(1)}%
                    </Typography>
                  </Box>

                  <Typography variant="body2" color="text.secondary" sx={{ mt: 2, lineHeight: 1.7 }}>
                    Use the Recommendations section to take action.
                  </Typography>
                </Paper>
              </Grid>
            </Grid>
          </Paper>

          

          {reportData && (
            <Paper elevation={0} sx={{ p: 2.5, mt: 2.5, borderRadius: 2, border: '1px solid #eaeaea' }}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 2 }}>
                <LocationOn sx={{ color: '#22c55e' }} />
                <Typography fontWeight={900}>Root Cause Analysis</Typography>
              </Box>
              <Chip
                label="PROBABLE CAUSE"
                size="small"
                sx={{ mb: 1.25, bgcolor: '#dcfce7', color: '#16a34a', fontWeight: 900 }}
              />
              <Box sx={{ color: 'text.secondary' }}>
                <ReactMarkdown remarkPlugins={[remarkGfm]} components={markdownComponents}>
                  {rootCauseBase}
                </ReactMarkdown>
              </Box>
            </Paper>
          )}

          {reportData && (summaryMarkdown || recommendationsMarkdown || aiRecommendationMarkdown) && (
            <Paper elevation={0} sx={{ p: 2.5, mt: 2.5, borderRadius: 2, border: '1px solid #eaeaea' }}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 2 }}>
                <Insights sx={{ color: '#22c55e' }} />
                <Typography fontWeight={900}>AI Summary</Typography>
              </Box>

              <Box sx={{ color: 'text.secondary' }}>
                <ReactMarkdown remarkPlugins={[remarkGfm]} components={markdownComponents}>
                  {summaryMarkdownDisplay}
                </ReactMarkdown>
              </Box>
            </Paper>
          )}

          {reportData && (
            <Paper elevation={0} sx={{ p: 2.5, mt: 2.5, borderRadius: 2, border: '1px solid #eaeaea' }}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 2 }}>
                <CheckCircle sx={{ color: '#22c55e' }} />
                <Typography fontWeight={900}>Recommendations</Typography>
              </Box>

              <Box sx={{ color: 'text.secondary' }}>
                <ReactMarkdown remarkPlugins={[remarkGfm]} components={markdownComponents}>
                  {recommendationsShort}
                </ReactMarkdown>
              </Box>
            </Paper>
          )}
        </Grid>
      </Grid>

      
    </Box>
  );

};

export default HealthReport;
