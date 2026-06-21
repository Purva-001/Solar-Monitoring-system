import '../domain/maintenance_models.dart';

MaintenanceComparison demoMaintenanceComparison() {
  return const MaintenanceComparison(
    panelId: 'PL01-B02-INV03-STR05-P01',
    channelIdx: 1,
    beforePowerW: 1.0,
    afterPowerWStored: 5.0,
    liveChannelPowerW: null,
    beforeStatus: 'Faulty',
    afterStatus: 'Healthy',
    beforeDeviationPct: 45.0,
    afterDeviationPct: 0.0,
  );
}
