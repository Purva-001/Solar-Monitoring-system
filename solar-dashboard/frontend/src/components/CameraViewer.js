import React, { useState, useEffect } from 'react';
import {
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Button,
  Box,
  IconButton,
  CircularProgress,
  Typography,
  Alert,
  Card,
  CardContent,
  Divider,
  Chip,
  LinearProgress
} from '@mui/material';
import { Close, Download, CloudUpload } from '@mui/icons-material';

const CameraViewer = ({ open, onClose, panelId, cameraUrl = 'http://10.132.204.94:3001/uploads/latest.jpg', onAnalysisComplete = null }) => {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [analyzing, setAnalyzing] = useState(false);
  const [analysisResult, setAnalysisResult] = useState(null);
  const [imageTimestamp, setImageTimestamp] = useState(new Date().getTime());

  // Auto-refresh camera feed every 500ms for live streaming
  useEffect(() => {
    if (!open || analysisResult !== null) {
      return; // Don't refresh if modal is closed or showing analysis results
    }

    const refreshInterval = setInterval(() => {
      setImageTimestamp(new Date().getTime());
    }, 500); // Refresh every 500ms for ~2 FPS live feed

    return () => clearInterval(refreshInterval);
  }, [open, analysisResult]);

  // Logger utility function
  const logger = (level, ...args) => {
    const timestamp = new Date().toISOString();
    const prefix = `[${timestamp}] [CameraViewer] [${level.toUpperCase()}]`;
    
    const colors = {
      info: 'color: #0066cc; font-weight: bold;',
      success: 'color: #00aa00; font-weight: bold;',
      error: 'color: #cc0000; font-weight: bold;',
      warning: 'color: #ff9900; font-weight: bold;'
    };
    
    const style = colors[level] || colors.info;
    console.log(`%c${prefix}`, style, ...args);
  };

  // Log state changes for debugging
  

  const handleRefresh = () => {
    setLoading(true);
    // Only update timestamp when user explicitly clicks refresh
    setImageTimestamp(new Date().getTime());
    setLoading(false);
  };

  const handleImageLoad = () => {
    setLoading(false);
    setError(null);
  };

  const handleImageError = () => {
    setLoading(false);
    setError('Failed to load camera feed. Make sure the ESP32 camera is online at ' + cameraUrl);
  };

  const handleCaptureImage = () => {
    const imgElement = document.getElementById(`camera-image-${panelId}`);
    if (imgElement && imgElement.src) {
      // Create a canvas to draw the image
      const canvas = document.createElement('canvas');
      canvas.width = imgElement.width;
      canvas.height = imgElement.height;
      const ctx = canvas.getContext('2d');
      ctx.drawImage(imgElement, 0, 0);
      
      // Convert to blob and download
      canvas.toBlob((blob) => {
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `${panelId}_${new Date().toISOString().slice(0, 19).replace(/:/g, '-')}.jpg`;
        document.body.appendChild(a);
        a.click();
        window.URL.revokeObjectURL(url);
        document.body.removeChild(a);
      }, 'image/jpeg', 0.95);
    }
  };

  const handleAnalyzeImage = async () => {
    setAnalyzing(true);
    setError(null);
    setAnalysisResult(null);

    try {
      const imgElement = document.getElementById(`camera-image-${panelId}`);
      if (!imgElement || !imgElement.src) {
        setError('No image to analyze');
        setAnalyzing(false);
        return;
      }

      logger('info', `Starting image analysis for panel ${panelId}`);

      // Convert image to blob
      const response = await fetch(imgElement.src);
      const blob = await response.blob();
      logger('info', `Image blob size: ${blob.size} bytes`);

      // Create FormData with image
      const formData = new FormData();
      formData.append('file', blob, `${panelId}.jpg`);

      // Get backend URL from environment or use default
      const backendUrl = process.env.REACT_APP_BACKEND_URL || 'http://localhost:8000';
      const analyzeUrl = `${backendUrl}/analyze`;
      
      logger('info', `Sending to ${analyzeUrl}`);
      const analysisResponse = await fetch(analyzeUrl, {
        method: 'POST',
        body: formData,
        headers: {
          'Accept': 'application/json'
        }
      });

      logger('info', `Response status: ${analysisResponse.status}`);
      const result = await analysisResponse.json();

      if (!analysisResponse.ok) {
        const errorMsg = result.detail || result.error || 'Analysis failed';
        logger('error', `API Error: ${errorMsg}`);
        setError(errorMsg);
      } else {
        logger('success', `Analysis complete! Detected: ${result.fault}`);
        logger('info', `Confidence: ${(result.confidence * 100).toFixed(2)}%`);
        logger('info', `Full result object:`, result);
        logger('info', `Setting analysis result state...`);
        
        // Force state update with a new object reference
        const resultData = {
          fault: result.fault,
          confidence: result.confidence,
          rag_context: result.rag_context,
          gemini_suggestion: result.gemini_suggestion
        };
        
        setAnalysisResult({ ...resultData });
        logger('info', `State set! Result:`, resultData);
        
        // Call the callback if provided to show health report
        if (onAnalysisComplete) {
          onAnalysisComplete(resultData);
        }
      }
    } catch (err) {
      const errorMsg = `Error analyzing image: ${err.message}`;
      logger('error', errorMsg);
      setError(errorMsg);
    } finally {
      setAnalyzing(false);
    }
  };

  const renderMarkdown = (text) => {
    if (!text) return '';
    
    const lines = String(text).split('\n');
    const elements = [];
    let currentList = [];
    let listKey = 0;
    
    const flushList = () => {
      if (currentList.length > 0) {
        elements.push(
          <Box
            key={`list-${listKey++}`}
            component="ul"
            sx={{
              ml: 2.5,
              mb: 2,
              pl: 1,
              '& li': {
                mb: 1,
                color: '#333',
                fontSize: '0.9rem',
                lineHeight: 1.6
              }
            }}
          >
            {currentList.map((item, i) => (
              <li key={i}>{item.replace(/\*\*/g, '').replace(/\*/g, '')}</li>
            ))}
          </Box>
        );
        currentList = [];
      }
    };
    
    lines.forEach((line, idx) => {
      const trimmed = line.trim();
      
      // Skip empty lines and table separators
      if (!trimmed || trimmed === '|' || /^[|-]+$/.test(trimmed) || trimmed.startsWith('|-|')) {
        return;
      }
      
      // Headers (##)
      if (trimmed.startsWith('## ')) {
        flushList();
        const headerText = trimmed.replace(/^#+\s/, '').replace(/\*\*/g, '').replace(/\*/g, '');
        elements.push(
          <Typography
            key={`h-${idx}`}
            variant="h6"
            sx={{
              fontWeight: 'bold',
              mt: 2.5,
              mb: 1.5,
              color: '#1565c0',
              fontSize: '1rem',
              letterSpacing: '0.3px'
            }}
          >
            {headerText}
          </Typography>
        );
      }
      // Subheaders (###)
      else if (trimmed.startsWith('### ')) {
        flushList();
        const headerText = trimmed.replace(/^#+\s/, '').replace(/\*\*/g, '').replace(/\*/g, '');
        elements.push(
          <Typography
            key={`h3-${idx}`}
            variant="body1"
            sx={{
              fontWeight: '600',
              mt: 1.5,
              mb: 1,
              color: '#0d47a1',
              fontSize: '0.95rem'
            }}
          >
            {headerText}
          </Typography>
        );
      }
      // Bullet points
      else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        const bulletText = trimmed.replace(/^[-*]\s/, '').replace(/\*\*/g, '').replace(/\*/g, '');
        currentList.push(bulletText);
      }
      // Skip table headers and markdown pipes
      else if (trimmed.startsWith('|')) {
        return;
      }
      // Regular paragraphs
      else if (trimmed.length > 0) {
        flushList();
        const cleanText = trimmed
          .replace(/\*\*/g, '')
          .replace(/\*/g, '')
          .replace(/\|/g, ' ')
          .replace(/`/g, '');
        
        elements.push(
          <Typography
            key={`p-${idx}`}
            variant="body2"
            sx={{
              mb: 1.5,
              color: '#444',
              lineHeight: 1.7,
              fontSize: '0.9rem'
            }}
          >
            {cleanText}
          </Typography>
        );
      }
    });
    
    // Flush any remaining list
    flushList();
    
    return elements;
  };

  return (
    <Dialog 
      key={`dialog-${panelId}-${analysisResult ? 'results' : 'camera'}`}
      open={open} 
      onClose={onClose} 
      maxWidth="sm" 
      fullWidth 
      PaperProps={{ 
        sx: { 
          maxHeight: '95vh',
          borderRadius: '12px',
          boxShadow: '0 20px 60px rgba(0,0,0,0.3)'
        } 
      }}
    >
      <DialogTitle sx={{ 
        fontWeight: 'bold', 
        fontSize: '1.3rem', 
        display: 'flex', 
        justifyContent: 'space-between', 
        alignItems: 'center',
        background: 'linear-gradient(135deg, #1976d2 0%, #1565c0 100%)',
        color: 'white',
        py: 2
      }}>
        📷 Live Camera - {panelId}
        <IconButton onClick={onClose} size="small" sx={{ color: 'white' }}>
          <Close />
        </IconButton>
      </DialogTitle>
      <DialogContent dividers sx={{ minHeight: '300px', overflowY: 'auto' }}>
        <Box sx={{ pt: 1, textAlign: 'center', width: '100%' }}>
          {error && (
            <Alert severity="error" sx={{ mb: 2 }}>
              {error}
            </Alert>
          )}

          {analysisResult === null || analysisResult === undefined ? (
            // CAMERA VIEW
            <>
              <Box
                sx={{
                  position: 'relative',
                  backgroundColor: '#000',
                  borderRadius: 1,
                  overflow: 'hidden',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  minHeight: '400px',
                  mb: 2
                }}
              >
                {loading && (
                  <CircularProgress sx={{ position: 'absolute' }} />
                )}
                <img
                  id={`camera-image-${panelId}`}
                  src={`${cameraUrl}?t=${imageTimestamp}`}
                  alt={`Live camera feed for ${panelId}`}
                  onLoad={handleImageLoad}
                  onError={handleImageError}
                  style={{
                    width: '100%',
                    height: 'auto',
                    maxHeight: '500px',
                    objectFit: 'contain'
                  }}
                />
              </Box>
              <Typography variant="caption" color="textSecondary">
                Camera URL: {cameraUrl}
              </Typography>
            </>
          ) : (
            <>
              {/* Analysis Results Display */}
              <Alert severity="success" sx={{ mb: 2 }}>
                 Analysis Complete - AI Recommendations Ready
              </Alert>

              <Card sx={{ mb: 3, textAlign: 'left', width: '100%', boxShadow: '0 4px 12px rgba(0,0,0,0.08)', borderRadius: '8px' }}>
                <CardContent sx={{ pb: 2 }}>
                  <Typography variant="h6" gutterBottom sx={{ fontWeight: 'bold', color: '#d32f2f', fontSize: '1.1rem' }}>
                    🔴 Defect Detection Results
                  </Typography>
                  <Box sx={{ mb: 2.5, p: 1.5, backgroundColor: '#fff3e0', borderRadius: '8px', border: '2px solid #ffb74d' }}>
                    <Typography variant="body2" color="textSecondary" sx={{ mb: 0.5, fontWeight: '600', fontSize: '0.85rem' }}>
                      Detected Defect:
                    </Typography>
                    <Chip
                      label={analysisResult.fault}
                      color="error"
                      variant="filled"
                      sx={{ mt: 0.8, mb: 1, fontSize: '0.95rem', fontWeight: 'bold', padding: '24px 16px' }}
                    />
                  </Box>

                  <Box sx={{ mb: 2, p: 1, backgroundColor: '#e3f2fd', borderRadius: '8px' }}>
                    <Typography variant="body2" color="textSecondary" gutterBottom sx={{ fontWeight: 'bold', fontSize: '0.85rem' }}>
                      Model Confidence: {(analysisResult.confidence * 100).toFixed(2)}%
                    </Typography>
                    <LinearProgress
                      variant="determinate"
                      value={analysisResult.confidence * 100}
                      sx={{ height: 10, borderRadius: 4, mb: 0.5, backgroundColor: '#b3e5fc' }}
                    />
                  </Box>

                  <Divider sx={{ my: 2.5 }} />

                  <Typography variant="h6" gutterBottom sx={{ fontWeight: 'bold', mt: 2.5, mb: 0.5, color: '#1565c0', fontSize: '1.1rem' }}>
                    🤖 AI Recommendations (RAG + Gemini AI)
                  </Typography>
                  <Typography variant="body2" color="textSecondary" sx={{ mb: 1.5, fontStyle: 'italic', fontSize: '0.85rem' }}>
                    Based on solar panel knowledge base and maintenance SOPs:
                  </Typography>
                  <Box
                    sx={{
                      backgroundColor: '#f0f7ff',
                      p: 2.5,
                      borderRadius: '8px',
                      maxHeight: '450px',
                      overflowY: 'auto',
                      border: '2px solid #90caf9',
                      fontSize: '0.9rem',
                      lineHeight: 1.7,
                      '&::-webkit-scrollbar': {
                        width: '6px'
                      },
                      '&::-webkit-scrollbar-track': {
                        background: '#f1f1f1',
                        borderRadius: '4px'
                      },
                      '&::-webkit-scrollbar-thumb': {
                        background: '#90caf9',
                        borderRadius: '4px'
                      }
                    }}
                  >
                  {analysisResult.gemini_suggestion ? (
                      <Box sx={{ lineHeight: 1.85 }}>
                        {renderMarkdown(analysisResult.gemini_suggestion)}
                      </Box>
                    ) : (
                      <Typography variant="body2" color="error">
                        No recommendations available from Gemini API.
                      </Typography>
                    )}
                  </Box>

                  {analysisResult.rag_context && (
                    <>
                      <Divider sx={{ my: 2.5 }} />
                      <Typography variant="body2" sx={{ fontWeight: 'bold', display: 'block', mb: 1, color: '#1565c0', fontSize: '0.95rem' }}>
                        📚 Retrieved Knowledge Base Context:
                      </Typography>
                      <Box
                        sx={{
                          backgroundColor: '#f5f5f5',
                          p: 2,
                          borderRadius: '8px',
                          maxHeight: '250px',
                          overflowY: 'auto',
                          border: '1px solid #e0e0e0',
                          fontSize: '0.85rem',
                          '&::-webkit-scrollbar': {
                            width: '6px'
                          },
                          '&::-webkit-scrollbar-track': {
                            background: '#f1f1f1',
                            borderRadius: '4px'
                          },
                          '&::-webkit-scrollbar-thumb': {
                            background: '#bdbdbd',
                            borderRadius: '4px'
                          }
                        }}
                      >
                        {renderMarkdown(analysisResult.rag_context)}
                      </Box>
                    </>
                  )}
                </CardContent>
              </Card>
            </>
          )}
        </Box>
      </DialogContent>
      <DialogActions>
        {analysisResult === null ? (
          <>
            <Button
              onClick={handleAnalyzeImage}
              variant="contained"
              color="success"
              startIcon={analyzing ? <CircularProgress size={20} /> : <CloudUpload />}
              disabled={analyzing}
            >
              {analyzing ? 'Analyzing...' : 'Analyze Image'}
            </Button>
            <Button onClick={handleCaptureImage} variant="outlined" color="secondary" startIcon={<Download />}>
              Download
            </Button>
            <Button onClick={handleRefresh} variant="outlined" color="primary">
              Refresh
            </Button>
          </>
        ) : (
          <>
            <Button
              onClick={() => setAnalysisResult(null)}
              variant="outlined"
              color="primary"
            >
              Back to Camera
            </Button>
            <Button
              onClick={handleAnalyzeImage}
              variant="contained"
              color="success"
              startIcon={<CloudUpload />}
            >
              Analyze Again
            </Button>
          </>
        )}
        <Button onClick={onClose} variant="contained">
          Close
        </Button>
      </DialogActions>
    </Dialog>
  );
};

export default CameraViewer;
