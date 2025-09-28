import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'fade.dart';
import 'cue.dart';

/// Handles exporting and importing fades and cues in the kernel module binary format
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

  /// Import a fade from a binary file
  static Future<Fade> importFade(String path, {String? name}) async {
    var file = File(path);
    if (!await file.exists()) {
      throw Exception('Fade file not found: $path');
    }

    var bytes = await file.readAsBytes();
    return _parseFadeFromBytes(bytes, name ?? _extractNameFromPath(path));
  }

  /// Import a cue from a binary file
  static Future<Cue> importCue(String path, {String? name}) async {
    var file = File(path);
    if (!await file.exists()) {
      throw Exception('Cue file not found: $path');
    }

    var bytes = await file.readAsBytes();
    return _parseCueFromBytes(bytes, name ?? _extractNameFromPath(path));
  }

  /// Import all fades and cues from a directory
  static Future<Map<String, dynamic>> importAll(String directory) async {
    var dir = Directory(directory);
    if (!dir.existsSync()) {
      throw Exception('Directory not found: $directory');
    }

    var fades = <Fade>[];
    var cues = <Cue>[];

    var files = await dir.list().toList();

    // Import fades
    for (var file in files) {
      if (file is File && file.path.contains('fade')) {
        try {
          var fade = await importFade(file.path);
          fades.add(fade);
        } catch (e) {
          print('Warning: Failed to import fade ${file.path}: $e');
        }
      }
    }

    // Import cues
    for (var file in files) {
      if (file is File && file.path.contains('cue')) {
        try {
          var cue = await importCue(file.path);
          cues.add(cue);
        } catch (e) {
          print('Warning: Failed to import cue ${file.path}: $e');
        }
      }
    }

    return {
      'fades': fades,
      'cues': cues,
    };
  }

  /// Parse a fade from binary data
  static Fade _parseFadeFromBytes(Uint8List bytes, String name) {
    if (bytes.length % 2 != 0) {
      throw Exception('Invalid fade file: length must be even (16-bit samples)');
    }

    var numSamples = bytes.length ~/ 2;
    var points = <FadePoint>[];

    // Assume default sample rate of 250Hz
    const sampleRate = 250;

    // Convert little-endian bytes back to 16-bit values
    for (int i = 0; i < numSamples; i++) {
      int byteIndex = i * 2;
      int value = bytes[byteIndex] | (bytes[byteIndex + 1] << 8);

      double time = i * 1000.0 / sampleRate; // Convert to milliseconds
      double duty = value / Fade.pwmPeriod; // Convert back to duty cycle

      points.add(FadePoint(time, duty));
    }

    // Optimize points by removing redundant ones (same duty cycle)
    var optimizedPoints = <FadePoint>[];
    if (points.isNotEmpty) {
      optimizedPoints.add(points.first);

      for (int i = 1; i < points.length - 1; i++) {
        var prev = points[i - 1];
        var curr = points[i];
        var next = points[i + 1];

        // Keep point if duty changes significantly
        if ((curr.duty - prev.duty).abs() > 0.001 ||
            (next.duty - curr.duty).abs() > 0.001) {
          optimizedPoints.add(curr);
        }
      }

      if (points.length > 1) {
        optimizedPoints.add(points.last);
      }
    }

    return Fade(
      name: name,
      displayName: name,
      points: optimizedPoints,
      sampleRate: sampleRate,
    );
  }

  /// Parse a cue from binary data
  static Cue _parseCueFromBytes(Uint8List bytes, String name) {
    if (bytes.length % 4 != 0) {
      throw Exception('Invalid cue file: length must be multiple of 4 (4-byte actions)');
    }

    var numActions = bytes.length ~/ 4;
    var actions = <CueAction>[];

    for (int i = 0; i < numActions; i++) {
      int byteIndex = i * 4;

      // Parse action structure: [ledIndex, typeFlag, valueLow, valueHigh]
      int ledIndex = bytes[byteIndex];
      int typeFlag = bytes[byteIndex + 1];
      int valueLow = bytes[byteIndex + 2];
      int valueHigh = bytes[byteIndex + 3];
      int value = valueLow | (valueHigh << 8);

      CueActionType type;
      dynamic actionValue;

      if (typeFlag == 0) {
        // Fade action
        type = CueActionType.fade;
        actionValue = value; // Fade index
      } else {
        // Duty action
        type = CueActionType.duty;
        actionValue = value / Fade.pwmPeriod; // Convert back to duty cycle
      }

      actions.add(CueAction(
        ledIndex: ledIndex,
        type: type,
        value: actionValue,
      ));
    }

    // Extract cue index from name if possible
    int? cueIndex;
    var match = RegExp(r'cue(\d+)').firstMatch(name);
    if (match != null) {
      cueIndex = int.parse(match.group(1)!);
    }

    return Cue(
      name: name,
      actions: actions,
      cueIndex: cueIndex,
    );
  }

  /// Extract name from file path
  static String _extractNameFromPath(String path) {
    var file = File(path);
    var basename = file.path.split('/').last;
    return basename;
  }
}
