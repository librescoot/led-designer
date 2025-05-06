import 'dart:math';
import 'dart:typed_data';

/// Represents a point in the fade curve
class FadePoint {
  final double time; // Time in milliseconds
  final double duty; // Duty cycle (0.0 - 1.0)

  FadePoint(this.time, this.duty);

  Map<String, dynamic> toJson() => {
    'time': time,
    'duty': duty,
  };

  factory FadePoint.fromJson(Map<String, dynamic> json) {
    return FadePoint(
      json['time'] as double,
      json['duty'] as double,
    );
  }
}

/// Represents a complete LED fade curve
class Fade {
  String name;  // Internal name (fade00, fade01, etc.)
  String displayName;  // User-given name
  List<FadePoint> points;
  int sampleRate; // Samples per second
  static const int pwmPeriod = 12000; // PWM period to match kernel module
  static const double minDuty = 0.0; // Minimum duty cycle
  static const double maxDuty = 1.0; // Maximum duty cycle

  Fade({
    required this.name,
    String? displayName,
    required this.points,
    this.sampleRate = 250, // Default 250Hz to match kernel module
  }) : displayName = displayName ?? name {
    // Sort points by time
    points.sort((a, b) => a.time.compareTo(b.time));
  }

  /// Get the total duration of the fade in milliseconds
  double get duration => points.isEmpty ? 0 : points.last.time;

  /// Get the direction of the fade (for kernel module)
  int getDirection() {
    if (points.length < 2) return 0; // Unknown

    bool increasing = false;
    bool decreasing = false;

    for (int i = 1; i < points.length; i++) {
      double diff = points[i].duty - points[i - 1].duty;
      if (diff > 0) increasing = true;
      if (diff < 0) decreasing = true;
      
      if (increasing && decreasing) return 2; // Non-monotonic
    }

    return increasing ? 0 : 1; // Increasing : Decreasing
  }

  /// Convert the fade curve to binary samples for the kernel module
  Uint8List toBinary() {
    if (points.isEmpty) return Uint8List(0);

    // Calculate number of samples needed
    int numSamples = (duration * sampleRate / 1000).ceil();
    
    // Ensure we don't exceed the kernel module's maximum fade size
    if (numSamples > 8192) {
      // Adjust sample rate to fit within limit while preserving duration
      sampleRate = ((8192 * 1000) / duration).floor();
      numSamples = 8192;
    }
    
    // Create a buffer for 16-bit samples
    var samples = Uint16List(numSamples);
    var byteBuffer = Uint8List(numSamples * 2); // For little-endian conversion

    // Generate samples using linear interpolation
    for (int i = 0; i < numSamples; i++) {
      double time = i * 1000 / sampleRate;
      double duty = interpolateDuty(time).clamp(minDuty, maxDuty);
      int value = (duty * pwmPeriod).round().clamp(0, pwmPeriod);
      samples[i] = value;
      
      // Convert to little-endian bytes
      byteBuffer[i * 2] = value & 0xFF;         // Low byte
      byteBuffer[i * 2 + 1] = (value >> 8) & 0xFF;  // High byte
    }

    return byteBuffer;
  }

  /// Interpolate duty cycle at a given time
  double interpolateDuty(double time) {
    if (points.isEmpty) return 0;
    if (points.length == 1) return points[0].duty.clamp(minDuty, maxDuty);
    if (time <= points.first.time) return points.first.duty.clamp(minDuty, maxDuty);
    if (time >= points.last.time) return points.last.duty.clamp(minDuty, maxDuty);

    // Find surrounding points
    int i = 1;
    while (i < points.length && points[i].time < time) i++;
    
    var p0 = points[i - 1];
    var p1 = points[i];
    
    // Linear interpolation
    double t = (time - p0.time) / (p1.time - p0.time);
    return (p0.duty + t * (p1.duty - p0.duty)).clamp(minDuty, maxDuty);
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'displayName': displayName,
    'points': points.map((p) => p.toJson()).toList(),
    'sampleRate': sampleRate,
  };

  factory Fade.fromJson(Map<String, dynamic> json) {
    return Fade(
      name: json['name'] as String,
      displayName: json['displayName'] as String?,
      points: (json['points'] as List).map((p) => FadePoint.fromJson(p as Map<String, dynamic>)).toList(),
      sampleRate: json['sampleRate'] as int? ?? 250,
    );
  }
}
