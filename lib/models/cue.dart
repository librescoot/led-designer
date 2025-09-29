import 'dart:typed_data';
import 'fade.dart';

/// Type of cue action (matches kernel module)
enum CueActionType {
  fade,     // Play a fade
  duty,     // Set direct duty cycle
  lastDuty  // Use last duty cycle from a fade
}

/// Represents a single action in a cue
class CueAction {
  int ledIndex;
  CueActionType type;
  dynamic value; // Fade index, duty cycle value (0.0-1.0), or fade reference for lastDuty

  CueAction({
    required this.ledIndex,
    required this.type,
    required this.value,
  });

  Map<String, dynamic> toJson() => {
    'ledIndex': ledIndex,
    'type': type == CueActionType.fade ? 'fade' : 
           type == CueActionType.duty ? 'duty' : 'last_duty',
    'value': value,
  };

  factory CueAction.fromJson(Map<String, dynamic> json) {
    CueActionType type;
    dynamic value = json['value'];
    
    switch(json['type'] as String) {
      case 'fade':
        type = CueActionType.fade;
        value = value as int;
        break;
      case 'duty':
        type = CueActionType.duty;
        value = (value as num).toDouble();
        break;
      case 'last_duty':
        type = CueActionType.lastDuty;
        value = value as String;
        break;
      default:
        throw Exception('Unknown cue action type: ${json['type']}');
    }

    return CueAction(
      ledIndex: json['ledIndex'] as int,
      type: type,
      value: value,
    );
  }

  /// Convert to binary format for kernel module
  Uint8List toBinary() {
    var data = Uint8List(4);
    int typeFlag = type == CueActionType.fade ? 0 : 1;
    
    // First two bytes: LED index with type flag in high byte
    data[0] = ledIndex & 0xFF;
    data[1] = typeFlag;

    // Second two bytes: value (little-endian)
    int valueInt;
    switch(type) {
      case CueActionType.fade:
        valueInt = value as int;
        break;
      case CueActionType.duty:
        // Scale duty cycle by PWM period
        double scaledDuty = (value as double);
        valueInt = (scaledDuty * Fade.pwmPeriod).round().clamp(0, Fade.pwmPeriod);
        break;
      case CueActionType.lastDuty:
        // For lastDuty, we need the fade's last duty value
        // This should be handled at a higher level since we need access to the fade data
        throw UnimplementedError('lastDuty conversion must be handled by Cue class');
    }
    
    data[2] = valueInt & 0xFF;         // Low byte
    data[3] = (valueInt >> 8) & 0xFF;  // High byte
    
    return data;
  }
}

/// Represents a complete cue sequence
class Cue {
  String name;
  List<CueAction> actions;
  int? cueIndex; // Index in the kernel module

  Cue({
    required this.name,
    required this.actions,
    this.cueIndex,
  });

  /// Convert entire cue to binary format for kernel module
  Uint8List toBinary({Map<String, Fade>? fadeMap}) {
    var buffer = BytesBuilder();
    
    for (var action in actions) {
      if (action.type == CueActionType.lastDuty) {
        if (fadeMap == null) {
          throw ArgumentError('fadeMap is required for cues with lastDuty actions');
        }
        
        // Get the referenced fade
        String fadePath = action.value as String;
        var fade = fadeMap[fadePath];
        if (fade == null) {
          throw ArgumentError('Fade not found: $fadePath');
        }
        
        // Create a duty action with the fade's last duty value
        var lastDuty = fade.points.last.duty.clamp(Fade.minDuty, Fade.maxDuty);
        var dutyAction = CueAction(
          ledIndex: action.ledIndex,
          type: CueActionType.duty,
          value: lastDuty,
        );
        buffer.add(dutyAction.toBinary());
      } else {
        buffer.add(action.toBinary());
      }
    }
    
    return buffer.takeBytes();
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'cueIndex': cueIndex,
    'actions': actions.map((a) => a.toJson()).toList(),
  };

  factory Cue.fromJson(Map<String, dynamic> json) {
    return Cue(
      name: json['name'] as String,
      cueIndex: json['cueIndex'] as int?,
      actions: (json['actions'] as List)
          .map((a) => CueAction.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }
}
