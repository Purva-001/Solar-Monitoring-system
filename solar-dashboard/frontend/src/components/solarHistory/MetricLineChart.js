import React from 'react';
import { Paper, Typography, Box } from '@mui/material';
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
import { absNumber } from '../../utils/numbers';

const palette = ['#2563eb', '#22c55e', '#f59e0b', '#ef4444', '#6366f1', '#14b8a6'];

const MetricLineChart = ({ title, subtitle, data, lines, yUnit, yDecimals = 2 }) => {
  const hasTimeSeries = Array.isArray(data) && data.some((d) => Number.isFinite(Number(d?.tsMs)));
  const formatTimeTick = (v) => {
    const n = Number(v);
    if (!Number.isFinite(n)) return String(v ?? '');
    try {
      return new Date(n).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
    } catch {
      return String(v ?? '');
    }
  };

  return (
    <Paper elevation={0} sx={{ p: 2.5, borderRadius: 2, border: '1px solid #eaeaea', height: '100%' }}>
      <Box sx={{ mb: 1.5 }}>
        <Typography fontWeight={900}>{title}</Typography>
        {subtitle ? (
          <Typography variant="caption" color="text.secondary">
            {subtitle}
          </Typography>
        ) : null}
      </Box>

      <Box sx={{ height: 320 }}>
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={data} margin={{ top: 10, right: 20, left: 0, bottom: 0 }}>
            <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
            <XAxis
              dataKey={hasTimeSeries ? 'tsMs' : 'timeLabel'}
              type={hasTimeSeries ? 'number' : 'category'}
              scale={hasTimeSeries ? 'time' : undefined}
              domain={hasTimeSeries ? ['dataMin', 'dataMax'] : undefined}
              tickFormatter={hasTimeSeries ? formatTimeTick : undefined}
              stroke="#666"
              minTickGap={32}
              interval="preserveStartEnd"
            />
            <YAxis
              stroke="#666"
              tickFormatter={(v) => `${absNumber(v).toFixed(yDecimals)}${yUnit ? ` ${yUnit}` : ''}`}
            />
            <Tooltip
              formatter={(v, name) => [`${absNumber(v).toFixed(yDecimals)}${yUnit ? ` ${yUnit}` : ''}`, name]}
              labelFormatter={(label, payload) => {
                const ts = payload?.[0]?.payload?.dateTimeLabel;
                return ts || label;
              }}
            />
            <Legend />
            {lines.map((ln, idx) => (
              <Line
                key={ln.dataKey}
                type="monotone"
                dataKey={ln.dataKey}
                name={ln.name || ln.dataKey}
                stroke={ln.color || palette[idx % palette.length]}
                strokeWidth={3}
                dot={false}
                isAnimationActive={false}
              />
            ))}
          </LineChart>
        </ResponsiveContainer>
      </Box>
    </Paper>
  );
};

export default MetricLineChart;
