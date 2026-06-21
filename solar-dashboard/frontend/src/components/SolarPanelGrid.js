import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { Grid, Paper, Typography, Box, CircularProgress, Alert, Button, Dialog, DialogTitle, DialogContent, DialogActions, Tabs, Tab } from '@mui/material';
import { ErrorOutline, CheckCircle, Videocam, Close } from '@mui/icons-material';
import CameraViewer from './CameraViewer';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { absNumber } from '../utils/numbers';
import { unwrapPanelReadingsPayload } from '../utils/solarReadings';

const SolarPanelGrid = ({ onPanelSelect, onHealthReportOpen }) => {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [cameraOpen, setCameraOpen] = useState(false);
  const [selectedPanelId, setSelectedPanelId] = useState(null);
  const [detailsOpen, setDetailsOpen] = useState(false);
  const [selectedPanel, setSelectedPanel] = useState(null);
  const [panelData, setPanelData] = useState(null);
  const [dataLoading, setDataLoading] = useState(false);
  const [tabValue, setTabValue] = useState(0);

  const pickReadingValue = (obj, key) => {
    const raw = obj?.[key];
    if (raw && typeof raw === 'object' && 'value' in raw) return raw.value;
    return raw;
  };

  const normalizeCurrentToA = (v) => {
    const n = absNumber(v);
    if (!Number.isFinite(n)) return 0;
    // Backend returns panelXcurrent in Amps. Legacy payloads may provide mA.
    // If value looks like mA, convert to A.
    return Math.abs(n) > 50 ? n / 1000 : n;
  };

  const pickPanelVoltage = (data, idx) =>
    absNumber(
      pickReadingValue(data, `V${idx}`) ?? data?.voltage?.[`V${idx}`] ?? data?.[`panel${idx}voltage`] ?? 0
    );

  const pickPanelPowerW = (data, idx) => {
    const raw =
      pickReadingValue(data, `P${idx}`) ??
      data?.power?.[`P${idx}`] ??
      data?.[`panel${idx}power`];
    if (raw != null) return absNumber(raw);

    const v = pickPanelVoltage(data, idx);
    const iA = pickPanelCurrentA(data, idx);
    return absNumber(Number.isFinite(v) && Number.isFinite(iA) ? v * iA : 0);
  };

  const pickPanelCurrentA = (data, idx) => {
    const legacy = pickReadingValue(data, `I${idx}`) ?? pickReadingValue(data, 'I') ?? data?.current;
    const flat = data?.[`panel${idx}current`];
    return normalizeCurrentToA(legacy ?? flat ?? 0);
  };

  const VALUES_ENDPOINT = '/api/panel/readings';

  const panels = useMemo(
    () => [
      { id: 'PL01-B02-INV03-STR05-P01', name: 'Solar Panel 1', location: 'Panel 1' },
      { id: 'PL01-B02-INV03-STR05-P02', name: 'Solar Panel 2', location: 'Panel 2' },
      { id: 'PL01-B02-INV03-STR05-P03', name: 'Solar Panel 3', location: 'Panel 3' },
      { id: 'PL01-B02-INV03-STR05-P04', name: 'Solar Panel 4', location: 'Panel 4' }
    ],
    []
  );

  const SENSOR_MAP = useMemo(
    () => ({
      'PL01-B02-INV03-STR05-P01': { idx: 1 },
      'PL01-B02-INV03-STR05-P02': { idx: 2 },
      'PL01-B02-INV03-STR05-P03': { idx: 3 },
      'PL01-B02-INV03-STR05-P04': { idx: 4 }
    }),
    []
  );

  const fetchPanelData = useCallback(async () => {
    try {
      setError(null);
      const res = await fetch(VALUES_ENDPOINT, { method: 'GET' });
      if (!res.ok) throw new Error(`Request failed: ${res.status}`);
      const raw = await res.json();
      const data = unwrapPanelReadingsPayload(raw) ?? raw;
      setPanelData(data && typeof data === 'object' && !Array.isArray(data) ? data : null);
    } catch (e) {
      setPanelData(null);
      setError(e?.message || 'Failed to fetch live panel values');
    } finally {
      setLoading(false);
      setDataLoading(false);
    }
  }, [VALUES_ENDPOINT]);

  useEffect(() => {
    fetchPanelData();
    const id = setInterval(fetchPanelData, 5000);
    return () => clearInterval(id);
  }, [fetchPanelData]);

  const handleOpenCamera = (panelId) => {
    setSelectedPanelId(panelId);
    setCameraOpen(true);
  };

  const handleCloseCamera = () => {
    setCameraOpen(false);
    setSelectedPanelId(null);
  };

  const handleOpenDetails = (panel) => {
    setSelectedPanel(panel);
    setDetailsOpen(true);
    setDataLoading(true); // ✅ Show loading state
    fetchPanelData();
  };

  const handleCloseDetails = () => {
    setDetailsOpen(false);
    setSelectedPanel(null);
    setPanelData(null);
    setTabValue(0);
  };

  // Generate IV Curve data - Live values (V1/V2/V3/V4 and I in A)
  const generateIVCurveData = () => {
    if (!panelData) return [];
    const points = [
      { voltage: pickPanelVoltage(panelData, 1), current: pickPanelCurrentA(panelData, 1), label: 'V1' },
      { voltage: pickPanelVoltage(panelData, 2), current: pickPanelCurrentA(panelData, 2), label: 'V2' },
      { voltage: pickPanelVoltage(panelData, 3), current: pickPanelCurrentA(panelData, 3), label: 'V3' },
      { voltage: pickPanelVoltage(panelData, 4), current: pickPanelCurrentA(panelData, 4), label: 'V4' }
    ];

    return points
      .filter((p) => Number.isFinite(p.voltage))
      .map((p) => ({
        voltage: Number(p.voltage.toFixed(4)),
        current: Number(p.current.toFixed(4)),
        label: p.label
      }))
      .sort((a, b) => a.voltage - b.voltage);
  };

  const generatePVCurveData = () => {
    if (!panelData) return [];

    const points = [
      { voltage: pickPanelVoltage(panelData, 1), power: pickPanelPowerW(panelData, 1), label: 'P1' },
      { voltage: pickPanelVoltage(panelData, 2), power: pickPanelPowerW(panelData, 2), label: 'P2' },
      { voltage: pickPanelVoltage(panelData, 3), power: pickPanelPowerW(panelData, 3), label: 'P3' },
      { voltage: pickPanelVoltage(panelData, 4), power: pickPanelPowerW(panelData, 4), label: 'P4' }
    ];

    return points
      .filter((p) => Number.isFinite(p.voltage))
      .map((p) => ({
        voltage: Number(p.voltage.toFixed(4)),
        power: Number(absNumber(p.power).toFixed(4)),
        label: p.label
      }))
      .sort((a, b) => a.voltage - b.voltage);
  };

  // Wrap PanelCard with React.memo to prevent unnecessary re-renders
  const PanelCard = React.memo(({ panel, panelData }) => {
    // Get sensor data based on panel ID
    const getPanelSensorData = () => {
      // Default values if no sensor data
      if (!panelData) {
        return { 
          voltage: 0,
          power: 0,
          current: 0
        };
      }

      try {
        const map = SENSOR_MAP[panel.id];
        const idx = map?.idx;
        const voltage = idx ? pickPanelVoltage(panelData, idx) : 0;
        const current = idx ? pickPanelCurrentA(panelData, idx) : 0; // A
        const power = idx ? pickPanelPowerW(panelData, idx) : 0; // W

        return { 
          voltage: Number(voltage.toFixed(4)),
          power: Number(power.toFixed(4)),
          current: Number(current.toFixed(4))
        };
      } catch (err) {
        console.error(`Error parsing sensor data for ${panel.name}:`, err);
        return { voltage: 0, power: 0, current: 0 };
      }
    };

    const sensorData = getPanelSensorData();

    const status = Math.abs(sensorData.power) >= 5 ? 'active' : Math.abs(sensorData.power) >= 1 ? 'warning' : 'defect';
    const statusMeta =
      status === 'active'
        ? { label: 'Active', color: '#16a34a', bg: '#f0fdf4', border: '#86efac', icon: <CheckCircle sx={{ color: '#16a34a', fontSize: 24 }} /> }
        : status === 'warning'
          ? { label: 'Warning', color: '#b45309', bg: '#fffbeb', border: '#fcd34d', icon: <CheckCircle sx={{ color: '#f59e0b', fontSize: 24 }} /> }
          : { label: 'Defect', color: '#b91c1c', bg: '#fef2f2', border: '#fca5a5', icon: <ErrorOutline sx={{ color: '#ef4444', fontSize: 24 }} /> };

    return (
      <Paper
        sx={{
          p: 2,
          height: '100%',
          borderRadius: 2,
          boxShadow: '0 4px 10px rgba(15, 23, 42, 0.06)',
          bgcolor: statusMeta.bg,
          border: `1px solid ${statusMeta.border}`,
          transition: 'transform 0.3s, box-shadow 0.3s, cursor 0.3s',
          '&:hover': {
            transform: 'translateY(-4px)',
            boxShadow: '0 10px 18px rgba(15, 23, 42, 0.10)',
            cursor: 'pointer'
          }
        }}
        onClick={() => {
          if (onPanelSelect) {
            onPanelSelect(panel);
            return;
          }
          handleOpenDetails(panel);
        }}
      >
        <Box display="flex" justifyContent="space-between" alignItems="start" mb={2}>
          <Box>
            <Typography variant="h6" fontWeight="bold">
              {panel.name}
            </Typography>
            <Typography variant="caption" color="textSecondary">
              {panel.location}
            </Typography>
          </Box>
          {statusMeta.icon}
        </Box>

        <Box
          sx={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: 0.75,
            px: 1.25,
            py: 0.5,
            borderRadius: 999,
            bgcolor: '#ffffffcc',
            border: `1px solid ${statusMeta.border}`,
            mb: 1.75
          }}
        >
          <Box sx={{ width: 8, height: 8, borderRadius: '50%', bgcolor: statusMeta.color }} />
          <Typography variant="caption" fontWeight={800} sx={{ color: statusMeta.color }}>
            {statusMeta.label}
          </Typography>
        </Box>

        {/* Show Individual Panel AWS Sensor Data */}
        <Box sx={{ mb: 2, bgcolor: '#fff', p: 1.5, borderRadius: 1.5, border: '1px solid #e5e7eb' }}>
          <Box display="flex" justifyContent="space-between" mb={1.5}>
            <Typography variant="body2" fontWeight="500">⚡ Voltage</Typography>
            <Box>
              <Typography 
                variant="body2" 
                fontWeight="bold" 
                color="#2196f3"
                sx={{ fontSize: '1rem' }}
              >
                {sensorData.voltage.toFixed(4)}V
              </Typography>
              <Typography variant="caption" color="textSecondary" sx={{ display: 'block', textAlign: 'right' }}>
              </Typography>
            </Box>
          </Box>
          
          <Box display="flex" justifyContent="space-between" mb={1.5}>
            <Typography variant="body2" fontWeight="500">🔋 Power</Typography>
            <Box>
              <Typography 
                variant="body2" 
                fontWeight="bold" 
                color={statusMeta.color}
                sx={{ fontSize: '1rem' }}
              >
                {sensorData.power.toFixed(4)}W
              </Typography>
              <Typography variant="caption" color="textSecondary" sx={{ display: 'block', textAlign: 'right' }}>
              </Typography>
            </Box>
          </Box>
          
          <Box display="flex" justifyContent="space-between">
            <Typography variant="body2" fontWeight="500">⚙️ Current </Typography>
            <Box>
              <Typography 
                variant="body2" 
                fontWeight="bold" 
                color="#4caf50"
                sx={{ fontSize: '1rem' }}
              >
                {sensorData.current.toFixed(4)} A
              </Typography>
              <Typography variant="caption" color="textSecondary" sx={{ display: 'block', textAlign: 'right' }}>
              </Typography>
            </Box>
          </Box>
        </Box>

        <Button
          fullWidth
          variant="outlined"
          onClick={(e) => {
            e.stopPropagation();
            handleOpenDetails(panel);
          }}
          sx={{ mt: 1.5 }}
        >
          View Details
        </Button>

        {onHealthReportOpen && (
          <Button
            fullWidth
            variant="outlined"
            color="success"
            onClick={(e) => {
              e.stopPropagation();
              onHealthReportOpen(panel);
            }}
            sx={{ mt: 1.25 }}
          >
            Health Report
          </Button>
        )}

        <Button
          fullWidth
          variant="contained"
          startIcon={<Videocam />}
          onClick={(e) => {
            e.stopPropagation();
            handleOpenCamera(panel.id);
          }}
          sx={{ mt: 2 }}
        >
          View Camera
        </Button>
      </Paper>
    );
  });

  PanelCard.displayName = 'PanelCard';

  if (loading) {
    return (
      <Box display="flex" justifyContent="center" alignItems="center" minHeight="400px">
        <CircularProgress />
      </Box>
    );
  }

  return (
    <Box sx={{ p: 3 }}>
      {/* Solar Panels Grid */}
      <Box>
        <Typography variant="h5" gutterBottom fontWeight="bold" mb={3}>
          🌞 Solar Panels ({panels.length})
        </Typography>

        {error && (
          <Alert severity="warning" sx={{ mb: 2 }}>
            {error}
          </Alert>
        )}

        <Grid container spacing={2}>
          {panels.map((panel) => (
            <Grid item xs={12} sm={6} md={6} lg={6} key={panel.id}>
              <PanelCard panel={panel} panelData={panelData} />
            </Grid>
          ))}
        </Grid>
      </Box>

      {/* Panel Details Dialog */}
      <Dialog
        open={detailsOpen}
        onClose={handleCloseDetails}
        maxWidth="lg"
        fullWidth
        sx={{ '& .MuiDialog-paper': { borderRadius: 2 } }}
      >
        <DialogTitle sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <Typography variant="h6" fontWeight="bold">
            {selectedPanel?.name} - Detailed Analysis
          </Typography>
          <Button onClick={handleCloseDetails} sx={{ minWidth: 'auto' }}>
            <Close />
          </Button>
        </DialogTitle>

        <DialogContent sx={{ pt: 2 }}>
          {dataLoading ? (
            <Box display="flex" justifyContent="center" py={5}>
              <CircularProgress />
            </Box>
          ) : (
            <>
              {error ? (
                <Alert severity="error" sx={{ mb: 2 }}>
                  {error}
                </Alert>
              ) : null}

              <Tabs value={tabValue} onChange={(e, v) => setTabValue(v)} sx={{ mb: 2, borderBottom: '1px solid #e0e0e0' }}>
                <Tab label="IV Curve" />
                <Tab label="P-V Curve" />
                <Tab label="Sensor Data" />
              </Tabs>

              {/* IV Curve Tab */}
              {tabValue === 0 && (
                <Box sx={{ py: 2 }}>
                  <Typography variant="h6" gutterBottom fontWeight="bold">
                    Current vs Voltage Curve
                  </Typography>
                  <Typography variant="body2" color="textSecondary" sx={{ mb: 2 }}>
                    Current shown in ampere (A).
                  </Typography>
                  {generateIVCurveData().length > 0 ? (
                    <ResponsiveContainer width="100%" height={400}>
                      <LineChart data={generateIVCurveData()} margin={{ top: 5, right: 30, left: 0, bottom: 5 }}>
                        <defs>
                          <linearGradient id="colorCurrent" x1="0" y1="0" x2="0" y2="1">
                            <stop offset="5%" stopColor="#ff9800" stopOpacity={0.8} />
                            <stop offset="95%" stopColor="#ff9800" stopOpacity={0} />
                          </linearGradient>
                        </defs>
                        <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
                        <XAxis
                          dataKey="voltage"
                          label={{ value: 'Voltage (V)', position: 'insideBottomRight', offset: -5 }}
                          stroke="#666"
                        />
                        <YAxis
                          label={{ value: 'Current (A)', angle: -90, position: 'insideLeft' }}
                          stroke="#666"
                        />
                        <Tooltip
                          contentStyle={{ backgroundColor: '#fff', border: '1px solid #ccc', borderRadius: 8 }}
                          formatter={(value) => `${Number(value).toFixed(4)} A`}
                          labelFormatter={(label) => `Voltage: ${label}V`}
                        />
                        <Legend />
                        <Line
                          type="monotone"
                          dataKey="current"
                          stroke="#ff9800"
                          strokeWidth={3}
                          dot={{ fill: '#ff9800', r: 6 }}
                          activeDot={{ r: 8 }}
                          name="Current"
                        />
                      </LineChart>
                    </ResponsiveContainer>
                  ) : (
                    <Alert severity="info">No IV curve data available</Alert>
                  )}
                </Box>
              )}

              {/* Power Tab */}
              {tabValue === 1 && (
                <Box sx={{ py: 2 }}>
                  <Typography variant="h6" gutterBottom fontWeight="bold">
                    Power vs Voltage Curve
                  </Typography>
                  <Typography variant="body2" color="textSecondary" sx={{ mb: 2 }}>
                    Power calculated as P = V × I.
                  </Typography>
                  {generatePVCurveData().length > 0 ? (
                    <ResponsiveContainer width="100%" height={400}>
                      <LineChart data={generatePVCurveData()} margin={{ top: 10, right: 30, left: 0, bottom: 0 }}>
                        <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
                        <XAxis
                          dataKey="voltage"
                          type="number"
                          label={{ value: 'Voltage (V)', position: 'insideBottomRight', offset: -5 }}
                          stroke="#666"
                        />
                        <YAxis label={{ value: 'Power (W)', angle: -90, position: 'insideLeft' }} stroke="#666" />
                        <Tooltip
                          contentStyle={{ backgroundColor: '#fff', border: '1px solid #ccc', borderRadius: 8 }}
                          formatter={(value) => `${Number(value).toFixed(4)} W`}
                          labelFormatter={(label) => `Voltage: ${label}V`}
                        />
                        <Legend />
                        <Line type="monotone" dataKey="power" name="Power" stroke="#22c55e" strokeWidth={3} dot={{ r: 5 }} isAnimationActive={false} />
                      </LineChart>
                    </ResponsiveContainer>
                  ) : (
                    <Alert severity="info">No power data available</Alert>
                  )}
                </Box>
              )}

              {/* Sensor Data Tab */}
              {tabValue === 2 && (
                <Box sx={{ py: 2 }}>
                  <Typography variant="h6" gutterBottom fontWeight="bold">
                    Raw Sensor Data (Real-time from AWS)
                  </Typography>
                  {panelData ? (
                    <Grid container spacing={2}>
                      {Object.entries(panelData).map(([key, data]) => (
                        <Grid item xs={12} sm={6} key={key}>
                          <Paper sx={{ p: 2, bgcolor: '#f5f5f5' }}>
                            <Typography variant="subtitle2" fontWeight="bold">
                              {key}
                            </Typography>
                            <Typography variant="h6" color="primary" sx={{ my: 1 }}>
                              {data?.value !== null && data?.value !== undefined ? absNumber(data.value).toFixed(4) : 'N/A'}
                            </Typography>
                            <Typography variant="caption" color="textSecondary">
                              {data?.timestamp ? `Updated: ${new Date(Number(data.timestamp) * 1000).toLocaleString()}` : ''}
                            </Typography>
                          </Paper>
                        </Grid>
                      ))}
                    </Grid>
                  ) : (
                    <Alert severity="info">No sensor data available</Alert>
                  )}
                </Box>
              )}
            </>
          )}
        </DialogContent>

        <DialogActions sx={{ p: 2, borderTop: '1px solid #e0e0e0' }}>
          <Button onClick={handleCloseDetails} variant="outlined">
            Close
          </Button>
        </DialogActions>
      </Dialog>

      {selectedPanelId && (
        <CameraViewer
          open={cameraOpen}
          onClose={handleCloseCamera}
          panelId={selectedPanelId}
          cameraUrl={`/api/camera/latest-upload`}
        />
      )}
    </Box>
  );
}

export default SolarPanelGrid;
