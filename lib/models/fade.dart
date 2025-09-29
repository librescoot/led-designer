import 'dart:math';
import 'dart:typed_data';

/// Curve interpolation type
enum CurveType {
  linear,
  bezier,
}

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
      (json['time'] as num).toDouble(),
      (json['duty'] as num).toDouble(),
    );
  }
}

/// Represents a complete LED fade curve
class Fade {
  String name;  // Internal name (fade00, fade01, etc.)
  String displayName;  // User-given name
  List<FadePoint> points;
  int sampleRate; // Samples per second
  CurveType curveType; // Interpolation type
  List<FadePoint>? _cachedBezierPoints; // Cached Bézier curve points
  static const int pwmPeriod = 12000; // PWM period to match kernel module
  static const double minDuty = 0.0; // Minimum duty cycle
  static const double maxDuty = 1.0; // Maximum duty cycle

  Fade({
    required this.name,
    String? displayName,
    required this.points,
    this.sampleRate = 250, // Default 250Hz to match kernel module
    this.curveType = CurveType.linear, // Default to linear for compatibility
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

  /// Calculate binomial coefficient for Bézier curves
  static double _binomialCoefficient(int n, int k) {
    if (k > n) return 0;
    if (k == 0 || k == n) return 1;

    double result = 1;
    for (int i = 1; i <= k; i++) {
      result = result * (n - i + 1) / i;
    }
    return result;
  }

  /// Calculate Bézier curve points using control points
  List<FadePoint> _calculateBezierCurve(int numPoints) {
    if (points.length < 2) return List.from(points);

    // Use the existing fade points as control points
    final controlPoints = points;
    final n = controlPoints.length - 1;
    final result = <FadePoint>[];

    // Get time bounds from original points
    final startTime = controlPoints.first.time;
    final endTime = controlPoints.last.time;
    final timeRange = endTime - startTime;

    // Calculate curve points with proper time distribution
    for (int i = 0; i <= numPoints; i++) {
      final t = i / numPoints;

      // Calculate Bézier position in normalized space (0-1)
      double normalizedTime = 0;
      double duty = 0;

      for (int j = 0; j <= n; j++) {
        final bernstein = _binomialCoefficient(n, j) *
                         pow(1 - t, n - j) *
                         pow(t, j);

        // Normalize control point times to 0-1 range for Bézier calculation
        final normalizedControlTime = (controlPoints[j].time - startTime) / timeRange;
        normalizedTime += bernstein * normalizedControlTime;
        duty += bernstein * controlPoints[j].duty;
      }

      // Convert back to actual time scale
      final actualTime = startTime + (normalizedTime * timeRange);
      result.add(FadePoint(actualTime, duty.clamp(minDuty, maxDuty)));
    }

    // Ensure points are sorted by time
    result.sort((a, b) => a.time.compareTo(b.time));
    return result;
  }

  /// Get cached Bézier curve points or calculate them
  List<FadePoint> _getBezierPoints() {
    if (_cachedBezierPoints == null || curveType != CurveType.bezier) {
      final numPoints = (duration * 2).round().clamp(100, 1000); // Adaptive resolution
      _cachedBezierPoints = _calculateBezierCurve(numPoints);
    }
    return _cachedBezierPoints!;
  }

  /// Interpolate duty cycle at a given time
  double interpolateDuty(double time) {
    if (points.isEmpty) return 0;
    if (points.length == 1) return points[0].duty.clamp(minDuty, maxDuty);
    if (time <= points.first.time) return points.first.duty.clamp(minDuty, maxDuty);
    if (time >= points.last.time) return points.last.duty.clamp(minDuty, maxDuty);

    if (curveType == CurveType.bezier && points.length >= 2) {
      // Use Bézier curve interpolation
      final bezierPoints = _getBezierPoints();
      if (bezierPoints.isEmpty) return 0;
      if (bezierPoints.length == 1) return bezierPoints[0].duty.clamp(minDuty, maxDuty);

      // Find surrounding Bézier points and interpolate
      int i = 1;
      while (i < bezierPoints.length && bezierPoints[i].time < time) {
        i++;
      }

      var p0 = bezierPoints[i - 1];
      var p1 = bezierPoints[i];

      // Linear interpolation between Bézier points
      double t = (time - p0.time) / (p1.time - p0.time);
      return (p0.duty + t * (p1.duty - p0.duty)).clamp(minDuty, maxDuty);
    } else {
      // Use linear interpolation
      int i = 1;
      while (i < points.length && points[i].time < time) {
        i++;
      }

      var p0 = points[i - 1];
      var p1 = points[i];

      double t = (time - p0.time) / (p1.time - p0.time);
      return (p0.duty + t * (p1.duty - p0.duty)).clamp(minDuty, maxDuty);
    }
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'displayName': displayName,
    'points': points.map((p) => p.toJson()).toList(),
    'sampleRate': sampleRate,
    'curveType': curveType.name,
  };

  factory Fade.fromJson(Map<String, dynamic> json) {
    // Parse curve type with fallback to linear for backward compatibility
    CurveType curveType = CurveType.linear;
    if (json.containsKey('curveType')) {
      final curveTypeStr = json['curveType'] as String;
      curveType = CurveType.values.firstWhere(
        (e) => e.name == curveTypeStr,
        orElse: () => CurveType.linear,
      );
    }

    return Fade(
      name: json['name'] as String,
      displayName: json['displayName'] as String?,
      points: (json['points'] as List).map((p) => FadePoint.fromJson(p as Map<String, dynamic>)).toList(),
      sampleRate: (json['sampleRate'] as num?)?.toInt() ?? 250,
      curveType: curveType,
    );
  }

  /// Clear cached Bézier points when points change
  void _invalidateCache() {
    _cachedBezierPoints = null;
  }
}
