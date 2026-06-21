// filepath: c:\Users\kunal salankar\Downloads\rag_folder\solar-dashboard\frontend\src\components\DashboardHome.js
import React, { useState, useEffect } from 'react';
import './DashboardHome.css';

const DashboardHome = () => {
  const [panelReport, setPanelReport] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    fetchPanelReport();
  }, []);

  const fetchPanelReport = async () => {
    try {
      setLoading(true);
      const response = await fetch('http://localhost:8000/api/panel-report/Solar-Panel-1');
      const data = await response.json();
      
      if (response.ok) {
        setPanelReport(data);
        setError(null);
      } else {
        setError(data.detail || 'Failed to fetch report');
      }
    } catch (err) {
      setError('Unable to connect to backend');
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  const checkVoltageAndAnalyze = async () => {
    try {
      setLoading(true);
      
      // Step 1: Check voltage
      const voltageResponse = await fetch(
        'http://localhost:8000/api/sitewise/check-voltage?threshold=4.0',
        { method: 'POST' }
      );
      const voltageData = await voltageResponse.json();
      
      if (voltageData.trigger_esp32) {
        console.log('✅ Voltage threshold exceeded! Triggering analysis...');
        
        // Step 2: Capture and analyze
        const analysisResponse = await fetch(
          'http://localhost:8000/api/esp32/capture-and-analyze',
          { method: 'POST' }
        );
        const analysisData = await analysisResponse.json();
        
        if (analysisResponse.ok) {
          setPanelReport(analysisData);
          setError(null);
        } else {
          setError(analysisData.detail || 'Analysis failed');
        }
      } else {
        setError(`Voltage (${voltageData.v1_value}V) is within safe limits. No analysis needed.`);
      }
    } catch (err) {
      setError('Failed to analyze panel');
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="dashboard-home">
      <div className="dashboard-header">
        <h1>☀️ Solar Panel Health Dashboard</h1>
        <p>Real-time monitoring and AI-powered analysis</p>
      </div>

      <div className="action-buttons">
        <button 
          onClick={checkVoltageAndAnalyze} 
          disabled={loading}
          className="btn btn-primary"
        >
          {loading ? '⏳ Analyzing...' : '🔍 Check & Analyze Panel'}
        </button>
        <button 
          onClick={fetchPanelReport} 
          disabled={loading}
          className="btn btn-secondary"
        >
          {loading ? '⏳ Loading...' : '📋 Refresh Report'}
        </button>
      </div>

      {error && (
        <div className="error-message">
          <span>❌ {error}</span>
          <button onClick={() => setError(null)}>✕</button>
        </div>
      )}

      {panelReport && (
        <div className="report-container">
          <div className="report-card">
            <h2>📊 Latest Panel Report</h2>
            
            <div className="report-info">
              <div className="info-item">
                <span className="label">Panel ID:</span>
                <span className="value">{panelReport.panel_id || panelReport.fault_detection || 'Solar-Panel-1'}</span>
              </div>
              
              {panelReport.fault_detection && (
                <>
                  <div className="info-item">
                    <span className="label">Defect Detected:</span>
                    <span className={`value defect-${panelReport.fault_detection.toLowerCase()}`}>
                      {panelReport.fault_detection}
                    </span>
                  </div>
                  
                  <div className="info-item">
                    <span className="label">Confidence:</span>
                    <span className="value">{(panelReport.confidence * 100).toFixed(1)}%</span>
                  </div>
                </>
              )}
              
              <div className="info-item">
                <span className="label">Report Time:</span>
                <span className="value">
                  {new Date(panelReport.timestamp).toLocaleString()}
                </span>
              </div>
            </div>

            {panelReport.image_url && (
              <div className="report-image">
                <img 
                  src={`http://localhost:8000${panelReport.image_url}`} 
                  alt="Panel capture"
                  onError={() => console.error('Failed to load image')}
                />
              </div>
            )}

            {panelReport.health_report && (
              <div className="health-report-content">
                <h3>📋 AI Health Report</h3>
                <div className="report-text">
                  {panelReport.health_report.split('\n').map((line, idx) => (
                    <div key={idx} className="report-line">
                      {line}
                    </div>
                  ))}
                </div>
              </div>
            )}

            {panelReport.rag_context && (
              <div className="rag-context">
                <h3>📚 Knowledge Base Context</h3>
                <div className="context-text">
                  {panelReport.rag_context}
                </div>
              </div>
            )}
          </div>
        </div>
      )}

      {!panelReport && !loading && (
        <div className="no-report">
          <p>No panel report available yet.</p>
          <p>Click "Check & Analyze Panel" to generate a report.</p>
        </div>
      )}
    </div>
  );
};

export default DashboardHome;