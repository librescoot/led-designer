import 'package:flutter/foundation.dart';
import '../models/fade.dart';
import '../models/cue.dart';
import '../models/binary_export.dart';
import '../models/predefined_cues.dart';

class DesignerState extends ChangeNotifier {
  List<Fade> _fades = [];
  List<Cue> _cues = [];
  Fade? _selectedFade;
  Cue? _selectedCue;

  DesignerState() {
    // Initialize with predefined cues
    _cues = PredefinedCues.cues.map((pc) => pc.toCue()).toList();
  }

  List<Fade> get fades => _fades;
  List<Cue> get cues => _cues;
  Fade? get selectedFade => _selectedFade;
  Cue? get selectedCue => _selectedCue;

  void addFade(Fade fade) {
    // Assign next available fade ID
    String fadeId = PredefinedCues.getNextFadeId(_fades.length);
    fade = Fade(
      name: fadeId,  // Use the ID as the internal name
      displayName: fade.name,  // Use the user-given name as display name
      points: fade.points,
      sampleRate: fade.sampleRate,
    );
    _fades.add(fade);
    notifyListeners();
  }

  void updateFade(Fade fade) {
    final index = _fades.indexWhere((f) => f.name == fade.name);
    if (index != -1) {
      _fades[index] = fade;
      notifyListeners();
    }
  }

  void deleteFade(Fade fade) {
    final fadeIndex = _fades.indexWhere((f) => f.name == fade.name);
    if (fadeIndex == -1) return;

    _fades.removeAt(fadeIndex);
    if (_selectedFade?.name == fade.name) {
      _selectedFade = null;
    }

    // Update cues that reference this fade
    for (var cue in _cues) {
      for (var action in cue.actions) {
        if (action.type == CueActionType.fade) {
          // If the action references the deleted fade or a fade after it
          int actionFadeIndex = action.value as int;
          if (actionFadeIndex == fadeIndex) {
            // Point to the previous fade, or the first one if none before
            action.value = fadeIndex > 0 ? fadeIndex - 1 : 0;
          } else if (actionFadeIndex > fadeIndex) {
            // Adjust indices for fades that moved up in the list
            action.value = actionFadeIndex - 1;
          }
        }
      }
    }

    notifyListeners();
  }

  void selectFade(Fade? fade) {
    _selectedFade = fade;
    notifyListeners();
  }

  void updateCue(Cue cue) {
    final index = _cues.indexWhere((c) => c.name == cue.name);
    if (index != -1) {
      // Preserve the cue ID/index when updating
      final existingCue = _cues[index];
      cue = Cue(
        name: cue.name,
        actions: cue.actions,
        cueIndex: existingCue.cueIndex,
      );
      _cues[index] = cue;
      notifyListeners();
    }
  }

  void selectCue(Cue? cue) {
    _selectedCue = cue;
    notifyListeners();
  }

  Future<void> exportAll(String directory) async {
    await BinaryExport.exportAll(_fades, _cues, directory);
  }

  Map<String, dynamic> toJson() => {
    'fades': _fades.map((f) => f.toJson()).toList(),
    'cues': _cues.map((c) => c.toJson()).toList(),
  };

  void loadFromJson(Map<String, dynamic> json) {
    _fades = (json['fades'] as List)
        .map((f) => Fade.fromJson(f as Map<String, dynamic>))
        .toList();
    // Don't load cues from JSON since they're predefined
    _selectedFade = null;
    _selectedCue = null;
    notifyListeners();
  }
} 