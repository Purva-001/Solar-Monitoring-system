import React from 'react';
import HealthReport from './HealthReport';

const GEnaiAnalysis = ({ panelId = null, onScheduleMaintenanceOpen }) => {
  return (
    <HealthReport
      panelId={panelId}
      onScheduleMaintenanceOpen={onScheduleMaintenanceOpen}
      showPanelIdentification={false}
      showWeatherSummary={false}
    />
  );
};

export default GEnaiAnalysis;
