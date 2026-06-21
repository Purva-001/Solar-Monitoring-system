import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/panel_info_repository.dart';
import 'panel_info_state.dart';

class PanelInfoCubit extends Cubit<PanelInfoState> {
  PanelInfoCubit({PanelInfoRepository? repository})
      : _repo = repository ?? PanelInfoRepository(),
        super(const PanelInfoLoading());

  final PanelInfoRepository _repo;

  Future<void> load({String panelId = 'PL01-B02-INV03-STR05-P01'}) async {
    try {
      if (isClosed) return;
      emit(const PanelInfoLoading());
      final info = await _repo.fetch(panelId: panelId);
      if (isClosed) return;
      emit(PanelInfoLoaded(info));
    } catch (e) {
      if (isClosed) return;
      emit(PanelInfoError(e.toString()));
    }
  }
}
