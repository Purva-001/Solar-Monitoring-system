import React, { useState, useEffect } from 'react';
import {
  Container,
  Paper,
  Typography,
  Box,
  Grid,
  Card,
  CardContent,
  AppBar,
  Toolbar,
  IconButton,
  Chip,
  Divider,
} from '@mui/material';
import { ArrowBack, Visibility } from '@mui/icons-material';
import axios from 'axios';

const DigitalTwin = ({ onBack, panelInfo }) => {
  const [currentReading, setCurrentReading] = useState(null);
  const [defects, setDefects] = useState([]);

  useEffect(() => {
    fetchCurrentReading();
    fetchDefects();
    const interval = setInterval(() => {
      fetchCurrentReading();
    }, 5000);
    return () => clearInterval(interval);
  }, []);

  const fetchCurrentReading = async () => {
    try {
      const response = await axios.get('/api/panel/current-reading');
      setCurrentReading(response.data);
    } catch (error) {
      console.error('Error fetching reading:', error);
    }
  };

  const fetchDefects = async () => {
    try {
      const response = await axios.get('/api/panel/defects');
      setDefects(response.data.defects || []);
    } catch (error) {
      console.error('Error fetching defects:', error);
    }
  };

  const getDefectColor = (type) => {
    const colors = {
      microcrack: 'error',
      diode: 'error',
      hotspot: 'warning',
      dust: 'default',
      bird_drop: 'warning',
    };
    return colors[type] || 'default';
  };

  const getDefectLabel = (type) => {
    const labels = {
      microcrack: 'Microcrack',
      diode: 'Diode Failure',
      hotspot: 'Hotspot',
      dust: 'Dust',
      bird_drop: 'Bird Drop',
    };
    return labels[type] || type;
  };

  return (
    <Box sx={{ minHeight: '100vh', bgcolor: 'background.default' }}>
      <AppBar position="static">
        <Toolbar>
          <IconButton edge="start" color="inherit" onClick={onBack} sx={{ mr: 2 }}>
            <ArrowBack />
          </IconButton>
          <Visibility sx={{ mr: 2 }} />
          <Typography variant="h6" component="div" sx={{ flexGrow: 1 }}>
            Digital Twin - 3D Visualization
          </Typography>
        </Toolbar>
      </AppBar>

      <Container maxWidth="xl" sx={{ mt: 4, mb: 4 }}>
        <Grid container spacing={3}>
          {/* 3D Panel Visualization */}
          <Grid item xs={12} md={8}>
            <Paper sx={{ p: 3, minHeight: 500 }}>
              <Typography variant="h5" gutterBottom fontWeight="bold">
                Panel 3D Model
              </Typography>
              <Box
                sx={{
                  width: '100%',
                  height: 450,
                  bgcolor: 'grey.100',
                  borderRadius: 2,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  border: '2px dashed #ccc',
                  mt: 2,
                  position: 'relative',
                  background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
                }}
              >
                <Box sx={{ textAlign: 'center', color: 'white' }}>
                  <Typography variant="h4" gutterBottom>
                    🔆
                  </Typography>
                  <Typography variant="h6" gutterBottom>
                    Solar Panel Digital Twin
                  </Typography>
                  <Typography variant="body2" sx={{ opacity: 0.9 }}>
                    Interactive 3D visualization would be rendered here
                  </Typography>
                  <Typography variant="body2" sx={{ opacity: 0.8, mt: 2 }}>
                    Panel ID: {panelInfo?.panel_id || 'PL01-B02-INV03-STR05-P01'}
                  </Typography>
                </Box>

                {/* Overlay defect markers */}
                {defects.slice(-5).map((defect, idx) => {
                  if (!defect.defects || defect.defects.length === 0) return null;
                  const positions = [
                    { top: '20%', left: '30%' },
                    { top: '40%', left: '60%' },
                    { top: '60%', left: '25%' },
                    { top: '70%', left: '70%' },
                    { top: '50%', left: '50%' },
                  ];
                  const pos = positions[idx % positions.length];
                  return (
                    <Box
                      key={idx}
                      sx={{
                        position: 'absolute',
                        top: pos.top,
                        left: pos.left,
                        width: 20,
                        height: 20,
                        borderRadius: '50%',
                        bgcolor: 'error.main',
                        border: '2px solid white',
                        cursor: 'pointer',
                        '&:hover': {
                          transform: 'scale(1.5)',
                        },
                      }}
                    />
                  );
                })}
              </Box>
              <Typography variant="caption" color="textSecondary" sx={{ mt: 2, display: 'block' }}>
                Note: This is a placeholder. In production, integrate with Three.js or similar 3D library for interactive visualization
              </Typography>
            </Paper>
          </Grid>

          {/* Real-time Data Panel */}
          <Grid item xs={12} md={4}>
            <Paper sx={{ p: 3, mb: 3 }}>
              <Typography variant="h6" gutterBottom fontWeight="bold">
                Real-Time Status
              </Typography>
              <Divider sx={{ mb: 2 }} />
              
              {currentReading && (
                <Box>
                  <Box sx={{ mb: 2 }}>
                    <Typography variant="body2" color="textSecondary">
                      Current
                    </Typography>
                    <Typography variant="h5" fontWeight="bold" color="primary">
                      {currentReading.current} A
                    </Typography>
                  </Box>
                  <Box sx={{ mb: 2 }}>
                    <Typography variant="body2" color="textSecondary">
                      Voltage
                    </Typography>
                    <Typography variant="h5" fontWeight="bold" color="success.main">
                      {currentReading.voltage} V
                    </Typography>
                  </Box>
                  <Box>
                    <Typography variant="body2" color="textSecondary">
                      Temperature
                    </Typography>
                    <Typography variant="h5" fontWeight="bold" color="error.main">
                      {currentReading.temperature} °C
                    </Typography>
                  </Box>
                </Box>
              )}

              {panelInfo && (
                <Box sx={{ mt: 3, pt: 3, borderTop: '1px solid #e0e0e0' }}>
                  <Typography variant="body2" color="textSecondary" gutterBottom>
                    Health Score
                  </Typography>
                  <Typography variant="h4" fontWeight="bold">
                    {panelInfo.health_score}%
                  </Typography>
                  <Chip
                    label={panelInfo.condition}
                    color={panelInfo.condition === 'Excellent' ? 'success' : panelInfo.condition === 'Good' ? 'info' : 'warning'}
                    sx={{ mt: 1 }}
                  />
                </Box>
              )}
            </Paper>

            {/* Defects Panel */}
            <Paper sx={{ p: 3 }}>
              <Typography variant="h6" gutterBottom fontWeight="bold">
                Detected Defects
              </Typography>
              <Divider sx={{ mb: 2 }} />
              {defects.length > 0 ? (
                <Box>
                  {defects.slice(-5).map((defect, idx) => (
                    <Card key={idx} sx={{ mb: 2 }} variant="outlined">
                      <CardContent sx={{ p: 2, '&:last-child': { pb: 2 } }}>
                        <Typography variant="caption" color="textSecondary">
                          {new Date(defect.timestamp).toLocaleString()}
                        </Typography>
                        {defect.defects && defect.defects.length > 0 && (
                          <Box sx={{ mt: 1 }}>
                            {defect.defects.slice(0, 3).map((d, i) => (
                              <Chip
                                key={i}
                                label={getDefectLabel(d.type)}
                                color={getDefectColor(d.type)}
                                size="small"
                                sx={{ mr: 0.5, mb: 0.5 }}
                              />
                            ))}
                            {defect.defects.length > 3 && (
                              <Typography variant="caption" color="textSecondary">
                                +{defect.defects.length - 3} more
                              </Typography>
                            )}
                          </Box>
                        )}
                      </CardContent>
                    </Card>
                  ))}
                </Box>
              ) : (
                <Typography variant="body2" color="textSecondary">
                  No defects detected
                </Typography>
              )}
            </Paper>
          </Grid>

          {/* Panel Specifications */}
          <Grid item xs={12}>
            <Paper sx={{ p: 3 }}>
              <Typography variant="h6" gutterBottom fontWeight="bold">
                Panel Specifications
              </Typography>
              <Divider sx={{ mb: 2 }} />
              <Grid container spacing={3}>
                <Grid item xs={12} sm={6} md={3}>
                  <Typography variant="body2" color="textSecondary">
                    Panel ID
                  </Typography>
                  <Typography variant="h6">{panelInfo?.panel_id || 'PL01-B02-INV03-STR05-P01'}</Typography>
                </Grid>
                <Grid item xs={12} sm={6} md={3}>
                  <Typography variant="body2" color="textSecondary">
                    Installation Date
                  </Typography>
                  <Typography variant="h6">
                    {panelInfo?.installation_date || '2023-01-15'}
                  </Typography>
                </Grid>
                <Grid item xs={12} sm={6} md={3}>
                  <Typography variant="body2" color="textSecondary">
                    Installation Rating (Current)
                  </Typography>
                  <Typography variant="h6">
                    {panelInfo?.installation_current_rating || 8.5} A
                  </Typography>
                </Grid>
                <Grid item xs={12} sm={6} md={3}>
                  <Typography variant="body2" color="textSecondary">
                    Installation Rating (Voltage)
                  </Typography>
                  <Typography variant="h6">
                    {panelInfo?.installation_voltage_rating || 36.0} V
                  </Typography>
                </Grid>
              </Grid>
            </Paper>
          </Grid>
        </Grid>
      </Container>
    </Box>
  );
};

export default DigitalTwin;

