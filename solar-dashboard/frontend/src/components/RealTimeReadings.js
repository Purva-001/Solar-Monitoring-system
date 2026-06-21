import React, { useState, useEffect } from 'react';
import { Paper, Grid, Typography, Box } from '@mui/material';
import { Bolt, Speed, Thermostat } from '@mui/icons-material';
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer
} from 'recharts';
import axios from 'axios';
import { absNumber } from '../utils/numbers';
import { unwrapPanelReadingsPayload } from '../utils/solarReadings';

const RealTimeReadings = ({ reading }) => {
  const [history, setHistory] = useState({ current: [], voltage: [], temperature: [] });
  const [panelData, setPanelData] = useState({
    I1: { value: null, timestamp: null },
    I2: { value: null, timestamp: null },
    V1: { value: null, timestamp: null },
    V2: { value: null, timestamp: null },
    V3: { value: null, timestamp: null },
    P1: { value: null, timestamp: null },
    P2: { value: null, timestamp: null },
    P3: { value: null, timestamp: null },
  });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const ASSET_ID = 'cd29fe97-2d5e-47b4-a951-04c9e29544ac';

  // Dummy data for fallback
  const DUMMY_DATA = {
    I1: { value: 1, timestamp: Math.floor(Date.now() / 1000) },
    I2: { value: 2, timestamp: Math.floor(Date.now() / 1000) },
    V1: { value: 6.46, timestamp: Math.floor(Date.now() / 1000) },
    V2: { value: 7.07, timestamp: Math.floor(Date.now() / 1000) },
    V3: { value: 7.35, timestamp: Math.floor(Date.now() / 1000) },
    P1: { value: 1.84, timestamp: Math.floor(Date.now() / 1000) },
    P2: { value: 1.84, timestamp: Math.floor(Date.now() / 1000) },
    P3: { value: 2.72, timestamp: Math.floor(Date.now() / 1000) },
  };

  useEffect(() => {
    fetchHistory();
    fetchPanelData();
    const interval = setInterval(() => {
      fetchHistory();
      fetchPanelData();
    }, 30000); // 30 seconds
    return () => clearInterval(interval);
  }, []);

  const fetchHistory = async () => {
    try {
      const response = await axios.get('/api/panel/history?limit=50');
      setHistory(response.data);
    } catch (error) {
      console.error('Error fetching history:', error);
    }
  };

  const fetchPanelData = async () => {
    try {
      setLoading(true);
      console.log('📡 Fetching panel data from backend...');
      
      const apiUrl = '/api/panel/readings';
      
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 10000); // 10 second timeout
      
      const response = await fetch(apiUrl, {
        headers: {
          'Accept': 'application/json'
        },
        signal: controller.signal
      })
      
      clearTimeout(timeoutId);
      
      if (!response.ok) {
        throw new Error(`Readings request failed: ${response.status}`);
      }
      
      const raw = await response.json();
      console.log('✅ Backend response received:', raw);

      const data = unwrapPanelReadingsPayload(raw) ?? raw;

      if (data && typeof data === 'object' && !Array.isArray(data)) {
        const isNewShape =
          data.panel1voltage !== undefined ||
          data.panel1power !== undefined ||
          data.panel1current !== undefined;

        if (isNewShape) {
          const transformedData = {
            V1: { value: data.panel1voltage ?? 0, timestamp: Date.now() },
            V2: { value: data.panel2voltage ?? 0, timestamp: Date.now() },
            V3: { value: data.panel3voltage ?? 0, timestamp: Date.now() },
            P1: { value: data.panel1power ?? 0, timestamp: Date.now() },
            P2: { value: data.panel2power ?? 0, timestamp: Date.now() },
            P3: { value: data.panel3power ?? 0, timestamp: Date.now() },
            I1: { value: (data.panel1current ?? 0) * 1000, timestamp: Date.now() },
            I2: { value: (data.panel2current ?? 0) * 1000, timestamp: Date.now() },
            I3: { value: (data.panel3current ?? 0) * 1000, timestamp: Date.now() },
          };
          console.log('✅ Panel data updated (new shape):', transformedData);
          setPanelData(transformedData);
        } else {
          // Old shape: nested values like {V1:{value,timestamp}, P1:{...}, I:{...}}
          const transformedData = {};
          for (const key in data) {
            const v = data[key];
            transformedData[key] = {
              value: typeof v === 'object' && v !== null ? v.value : v,
              timestamp: typeof v === 'object' && v !== null ? v.timestamp : Date.now(),
            };
          }
          console.log('✅ Panel data updated (old shape):', transformedData);
          setPanelData(transformedData);
        }
        setError(null);
      }
    } catch (err) {
      console.error('❌ Error fetching from backend:', err.message);
      setError(`API Error: ${err.message}`);
    } finally {
      setLoading(false);
    }
  };

  // Calculate panel data based on new specifications
  const getPanelData = (panelNum) => {
    let v, i, p;
    
    switch(panelNum) {
      case 1:
        v = absNumber(panelData.V1?.value || 0);
        i = absNumber(panelData.I1?.value || panelData.I?.value || 0);
        p = absNumber(panelData.P1?.value || (v * (i / 1000))).toFixed(3);
        return { voltage: v?.toFixed(3), current: i?.toFixed(0), power: p };
      case 2:
        v = absNumber(panelData.V2?.value || 0);
        i = absNumber(panelData.I2?.value || panelData.I?.value || 0);
        p = absNumber(panelData.P2?.value || (v * (i / 1000))).toFixed(3);
        return { voltage: v?.toFixed(3), current: i?.toFixed(0), power: p };
      case 3:
        v = absNumber(panelData.V3?.value || 0);
        i = absNumber(panelData.I3?.value || panelData.I?.value || 0);
        p = absNumber(panelData.P3?.value || (v * (i / 1000))).toFixed(3);
        return { voltage: v?.toFixed(3), current: i?.toFixed(0), power: p };
      default:
        return { voltage: 'N/A', current: 'N/A', power: 'N/A' };
    }
  };

  const formatTime = (timestamp) => {
    if (!timestamp) return '';
    return new Date(timestamp).toLocaleTimeString();
  };

  const chartData = history.current?.map((item, index) => ({
    time: formatTime(item.timestamp),
    Current: absNumber(item.value),
    Voltage: absNumber(history.voltage?.[index]?.value || 0),
    Temperature: absNumber(history.temperature?.[index]?.value || 0),
  })) || [];

  const StatCard = ({ icon, title, value, unit, color }) => (
    <Paper
      sx={{
        p: 3,
        height: '100%',
        background: `linear-gradient(135deg, ${color}15 0%, ${color}05 100%)`,
        border: `2px solid ${color}30`,
      }}
    >
      <Box display="flex" alignItems="center" mb={2}>
        <Box
          sx={{
            bgcolor: color,
            color: 'white',
            borderRadius: '50%',
            p: 1.5,
            mr: 2,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          {icon}
        </Box>
        <Box>
          <Typography variant="body2" color="textSecondary">
            {title}
          </Typography>
          <Typography variant="h4" fontWeight="bold" color={color}>
            {value !== null && value !== undefined
              ? Number.isFinite(Number(value))
                ? `${absNumber(value)} ${unit}`
                : `${value} ${unit}`
              : '--'}
          </Typography>
        </Box>
      </Box>
    </Paper>
  );

  const totalCurrent = panelData.I1?.value || 0;
  const individualCurrent = panelData.I2?.value || 0;

  return (
    <Paper sx={{ p: 3 }}>
      <Box display="flex" justifyContent="space-between" alignItems="center" mb={2}>
        <Typography variant="h5" gutterBottom fontWeight="bold" mb={0}>
          Real-Time Readings
        </Typography>
        {error && (
          <Typography variant="caption" color="warning.main" sx={{ bgcolor: '#fff3cd', px: 2, py: 1, borderRadius: 1 }}>
            ⚠️ {error}
          </Typography>
        )}
      </Box>
      <Grid container spacing={3} sx={{ mt: 1 }}>
        <Grid item xs={12} sm={4}>
          <StatCard
            icon={<Bolt sx={{ fontSize: 32 }} />}
            title="Current I1"
            value={panelData.I1?.value != null ? absNumber(panelData.I1.value).toFixed(0) : 'N/A'}
            unit="mA"
            color="#1976d2"
          />
        </Grid>
        <Grid item xs={12} sm={4}>
          <StatCard
            icon={<Bolt sx={{ fontSize: 32 }} />}
            title="Current I2"
            value={panelData.I2?.value != null ? absNumber(panelData.I2.value).toFixed(0) : 'N/A'}
            unit="mA"
            color="#1976d2"
          />
        </Grid>
        <Grid item xs={12} sm={4}>
          <StatCard
            icon={<Thermostat sx={{ fontSize: 32 }} />}
            title="Temperature"
            value={reading?.temperature || 'N/A'}
            unit="°C"
            color="#d32f2f"
          />
        </Grid>

        {/* Solar Panels Data */}
        <Grid item xs={12}>
          <Typography variant="h6" gutterBottom>
            Solar Panels
          </Typography>
          <Grid container spacing={2}>
            {[1, 2, 3].map((panelNum) => {
              const data = getPanelData(panelNum);
              return (
                <Grid item xs={12} sm={6} md={4} key={`panel-${panelNum}`}>
                  <Paper sx={{ p: 2, background: 'linear-gradient(135deg, #ffc10715 0%, #ffc10705 100%)', border: '2px solid #ffc10730' }}>
                    <Typography variant="h6" fontWeight="bold" color="#ff9800" gutterBottom>
                      Panel {panelNum}
                    </Typography>
                    <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
                      <Box>
                        <Typography variant="caption" color="textSecondary">Voltage (V{panelNum}):</Typography>
                        <Typography variant="body1" fontWeight="bold" color="#2196f3">
                          {data.voltage} V
                        </Typography>
                      </Box>
                      <Box>
                        <Typography variant="caption" color="textSecondary">Current (I{panelNum <= 2 ? '1' : '2'}):</Typography>
                        <Typography variant="body1" fontWeight="bold" color="#1976d2">
                          {data.current} mA
                        </Typography>
                      </Box>
                      <Box>
                        <Typography variant="caption" color="textSecondary">Power (V × I):</Typography>
                        <Typography variant="body1" fontWeight="bold" color="#9c27b0">
                          {data.power} W
                        </Typography>
                      </Box>
                    </Box>
                  </Paper>
                </Grid>
              );
            })}
          </Grid>
        </Grid>

        <Grid item xs={12} sx={{ mt: 2 }}>
          <Typography variant="h6" gutterBottom>
            Historical Trends
          </Typography>
          {chartData.length > 0 ? (
            <ResponsiveContainer width="100%" height={300}>
              <LineChart data={chartData}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="time" />
                <YAxis yAxisId="left" />
                <YAxis yAxisId="right" orientation="right" />
                <Tooltip />
                <Legend />
                <Line
                  yAxisId="left"
                  type="monotone"
                  dataKey="Current"
                  stroke="#1976d2"
                  strokeWidth={2}
                  dot={false}
                />
                <Line
                  yAxisId="left"
                  type="monotone"
                  dataKey="Voltage"
                  stroke="#2e7d32"
                  strokeWidth={2}
                  dot={false}
                />
                <Line
                  yAxisId="right"
                  type="monotone"
                  dataKey="Temperature"
                  stroke="#d32f2f"
                  strokeWidth={2}
                  dot={false}
                />
              </LineChart>
            </ResponsiveContainer>
          ) : (
            <Typography color="textSecondary">No historical data available</Typography>
          )}
        </Grid>
      </Grid>
    </Paper>
  );
};

export default RealTimeReadings;