import 'package:equatable/equatable.dart';

import '../domain/panel_comparison_models.dart';

sealed class PanelInfoState extends Equatable {
  const PanelInfoState();

  @override
  List<Object?> get props => [];
}

class PanelInfoLoading extends PanelInfoState {
  const PanelInfoLoading();
}

class PanelInfoLoaded extends PanelInfoState {
  const PanelInfoLoaded(this.info);

  final PanelInfo info;

  @override
  List<Object?> get props => [info];
}

class PanelInfoError extends PanelInfoState {
  const PanelInfoError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
