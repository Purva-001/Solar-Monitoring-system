import React from 'react';
import { Paper, Typography, Box, Grid, LinearProgress, Chip } from '@mui/material';
import { TrendingDown, TrendingUp, CheckCircle, Warning, Error } from '@mui/icons-material';

const PanelComparison = ({ panelInfo }) => {
  if (!panelInfo) {
    return (
      <Paper sx={{ p: 3, textAlign: 'center' }}>
        <Typography>Loading panel information...</Typography>
      </Paper>
    );
  }

  const currentEfficiency = (panelInfo.current_rating / panelInfo.installation_current_rating) * 100;
  const voltageEfficiency = (panelInfo.voltage_rating / panelInfo.installation_voltage_rating) * 100;
  const currentDegradation = panelInfo.installation_current_rating - panelInfo.current_rating;
  const voltageDegradation = panelInfo.installation_voltage_rating - panelInfo.voltage_rating;

  const getConditionIcon = (condition) => {
    switch (condition) {
      case 'Excellent':
        return <CheckCircle color="success" />;
      case 'Good':
        return <CheckCircle color="info" />;
      case 'Fair':
        return <Warning color="warning" />;
      case 'Poor':
        return <Error color="error" />;
      default:
        return <Warning color="warning" />;
    }
  };

  const getConditionColor = (condition) => {
    switch (condition) {
      case 'Excellent':
        return 'success';
      case 'Good':
        return 'info';
      case 'Fair':
        return 'warning';
      case 'Poor':
        return 'error';
      default:
        return 'default';
    }
  };

  const ComparisonItem = ({ label, installation, current, unit, efficiency }) => (
    <Box sx={{ mb: 3 }}>
      <Box display="flex" justifyContent="space-between" alignItems="center" mb={1}>
        <Typography variant="body1" fontWeight="medium">
          {label}
        </Typography>
        <Typography variant="body2" color="textSecondary">
          {efficiency.toFixed(1)}% Efficiency
        </Typography>
      </Box>
      <Grid container spacing={2} alignItems="center">
        <Grid item xs={12} sm={5}>
          <Box>
            <Typography variant="caption" color="textSecondary">
              Installation Rating
            </Typography>
            <Typography variant="h6" fontWeight="bold" color="primary">
              {installation} {unit}
            </Typography>
          </Box>
        </Grid>
        <Grid item xs={12} sm={2} sx={{ textAlign: 'center' }}>
          <Typography variant="h5">→</Typography>
        </Grid>
        <Grid item xs={12} sm={5}>
          <Box>
            <Typography variant="caption" color="textSecondary">
              Current Rating
            </Typography>
            <Typography variant="h6" fontWeight="bold" color={efficiency > 85 ? 'success.main' : efficiency > 70 ? 'warning.main' : 'error.main'}>
              {current} {unit}
            </Typography>
          </Box>
        </Grid>
      </Grid>
      <LinearProgress
        variant="determinate"
        value={efficiency}
        sx={{
          mt: 1,
          height: 8,
          borderRadius: 4,
          bgcolor: 'grey.200',
          '& .MuiLinearProgress-bar': {
            bgcolor: efficiency > 85 ? 'success.main' : efficiency > 70 ? 'warning.main' : 'error.main',
          },
        }}
      />
      <Box display="flex" justifyContent="space-between" mt={0.5}>
        <Typography variant="caption" color="textSecondary">
          Degradation: {label === 'Current' ? currentDegradation.toFixed(2) : voltageDegradation.toFixed(2)} {unit}
        </Typography>
        {efficiency < 90 && (
          <Typography variant="caption" color="warning.main" display="flex" alignItems="center">
            <TrendingDown sx={{ fontSize: 14, mr: 0.5 }} />
            Degraded
          </Typography>
        )}
      </Box>
    </Box>
  );

  return (
    <Paper sx={{ p: 3, height: '100%' }}>
      <Box display="flex" justifyContent="space-between" alignItems="center" mb={3}>
        <Typography variant="h5" fontWeight="bold">
          Panel Condition & Comparison
        </Typography>
        <Chip
          icon={getConditionIcon(panelInfo.condition)}
          label={panelInfo.condition}
          color={getConditionColor(panelInfo.condition)}
          size="medium"
        />
      </Box>

      <Box sx={{ mb: 3, p: 2, bgcolor: 'grey.50', borderRadius: 2 }}>
        <Typography variant="h6" gutterBottom>
          Health Score: {panelInfo.health_score}%
        </Typography>
        <LinearProgress
          variant="determinate"
          value={panelInfo.health_score}
          sx={{
            height: 10,
            borderRadius: 5,
            bgcolor: 'grey.300',
            '& .MuiLinearProgress-bar': {
              bgcolor: panelInfo.health_score > 85 ? 'success.main' : panelInfo.health_score > 70 ? 'warning.main' : 'error.main',
            },
          }}
        />
      </Box>

      <ComparisonItem
        label="Current"
        installation={panelInfo.installation_current_rating}
        current={panelInfo.current_rating}
        unit="A"
        efficiency={currentEfficiency}
      />

      <ComparisonItem
        label="Voltage"
        installation={panelInfo.installation_voltage_rating}
        current={panelInfo.voltage_rating}
        unit="V"
        efficiency={voltageEfficiency}
      />

      <Box sx={{ mt: 3, p: 2, bgcolor: 'info.light', borderRadius: 2 }}>
        <Typography variant="body2" color="info.dark">
          <strong>Active Defects:</strong> {panelInfo.defect_count}
        </Typography>
        {panelInfo.last_inspection && (
          <Typography variant="body2" color="info.dark" sx={{ mt: 1 }}>
            <strong>Last Inspection:</strong> {new Date(panelInfo.last_inspection).toLocaleString()}
          </Typography>
        )}
      </Box>
    </Paper>
  );
};

export default PanelComparison;

