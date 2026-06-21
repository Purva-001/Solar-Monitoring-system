import React, { useState } from 'react';
import {
  Paper,
  Typography,
  Box,
  Button,
  Grid,
  Card,
  CardContent,
  CardMedia,
  Chip,
  Alert,
  CircularProgress,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions
} from '@mui/material';
import { CloudUpload, Image as ImageIcon, Close } from '@mui/icons-material';
import axios from 'axios';

const DefectDetection = ({ onDetectionComplete }) => {
  const [selectedFile, setSelectedFile] = useState(null);
  const [preview, setPreview] = useState(null);
  const [detecting, setDetecting] = useState(false);
  const [detectionResult, setDetectionResult] = useState(null);
  const [error, setError] = useState(null);
  const [dialogOpen, setDialogOpen] = useState(false);

  const handleFileSelect = (event) => {
    const file = event.target.files[0];
    if (file) {
      setSelectedFile(file);
      setError(null);
      setDetectionResult(null);
      
      // Create preview
      const reader = new FileReader();
      reader.onloadend = () => {
        setPreview(reader.result);
      };
      reader.readAsDataURL(file);
    }
  };

  const handleDetect = async () => {
    if (!selectedFile) {
      setError('Please select an image first');
      return;
    }

    setDetecting(true);
    setError(null);

    const formData = new FormData();
    formData.append('image', selectedFile);

    try {
      const response = await axios.post('/api/panel/defect-detect', formData, {
        headers: {
          'Content-Type': 'multipart/form-data',
        },
      });

      setDetectionResult(response.data);
      setDialogOpen(true);
      if (onDetectionComplete) {
        onDetectionComplete();
      }
    } catch (err) {
      setError(err.response?.data?.error || 'Failed to detect defects');
      console.error('Detection error:', err);
    } finally {
      setDetecting(false);
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

  const getSeverityColor = (severity) => {
    const colors = {
      high: 'error',
      medium: 'warning',
      low: 'info',
    };
    return colors[severity] || 'default';
  };

  return (
    <Paper sx={{ p: 3, height: '100%' }}>
      <Typography variant="h5" gutterBottom fontWeight="bold">
        AI Defect Detection
      </Typography>
      <Typography variant="body2" color="textSecondary" sx={{ mb: 3 }}>
        Upload an image of your solar panel to detect defects like microcracks, diode failures, hotspots, dust, and bird droppings
      </Typography>

      <Box sx={{ mb: 3 }}>
        <input
          accept="image/*"
          style={{ display: 'none' }}
          id="upload-image"
          type="file"
          onChange={handleFileSelect}
        />
        <label htmlFor="upload-image">
          <Button
            variant="outlined"
            component="span"
            startIcon={<CloudUpload />}
            fullWidth
            sx={{ mb: 2, py: 1.5 }}
          >
            Select Panel Image
          </Button>
        </label>

        {preview && (
          <Box sx={{ mb: 2, position: 'relative' }}>
            <Box
              component="img"
              src={preview}
              alt="Preview"
              sx={{
                width: '100%',
                maxHeight: 300,
                objectFit: 'contain',
                borderRadius: 2,
                border: '2px solid #e0e0e0',
              }}
            />
            <Button
              size="small"
              onClick={() => {
                setPreview(null);
                setSelectedFile(null);
                setDetectionResult(null);
              }}
              sx={{ position: 'absolute', top: 8, right: 8 }}
              color="error"
            >
              <Close />
            </Button>
          </Box>
        )}

        <Button
          variant="contained"
          color="primary"
          fullWidth
          onClick={handleDetect}
          disabled={!selectedFile || detecting}
          startIcon={detecting ? <CircularProgress size={20} /> : <ImageIcon />}
          sx={{ py: 1.5 }}
        >
          {detecting ? 'Detecting Defects...' : 'Analyze Panel'}
        </Button>
      </Box>

      {error && (
        <Alert severity="error" sx={{ mb: 2 }}>
          {error}
        </Alert>
      )}

      {detectionResult && detectionResult.defects && detectionResult.defects.length > 0 && (
        <Box>
          <Typography variant="h6" gutterBottom>
            Detected Defects: {detectionResult.defects.length}
          </Typography>
          <Grid container spacing={2}>
            {detectionResult.defects.map((defect, index) => (
              <Grid item xs={12} sm={6} key={index}>
                <Card>
                  <CardContent>
                    <Box display="flex" justifyContent="space-between" alignItems="center" mb={1}>
                      <Chip
                        label={getDefectLabel(defect.type)}
                        color={getDefectColor(defect.type)}
                        size="small"
                      />
                      <Chip
                        label={defect.severity}
                        color={getSeverityColor(defect.severity)}
                        size="small"
                      />
                    </Box>
                    <Typography variant="body2" color="textSecondary">
                      Confidence: {(defect.confidence * 100).toFixed(1)}%
                    </Typography>
                  </CardContent>
                </Card>
              </Grid>
            ))}
          </Grid>
        </Box>
      )}

      {detectionResult && detectionResult.defects && detectionResult.defects.length === 0 && (
        <Alert severity="success" sx={{ mt: 2 }}>
          No defects detected! Panel appears to be in good condition.
        </Alert>
      )}

      <Dialog open={dialogOpen} onClose={() => setDialogOpen(false)} maxWidth="md" fullWidth>
        <DialogTitle>Defect Detection Results</DialogTitle>
        <DialogContent sx={{ maxHeight: '70vh', overflowY: 'auto' }}>
          {detectionResult && detectionResult.image && (
            <Box sx={{ mb: 3 }}>
              <img
                src={detectionResult.image}
                alt="Analyzed Panel"
                style={{
                  width: '100%',
                  borderRadius: 8,
                  border: '2px solid #e0e0e0',
                }}
              />
            </Box>
          )}
          
          {detectionResult && detectionResult.gemini_analysis && (
            <Box sx={{ mb: 3, p: 2, bgcolor: '#f5f5f5', borderRadius: 2 }}>
              <Typography variant="h6" gutterBottom sx={{ fontWeight: 'bold' }}>
                🔍 AI Analysis Summary (Powered by Gemini)
              </Typography>
              <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', sm: '1fr 1fr' }, gap: 2, mb: 2 }}>
                {detectionResult.gemini_analysis.overall_condition && (
                  <Box>
                    <Typography variant="body2" color="textSecondary">Overall Condition:</Typography>
                    <Typography variant="body1" sx={{ fontWeight: 'bold' }}>
                      {detectionResult.gemini_analysis.overall_condition}
                    </Typography>
                  </Box>
                )}
                {detectionResult.gemini_analysis.confidence && (
                  <Box>
                    <Typography variant="body2" color="textSecondary">Analysis Confidence:</Typography>
                    <Typography variant="body1" sx={{ fontWeight: 'bold', color: '#4caf50' }}>
                      {detectionResult.gemini_analysis.confidence}%
                    </Typography>
                  </Box>
                )}
              </Box>
            </Box>
          )}
          
          {detectionResult && detectionResult.defects && detectionResult.defects.length > 0 && (
            <Box>
              <Typography variant="h6" gutterBottom>
                Detected Defects ({detectionResult.defects.length}):
              </Typography>
              <Grid container spacing={2}>
                {detectionResult.defects.map((defect, index) => (
                  <Grid item xs={12} key={index}>
                    <Card variant="outlined">
                      <CardContent>
                        <Box display="flex" justifyContent="space-between" alignItems="center" flexWrap="wrap" gap={1}>
                          <Chip
                            label={getDefectLabel(defect.type)}
                            color={getDefectColor(defect.type)}
                          />
                          <Chip
                            label={`Severity: ${defect.severity}`}
                            color={getSeverityColor(defect.severity)}
                            size="small"
                          />
                          <Typography variant="body2">
                            Confidence: {(defect.confidence * 100).toFixed(1)}%
                          </Typography>
                        </Box>
                      </CardContent>
                    </Card>
                  </Grid>
                ))}
              </Grid>
            </Box>
          )}
          {detectionResult && detectionResult.defects && detectionResult.defects.length === 0 && (
            <Alert severity="success">
              No defects detected! The panel appears to be in excellent condition.
            </Alert>
          )}
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setDialogOpen(false)}>Close</Button>
        </DialogActions>
      </Dialog>
    </Paper>
  );
};

export default DefectDetection;

