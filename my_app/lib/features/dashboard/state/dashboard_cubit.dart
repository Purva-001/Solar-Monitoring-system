import 'package:flutter_bloc/flutter_bloc.dart';

import 'dart:async';

import '../data/dashboard_repository.dart';
import '../domain/dashboard_models.dart';
import 'dashboard_state.dart';

class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit({DashboardRepository? repository})
      : _repo = repository ?? DashboardRepository(),
        super(const DashboardLoading());

  final DashboardRepository _repo;

  Timer? _timer;
  final List<dynamic> _powerSeries = <dynamic>[];

  Future<void> load() async {
    try {
      if (isClosed) return;
      emit(const DashboardLoading());
      await _refreshOnce(includeHistory: true);
      if (isClosed) return;

      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        _refreshOnce(includeHistory: false);
      });
    } catch (e) {
      if (isClosed) return;
      emit(DashboardError(e.toString()));
    }
  }

  Future<void> refreshNow() => _refreshOnce(includeHistory: true);

  Future<void> _refreshOnce({bool includeHistory = false}) async {
    try {
      final readings = await _repo.fetchReadings();
      final panels = await _repo.fetchPanels();
      if (isClosed) return;

      if (includeHistory) {
        try {
          final history = await _repo.fetchPowerTrendFromHistory();
          _powerSeries
            ..clear()
            ..addAll(history.map((p) => <String, dynamic>{'tsMs': p.tsMs, 'w': p.w}));
        } catch (_) {
          // History optional if endpoint unset or error; keep existing in-memory series.
        }
      }

      final now = DateTime.now();
      final tsMs = now.millisecondsSinceEpoch;
      _powerSeries.add({'tsMs': tsMs, 'w': double.parse(readings.totalPowerW.toStringAsFixed(2))});

      final cutoff = tsMs - (7 * 24 * 60 * 60 * 1000);
      _powerSeries.removeWhere((e) => (e is Map) && (e['tsMs'] is num) && (e['tsMs'] as num).toInt() < cutoff);
      if (_powerSeries.length > 10000) {
        _powerSeries.removeRange(0, _powerSeries.length - 10000);
      }

      final points = _powerSeries
          .whereType<Map>()
          .map((e) => PowerPoint(tsMs: (e['tsMs'] as num).toInt(), w: (e['w'] as num).toDouble()))
          .toList(growable: false);

      emit(DashboardLoaded(panels: panels, readings: readings, powerSeries: points, lastUpdated: now));
    } catch (e) {
      if (isClosed) return;
      final prev = state;
      if (prev is DashboardLoaded) {
        emit(DashboardError(e.toString()));
        if (isClosed) return;
        emit(prev);
      } else {
        emit(DashboardError(e.toString()));
      }
    }
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
