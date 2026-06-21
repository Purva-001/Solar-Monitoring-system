import React from 'react';
import { Card, CardContent, Box, Typography } from '@mui/material';

const SummaryMetricCard = ({ label, value, unit, color, icon }) => {
  return (
    <Card elevation={0} sx={{ borderRadius: 2, border: '1px solid #eaeaea', bgcolor: '#fff' }}>
      <CardContent sx={{ p: 2.25 }}>
        <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 1.5 }}>
          <Box
            sx={{
              width: 38,
              height: 38,
              borderRadius: 2,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              bgcolor: `${color}15`,
              color
            }}
          >
            {icon}
          </Box>
        </Box>

        <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 0.75 }}>
          {label}
        </Typography>
        <Typography variant="h6" fontWeight={900}>
          {value}
          {unit ? (
            <Typography component="span" variant="caption" sx={{ ml: 0.75, color: 'text.secondary', fontWeight: 700 }}>
              {unit}
            </Typography>
          ) : null}
        </Typography>
      </CardContent>
    </Card>
  );
};

export default SummaryMetricCard;
