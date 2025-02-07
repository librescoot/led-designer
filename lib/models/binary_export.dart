import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'fade.dart';
import 'cue.dart';

/// Handles exporting fades and cues in the kernel module binary format
class BinaryExport {
  /// Export a fade to a binary file
  static Future<void> exportFade(Fade fade, String path, int fadeIndex) async {
    var samples = fade.toBinary();
    var file = File(path);
    await file.writeAsBytes(samples.buffer.asUint8List());
  }

  /// Export a cue to a binary file
  static Future<void> exportCue(Cue cue, String path, Map<String, int> fadeIndices) async {
    // Create a map of fade paths to Fade objects for lastDuty resolution
    var fadeMap = <String, Fade>{};
    for (var action in cue.actions) {
      if (action.type == CueActionType.lastDuty) {
        var fadePath = action.value as String;
        var fadeFile = File(fadePath);
        if (await fadeFile.exists()) {
          var fadeJson = jsonDecode(await fadeFile.readAsString());
          fadeMap[fadePath] = Fade.fromJson(fadeJson);
        }
      }
    }
    
    var binary = cue.toBinary(fadeMap: fadeMap);
    var file = File(path);
    await file.writeAsBytes(binary);
  }

  /// Export a collection of fades and cues to a directory
  static Future<void> exportAll(
    List<Fade> fades,
    List<Cue> cues,
    String directory,
  ) async {
    var dir = Directory(directory);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    // Create a map to track fade indices
    var fadeIndices = <String, int>{};
    
    // Export fades with numeric filenames
    for (var i = 0; i < fades.length; i++) {
      var fade = fades[i];
      var path = '${dir.path}/fade$i';
      fadeIndices[fade.name] = i;  // Store the index for this fade
      await exportFade(fade, path, i);
    }

    // Export cues with numeric filenames
    for (var i = 0; i < cues.length; i++) {
      var cue = cues[i];
      var index = cue.cueIndex ?? i;
      var path = '${dir.path}/cue$index';
      await exportCue(cue, path, fadeIndices);
    }

    // Create a manifest file
    var manifest = {
      'fades': fades.map((f) => {
        ...f.toJson(),
        'fadeIndex': fadeIndices[f.name],
        'filename': 'fade${fadeIndices[f.name]}',
      }).toList(),
      'cues': cues.map((c) => {
        ...c.toJson(),
        'filename': 'cue${c.cueIndex ?? cues.indexOf(c)}',
      }).toList(),
    };
    
    await File('${dir.path}/manifest.json')
        .writeAsString(jsonEncode(manifest, toEncodable: (obj) {
          if (obj is double) {
            return obj.toStringAsFixed(6); // Format doubles with fixed precision
          }
          return obj;
        }));
  }
}
