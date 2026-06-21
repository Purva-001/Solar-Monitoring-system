import React, { useState } from 'react';
import {
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Button,
  Box,
  Paper,
  Typography,
  Card,
  CardContent,
  Chip,
  LinearProgress,
  Divider,
  Alert,
  Table,
  TableBody,
  TableCell,
  TableRow,
  Grid
} from '@mui/material';
import {
  Close,
  CheckCircle,
  Warning,
  Error as ErrorIcon,
  Info,
  TrendingDown,
  Build
} from '@mui/icons-material';

const AnalysisHealthReport = ({ open, onClose, panelId, analysisResult }) => {
  if (!analysisResult) return null;

  const ml = analysisResult.ml_result;
  const confidence = (ml.confidence * 100).toFixed(2);

  // Determine health score based on defect type and confidence
  const getHealthScore = () => {
    const defect = ml.fault_type.toLowerCase();
    
    if (defect === 'clean') {
      return Math.round(100 - (ml.confidence * 10));
    }
    
    // Deduct health based on defect severity
    let baseDeduction = 0;
    if (defect === 'dusty' || defect === 'snow-covered') {
      baseDeduction = 40; // Moderate issue
    } else if (defect === 'bird-drop') {
      baseDeduction = 50; // Significant issue
    } else if (defect === 'electrical-damage' || defect === 'physical-damage') {
      baseDeduction = 70; // Severe issue
    }
    
    return Math.max(0, 100 - baseDeduction - (ml.confidence * 20));
  };

  // Determine urgency based on defect
  const getUrgency = () => {
    const defect = ml.fault_type.toLowerCase();
    
    if (defect === 'clean') return { level: 'Low', color: '#4caf50', icon: CheckCircle };
    if (defect === 'dusty' || defect === 'snow-covered') return { level: 'Medium', color: '#ff9800', icon: Warning };
    if (defect === 'electrical-damage' || defect === 'physical-damage') return { level: 'High', color: '#f44336', icon: ErrorIcon };
    
    return { level: 'Medium', color: '#ff9800', icon: Warning };
  };

  const healthScore = getHealthScore();
  const urgency = getUrgency();
  const UrgencyIcon = urgency.icon;

  const getHealthColor = (score) => {
    if (score >= 80) return '#4caf50';
    if (score >= 60) return '#8bc34a';
    if (score >= 40) return '#ff9800';
    return '#f44336';
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="md" fullWidth>
      <DialogTitle sx={{ fontWeight: 'bold', fontSize: '1.3rem', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        Health Report - {panelId}
        <Button onClick={onClose} size="small" color="inherit">
          <Close />
        </Button>
      </DialogTitle>

      <DialogContent>
        <Box sx={{ pt: 2 }}>
          {/* Overall Health Score */}
          <Paper sx={{ p: 3, mb: 3, background: `linear-gradient(135deg, ${getHealthColor(healthScore)}20 0%, ${getHealthColor(healthScore)}05 100%)`, border: `3px solid ${getHealthColor(healthScore)}` }}>
            <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 2 }}>
              <Box>
                <Typography variant="h6" sx={{ fontWeight: 'bold', mb: 1 }}>
                  Panel Health Score
                </Typography>
                <Typography variant="body2" color="textSecondary">
                  Based on AI analysis and defect detection
                </Typography>
              </Box>
              <Box sx={{ textAlign: 'center' }}>
                <Typography variant="h3" sx={{ fontWeight: 'bold', color: getHealthColor(healthScore) }}>
                  {healthScore.toFixed(0)}%
                </Typography>
              </Box>
            </Box>
            <LinearProgress
              variant="determinate"
              value={healthScore}
              sx={{
                height: 12,
                borderRadius: 6,
                backgroundColor: '#e0e0e0',
                '& .MuiLinearProgress-bar': {
                  backgroundColor: getHealthColor(healthScore)
                }
              }}
            />
          </Paper>

          {/* Urgency Level */}
          <Paper sx={{ p: 2, mb: 3, backgroundColor: `${urgency.color}15`, border: `2px solid ${urgency.color}` }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
              <UrgencyIcon sx={{ color: urgency.color, fontSize: 32 }} />
              <Box>
                <Typography variant="subtitle2" sx={{ fontWeight: 'bold' }}>
                  Maintenance Urgency
                </Typography>
                <Chip
                  label={urgency.level}
                  sx={{
                    backgroundColor: urgency.color,
                    color: 'white',
                    fontWeight: 'bold',
                    mt: 0.5
                  }}
                />
              </Box>
            </Box>
          </Paper>

          {/* ML Detection Results */}
          <Card sx={{ mb: 3 }}>
            <CardContent>
              <Typography variant="h6" sx={{ fontWeight: 'bold', mb: 2 }}>
                Defect Detection Results
              </Typography>

              <Table size="small">
                <TableBody>
                  <TableRow>
                    <TableCell sx={{ fontWeight: 'bold', width: '40%' }}>Detected Defect</TableCell>
                    <TableCell>
                      <Chip
                        label={ml.fault_type}
                        color="primary"
                        variant="outlined"
                      />
                    </TableCell>
                  </TableRow>
                  <TableRow>
                    <TableCell sx={{ fontWeight: 'bold' }}>Confidence</TableCell>
                    <TableCell>
                      <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                        <Box sx={{ flex: 1 }}>
                          <LinearProgress
                            variant="determinate"
                            value={parseFloat(confidence)}
                            sx={{ height: 8, borderRadius: 4 }}
                          />
                        </Box>
                        <Typography variant="body2" sx={{ fontWeight: 'bold', minWidth: 60 }}>
                          {confidence}%
                        </Typography>
                      </Box>
                    </TableCell>
                  </TableRow>
                </TableBody>
              </Table>

              {/* Top Predictions */}
              <Typography variant="subtitle2" sx={{ fontWeight: 'bold', mt: 3, mb: 1 }}>
                Alternative Predictions
              </Typography>
              <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
                {ml.top_predictions.slice(1).map((pred, idx) => (
                  <Box key={idx} sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                    <Typography variant="body2" sx={{ minWidth: 100 }}>
                      {pred.label}
                    </Typography>
                    <Box sx={{ flex: 1 }}>
                      <LinearProgress
                        variant="determinate"
                        value={pred.score * 100}
                        sx={{ height: 6 }}
                      />
                    </Box>
                    <Typography variant="caption">
                      {(pred.score * 100).toFixed(1)}%
                    </Typography>
                  </Box>
                ))}
              </Box>
            </CardContent>
          </Card>

          {/* AI Expert Analysis */}
          <Card sx={{ mb: 3, backgroundColor: '#f5f5f5' }}>
            <CardContent>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 2 }}>
                <Info sx={{ color: '#1976d2' }} />
                <Typography variant="h6" sx={{ fontWeight: 'bold' }}>
                  AI Expert Analysis
                </Typography>
              </Box>
              <Divider sx={{ mb: 2 }} />
              <Typography
                variant="body2"
                sx={{
                  whiteSpace: 'pre-wrap',
                  lineHeight: 1.8,
                  color: '#333'
                }}
              >
                {analysisResult.gemini_analysis}
              </Typography>
            </CardContent>
          </Card>

          {/* Recommended Actions */}
          <Card sx={{ mb: 3 }}>
            <CardContent>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 2 }}>
                <Build sx={{ color: '#ff9800' }} />
                <Typography variant="h6" sx={{ fontWeight: 'bold' }}>
                  Recommended Actions
                </Typography>
              </Box>
              <Divider sx={{ mb: 2 }} />

              {ml.fault_type.toLowerCase() === 'clean' && (
                <Alert severity="success" sx={{ mb: 1 }}>
                  ✓ Panel is clean and operating normally. Continue regular monitoring.
                </Alert>
              )}

              {ml.fault_type.toLowerCase() === 'dusty' && (
                <Alert severity="warning" sx={{ mb: 1 }}>
                  🧹 Panel requires cleaning. Dust reduces efficiency by 10-25%. Schedule cleaning immediately.
                </Alert>
              )}

              {ml.fault_type.toLowerCase() === 'bird-drop' && (
                <Alert severity="warning" sx={{ mb: 1 }}>
                  🐦 Bird droppings detected. Clean panel to restore efficiency. Consider anti-bird measures.
                </Alert>
              )}

              {ml.fault_type.toLowerCase() === 'snow-covered' && (
                <Alert severity="warning" sx={{ mb: 1 }}>
                  ❄️ Panel covered with snow/ice. Efficiency significantly reduced. Clear snow when safe.
                </Alert>
              )}

              {(ml.fault_type.toLowerCase() === 'electrical-damage' || ml.fault_type.toLowerCase() === 'physical-damage') && (
                <Alert severity="error" sx={{ mb: 1 }}>
                  ⚠️ Physical or electrical damage detected. Contact technician immediately for inspection and repair.
                </Alert>
              )}
            </CardContent>
          </Card>

          {/* Timestamp */}
          <Typography variant="caption" color="textSecondary" sx={{ display: 'block', textAlign: 'center', mt: 2 }}>
            Analysis performed on {new Date(analysisResult.timestamp).toLocaleString()}
          </Typography>
        </Box>
      </DialogContent>

      <DialogActions sx={{ p: 2 }}>
        <Button onClick={onClose} variant="contained" color="primary">
          Close Report
        </Button>
      </DialogActions>
    </Dialog>
  );
};

export default AnalysisHealthReport;
