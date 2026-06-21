import React, { useState, useEffect } from 'react';
import {
  Paper,
  Typography,
  Box,
  Grid,
  Card,
  CardContent,
  Chip,
  LinearProgress,
  Alert,
  List,
  ListItem,
  ListItemIcon,
  ListItemText,
} from '@mui/material';
import {
  Build,
  TrendingDown,
  TrendingUp,
  Warning,
  CheckCircle,
  Schedule,
} from '@mui/icons-material';
import axios from 'axios';
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from 'recharts';

const PredictiveMaintenance = ({ panelInfo }) => {
  const [maintenanceData, setMaintenanceData] = useState(null);

  useEffect(() => {
    fetchMaintenanceData();
    const interval = setInterval(fetchMaintenanceData, 30000);
    return () => clearInterval(interval);
  }, []);

  const fetchMaintenanceData = async () => {
    try {
      const response = await axios.get('/api/panel/predictive-maintenance');
      setMaintenanceData(response.data);
    } catch (error) {
      console.error('Error fetching maintenance data:', error);
    }
  };

  const getPriorityColor = (priority) => {
    const colors = {
      High: 'error',
      Medium: 'warning',
      Low: 'success',
    };
    return colors[priority] || 'default';
  };

  const getTrendIcon = (trend) => {
    if (trend === 'decreasing') return <TrendingDown color="error" />;
    if (trend === 'improving') return <TrendingUp color="success" />;
    return <CheckCircle color="info" />;
  };

  const predictionData = maintenanceData
    ? [
        {
          period: 'Current',
          efficiency: panelInfo?.health_score || 0,
        },
        {
          period: '30 Days',
          efficiency: maintenanceData.predicted_efficiency_30days,
        },
        {
          period: '90 Days',
          efficiency: maintenanceData.predicted_efficiency_90days,
        },
      ]
    : [];

  if (!maintenanceData) {
    return (
      <Paper sx={{ p: 3 }}>
        <Typography>Loading maintenance data...</Typography>
      </Paper>
    );
  }

  return (
    <Paper sx={{ p: 3 }}>
      <Box display="flex" alignItems="center" mb={3}>
        <Build sx={{ mr: 2, fontSize: 32, color: 'primary.main' }} />
        <Typography variant="h5" fontWeight="bold">
          Predictive Maintenance Dashboard
        </Typography>
      </Box>

      <Grid container spacing={3}>
        {/* Maintenance Priority Card */}
        <Grid item xs={12} md={4}>
          <Card sx={{ height: '100%', bgcolor: `${getPriorityColor(maintenanceData.maintenance_priority)}.light` }}>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                Maintenance Priority
              </Typography>
              <Chip
                label={maintenanceData.maintenance_priority}
                color={getPriorityColor(maintenanceData.maintenance_priority)}
                size="large"
                sx={{ mb: 2 }}
              />
              <Box display="flex" alignItems="center" mt={2}>
                <Schedule sx={{ mr: 1 }} />
                <Typography variant="body1">
                  Days until maintenance: <strong>{maintenanceData.days_until_maintenance}</strong>
                </Typography>
              </Box>
            </CardContent>
          </Card>
        </Grid>

        {/* Health Trend Card */}
        <Grid item xs={12} md={4}>
          <Card sx={{ height: '100%' }}>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                Health Trend
              </Typography>
              <Box display="flex" alignItems="center" justifyContent="space-between" mt={2}>
                <Box>
                  <Typography variant="h4" fontWeight="bold">
                    {maintenanceData.health_trend.charAt(0).toUpperCase() +
                      maintenanceData.health_trend.slice(1)}
                  </Typography>
                  <Typography variant="body2" color="textSecondary">
                    Performance trend
                  </Typography>
                </Box>
                <Box>{getTrendIcon(maintenanceData.health_trend)}</Box>
              </Box>
            </CardContent>
          </Card>
        </Grid>

        {/* Efficiency Prediction Card */}
        <Grid item xs={12} md={4}>
          <Card sx={{ height: '100%' }}>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                Predicted Efficiency
              </Typography>
              <Box mt={2}>
                <Typography variant="body2" color="textSecondary" gutterBottom>
                  30 Days: {maintenanceData.predicted_efficiency_30days}%
                </Typography>
                <LinearProgress
                  variant="determinate"
                  value={maintenanceData.predicted_efficiency_30days}
                  sx={{ mb: 2, height: 8, borderRadius: 4 }}
                />
                <Typography variant="body2" color="textSecondary" gutterBottom>
                  90 Days: {maintenanceData.predicted_efficiency_90days}%
                </Typography>
                <LinearProgress
                  variant="determinate"
                  value={maintenanceData.predicted_efficiency_90days}
                  sx={{ height: 8, borderRadius: 4 }}
                />
              </Box>
            </CardContent>
          </Card>
        </Grid>

        {/* Recommendations */}
        <Grid item xs={12} md={6}>
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                Recommendations
              </Typography>
              {maintenanceData.recommendations && maintenanceData.recommendations.length > 0 ? (
                <List>
                  {maintenanceData.recommendations.map((rec, index) => (
                    <ListItem key={index}>
                      <ListItemIcon>
                        <Warning color="warning" />
                      </ListItemIcon>
                      <ListItemText primary={rec} />
                    </ListItem>
                  ))}
                </List>
              ) : (
                <Alert severity="success" sx={{ mt: 2 }}>
                  No immediate maintenance actions required. Panel is operating within optimal parameters.
                </Alert>
              )}
            </CardContent>
          </Card>
        </Grid>

        {/* Efficiency Prediction Chart */}
        <Grid item xs={12} md={6}>
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                Efficiency Prediction
              </Typography>
              <ResponsiveContainer width="100%" height={250}>
                <LineChart data={predictionData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="period" />
                  <YAxis domain={[0, 100]} />
                  <Tooltip />
                  <Legend />
                  <Line
                    type="monotone"
                    dataKey="efficiency"
                    stroke="#1976d2"
                    strokeWidth={3}
                    name="Efficiency %"
                    dot={{ r: 6 }}
                  />
                </LineChart>
              </ResponsiveContainer>
            </CardContent>
          </Card>
        </Grid>
      </Grid>
    </Paper>
  );
};

export default PredictiveMaintenance;

