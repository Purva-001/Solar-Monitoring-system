# Quick Reference - Flutter Solar Dashboard

## Files Modified/Created

### Modified Files
✏️ **dashboard_page.dart**
- Location: `my_app/lib/features/dashboard/presentation/dashboard_page.dart`
- Changes:
  - Added imports for camera and health report pages
  - Updated `_TopHeader` class with camera & health report callbacks
  - Added 3 navigation buttons in header

✏️ **camera_feed_cubit.dart**
- Location: `my_app/lib/features/camera/state/camera_feed_cubit.dart`
- Changes:
  - Added `resetZoom()` method

### New Files Created
🆕 **camera_view_page.dart**
- Location: `my_app/lib/features/camera/presentation/camera_view_page.dart`
- Full camera view page with controls and history

🆕 **health_report_dashboard_page.dart**
- Location: `my_app/lib/features/health_report/presentation/health_report_dashboard_page.dart`
- Comprehensive health report dashboard

## Navigation Flow

```
Dashboard Page
├── Camera Icon (🎥)
│   └── Camera View Page
│       ├── Live Feed
│       ├── Zoom Controls
│       ├── Camera Info
│       └── Recent Captures
│
├── Health Report Icon (📊)
│   └── Health Report Dashboard
│       ├── Overall Health Score
│       ├── Distribution Chart
│       ├── KPI Metrics
│       ├── Panel Details (×4)
│       ├── Recommendations
│       └── Report Timeline
│
└── Refresh Icon (🔄)
    └── Refresh Dashboard Data
```

## Key Components Summary

### Camera View Page
```dart
CameraViewPage()
├── _CameraFeedSection
├── _CameraControlsSection
├── _ControlButton (×4)
├── _CameraInfoSection
├── _InfoRow (×5)
├── _CameraHistorySection
└── _CameraImage
```

### Health Report Dashboard
```dart
HealthReportPage()
├── _OverallHealthCard
├── _HealthDistributionChart
├── _DistributionLegend (×3)
├── _HealthMetricsGrid
│   └── _MetricTile (×4)
├── _PanelDetailCard (×4)
│   └── _StatCell (×4)
├── _RecommendationsCard
│   └── _RecommendationItem
└── _SystemHealthTimelineCard
```

## Color Scheme

| Status | Color | Hex Code |
|--------|-------|----------|
| Healthy | Green | #22C55E |
| Warning | Amber | #F59E0B |
| Critical | Red | #EF4444 |
| Info | Blue | #2563EB |
| Secondary | Gray | #64748B |

## Mock Data Structure

### Health Metrics
```dart
_HealthMetrics(
  totalPanels: 4,
  healthyCount: 3,
  warningCount: 1,
  criticalCount: 0,
  overallScore: 87.5,
  generatedAt: DateTime.now(),
)
```

### Panel Details
```dart
_PanelDetail(
  panelId: 'Panel-P01',
  name: 'Panel 01',
  status: 'healthy',  // 'healthy', 'warning', 'critical'
  voltage: 48.2,
  power: 8.5,
  current: 1.2,
  temperature: 32.5,
  efficiency: 94.2,
)
```

## Button Actions

### Dashboard Header Buttons
```
┌─────────────────────────┐
│ Title         🎥 📊 🔄  │
└─────────────────────────┘
  │   │  └─→ Refresh data
  │   └─────→ Open Health Report
  └─────────→ Open Camera View
```

### Camera Controls
- **Zoom In** - Increase zoom by 0.2x
- **Zoom Out** - Decrease zoom by 0.2x
- **Refresh Feed** - Update camera frame
- **Reset Zoom** - Return to 1.0x zoom

### Health Report Actions
- **Refresh** - Reload health metrics
- **Export** - Download report (future feature)

## Default Values

### Camera
- Initial Zoom: 1.0x
- Min Zoom: 1.0x
- Max Zoom: 5.0x
- Refresh Interval: 5 seconds
- Aspect Ratio: 16:9

### Health Report
- Health Score Range: 0-100
- Excellent: ≥90
- Good: ≥75
- Fair: ≥60
- Poor: <60

## API Integration Points

1. **Health Metrics**
   - Endpoint: `/api/health/metrics`
   - Method: GET
   - Returns: Overall score, panel counts

2. **Panel Details**
   - Endpoint: `/api/health/panels`
   - Method: GET
   - Returns: Array of panel status objects

3. **Camera Feed**
   - Endpoint: `http://192.168.1.200/capture`
   - Method: GET (image/jpeg)
   - Headers: Accept: image/jpeg

4. **Recommendations**
   - Endpoint: `/api/health/recommendations`
   - Method: GET
   - Returns: Array of recommendation strings

## Common Customizations

### Change Camera URL
```dart
// In camera_view_page.dart
static String esp32StreamUrl(int tickMs) {
  return 'YOUR_NEW_URL';
}
```

### Adjust Health Thresholds
```dart
// In health_report_dashboard_page.dart
String get healthStatus {
  if (overallScore >= 95) return 'Excellent';
  if (overallScore >= 85) return 'Good';
  // ...
}
```

### Add Automatic Refresh
```dart
@override
void initState() {
  super.initState();
  Timer.periodic(Duration(seconds: 30), (_) {
    _loadHealthData();
  });
}
```

## Testing Checklist

- [ ] Dashboard buttons are clickable
- [ ] Camera page opens with live feed
- [ ] Health report shows mock data
- [ ] Zoom controls work smoothly
- [ ] Back navigation works
- [ ] Panel cards display correctly
- [ ] Health chart renders
- [ ] Recommendations are visible
- [ ] No console errors
- [ ] Responsive on all screen sizes

## Performance Metrics

- **Camera Page Load Time:** <500ms
- **Health Report Load Time:** <1s
- **Camera Feed Update:** Every 5 seconds
- **Chart Render Time:** <300ms
- **Memory Usage:** <50MB

## Deployment Checklist

- [ ] Replace mock data with real API calls
- [ ] Update camera stream URL
- [ ] Configure health metrics endpoint
- [ ] Add error handling for failed requests
- [ ] Set appropriate timeouts
- [ ] Test on target devices
- [ ] Verify performance
- [ ] Add analytics tracking
- [ ] Update app version
- [ ] Create release build

---

For detailed information, see **FLUTTER_IMPLEMENTATION_GUIDE.md**
