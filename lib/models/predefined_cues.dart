import 'cue.dart';

class PredefinedCue {
  final String id;
  final String displayName;
  final List<CueAction> actions;

  const PredefinedCue({
    required this.id,
    required this.displayName,
    required this.actions,
  });

  Cue toCue() {
    return Cue(
      name: displayName,
      actions: actions,
      cueIndex: int.parse(id.substring(3)), // Extract number from "cueXX"
    );
  }
}

class PredefinedCues {
  static const List<PredefinedCue> cues = [
    PredefinedCue(
      id: 'cue00',
      displayName: 'all_off',
      actions: [],
    ),
    PredefinedCue(
      id: 'cue01',
      displayName: 'standby_to_parked_brake_off',
      actions: [],
    ),
    PredefinedCue(
      id: 'cue02',
      displayName: 'standby_to_parked_brake_on',
      actions: [],
    ),
    PredefinedCue(
      id: 'cue03',
      displayName: 'parked_to_drive',
      actions: [],
    ),
    PredefinedCue(
      id: 'cue04',
      displayName: 'brake_off_to_brake_on',
      actions: [],
    ),
    PredefinedCue(
      id: 'cue05',
      displayName: 'brake_on_to_brake_off',
      actions: [],
    ),
    PredefinedCue(
      id: 'cue06',
      displayName: 'drive_to_parked',
      actions: [],
    ),
    PredefinedCue(
      id: 'cue07',
      displayName: 'parked_brake_off_to_standby',
      actions: [],
    ),
    PredefinedCue(
      id: 'cue08',
      displayName: 'parked_brake_on_to_standby',
      actions: [],
    ),
    PredefinedCue(
      id: 'cue09',
      displayName: 'blink_none',
      actions: [],
    ),
    PredefinedCue(
      id: 'cue10',
      displayName: 'blink_left',
      actions: [],
    ),
    PredefinedCue(
      id: 'cue11',
      displayName: 'blink_right',
      actions: [],
    ),
    PredefinedCue(
      id: 'cue12',
      displayName: 'blink_both',
      actions: [],
    ),
  ];

  static PredefinedCue? getCueById(String id) {
    try {
      return cues.firstWhere((cue) => cue.id == id);
    } catch (e) {
      return null;
    }
  }

  static PredefinedCue? getCueByDisplayName(String displayName) {
    try {
      return cues.firstWhere((cue) => cue.displayName == displayName);
    } catch (e) {
      return null;
    }
  }

  static String getNextFadeId(int currentCount) {
    return 'fade${currentCount.toString().padLeft(2, '0')}';
  }
} 
