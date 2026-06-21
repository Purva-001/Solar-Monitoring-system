import React, { useState } from 'react';
import { Box, IconButton, Paper, Typography } from '@mui/material';
import { AddCircleOutline, RemoveCircleOutline, Refresh, Videocam, ErrorOutline } from '@mui/icons-material';

const LiveCameraFeed = () => {
  const [zoom, setZoom] = useState(1.0);
  const [tick, setTick] = useState(Date.now());
  const [hasError, setHasError] = useState(false);

  // create-react-app uses REACT_APP_ prefix. If missing, fallback to the provided IP.
  const baseUrl =
    process.env.REACT_APP_ESP32_CAM_STREAM_BASE ||
    process.env.ESP32_CAM_STREAM_BASE ||
    'http://10.235.197.223:3001';
  const feedUrl = `${baseUrl}/stream?t=${tick}`;

  return (
    <Paper
      elevation={0}
      sx={{
        p: 2.25,
        borderRadius: 2.5,
        border: '1px solid #e2e8f0',
        boxShadow: '0 2px 8px rgba(15,23,42,0.04)',
        height: '100%'
      }}
    >
      {/* Header */}
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <Videocam sx={{ color: '#8dbef6ff' }} />
          <Typography variant="h5" fontWeight={900}>AI Visual Inspection</Typography>
        </Box>
        <Box sx={{ display: 'flex', gap: 1 }}>
          <IconButton
            sx={{ bgcolor: '#f8fafc', border: '1px solid #e2e8f0' }}
            size="small"
            onClick={() => setZoom((z) => Math.max(z - 0.2, 1.0))}
          >
            <RemoveCircleOutline fontSize="small" sx={{ color: '#aec4f1ff' }} />
          </IconButton>
          <IconButton
            sx={{ bgcolor: '#f8fafc', border: '1px solid #e2e8f0' }}
            size="small"
            onClick={() => setZoom((z) => Math.min(z + 0.2, 3.0))}
          >
            <AddCircleOutline fontSize="small" sx={{ color: '#16a34a' }} />
          </IconButton>
          <IconButton
            sx={{ bgcolor: '#f8fafc', border: '1px solid #e2e8f0' }}
            size="small"
            onClick={() => {
              setTick(Date.now());
              setHasError(false);
            }}
          >
            <Refresh fontSize="small" sx={{ color: '#f59e0b' }} />
          </IconButton>
        </Box>
      </Box>

      {/* Camera viewport */}
      <Box
        sx={{
          position: 'relative',
          overflow: 'hidden',
          borderRadius: 2.5,
          bgcolor: '#f1f5f9',
          aspectRatio: '16/9',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center'
        }}
      >
        {/* LIVE badge */}
        <Box
          sx={{
            position: 'absolute',
            top: 12,
            right: 12,
            zIndex: 10,
            px: 1.5,
            py: 0.5,
            borderRadius: '999px',
            bgcolor: 'rgba(220, 252, 231, 0.95)',
            border: '1px solid rgba(34, 197, 94, 0.4)'
          }}
        >
          <Typography
            sx={{
              fontWeight: 900,
              color: '#166534',
              fontSize: '0.75rem',
              display: 'flex',
              alignItems: 'center',
              gap: 0.5,
              letterSpacing: 0.5
            }}
          >
            <Box sx={{ width: 6, height: 6, borderRadius: '50%', bgcolor: '#22c55e' }} />
            LIVE
          </Typography>
        </Box>

        {hasError ? (
          <Box sx={{ textAlign: 'center' }}>
            <ErrorOutline sx={{ fontSize: 48, color: '#94a3b8', mb: 1.5 }} />
            <Typography sx={{ color: '#64748b', fontWeight: 800 }}>Camera Feed Unavailable</Typography>
            <Typography sx={{ color: '#94a3b8', fontWeight: 600, fontSize: '0.85rem' }}>
              Check camera connection
            </Typography>
          </Box>
        ) : (
          <img
            src={feedUrl}
            alt="Live Camera Stream"
            style={{
              width: '100%',
              height: '100%',
              objectFit: 'cover',
              transform: `scale(${zoom})`,
              transition: 'transform 0.2s ease',
              display: 'block'
            }}
            onError={() => setHasError(true)}
          />
        )}
      </Box>

      {/* Footer */}
      <Box sx={{ display: 'flex', justifyContent: 'space-between', mt: 2, px: 1 }}>
        <Typography variant="body2" color="text.secondary" fontWeight={800}>
          Zoom: {zoom.toFixed(1)}x
        </Typography>
      </Box>
    </Paper>
  );
};

export default LiveCameraFeed;