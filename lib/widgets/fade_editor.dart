import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math' show max;
import 'dart:async';
import '../models/fade.dart';
import '../providers/designer_state.dart';

class FadeEditor extends StatefulWidget {
  const FadeEditor({super.key});

  @override
  State<FadeEditor> createState() => _FadeEditorState();
}

class LedPreview extends StatefulWidget {
  final List<FadePoint> points;
  final double maxDuration;

  const LedPreview({
    super.key,
    required this.points,
    required this.maxDuration,
  });

  @override
  State<LedPreview> createState() => _LedPreviewState();
}

class _LedPreviewState extends State<LedPreview> {
  Timer? _animationTimer;
  double _currentTime = 0;
  double _currentBrightness = 0;
  bool _isPaused = false;
  bool _isHoldingFinal = false;

  @override
  void initState() {
    super.initState();
    _startAnimation();
  }

  @override
  void dispose() {
    _animationTimer?.cancel();
    super.dispose();
  }

  void _startAnimation() {
    _animationTimer?.cancel();
    _currentTime = 0;
    _currentBrightness = 0;
    _isPaused = false;
    _isHoldingFinal = false;
    
    _animationTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      setState(() {
        if (_isPaused) {
          _currentBrightness = 0;
          return;
        }
        
        if (_isHoldingFinal) {
          return; // Keep the current brightness
        }
        
        _currentTime += 16;
        
        // Find the time of the rightmost point
        final lastPointTime = widget.points.isEmpty ? 0.0 : 
          widget.points.reduce((a, b) => a.time > b.time ? a : b).time.toDouble();
        
        if (_currentTime >= lastPointTime) {
          _currentTime = lastPointTime;
          _currentBrightness = _calculateBrightness(_currentTime).clamp(0.0, 1.0);
          _isHoldingFinal = true;
          
          // Hold final brightness for 2 seconds
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              setState(() {
                _currentBrightness = 0;
                _isPaused = true;
                _isHoldingFinal = false;
                
                // Wait 2 seconds before starting next animation
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) {
                    setState(() {
                      _currentTime = 0;
                      _isPaused = false;
                    });
                  }
                });
              });
            }
          });
        } else {
          _currentBrightness = _calculateBrightness(_currentTime).clamp(0.0, 1.0);
        }
      });
    });
  }

  double _calculateBrightness(double time) {
    if (widget.points.isEmpty) return 0;
    if (widget.points.length == 1) return widget.points[0].duty;
    
    // If we're at or past the last point's time, return its brightness
    final lastPoint = widget.points.reduce((a, b) => a.time > b.time ? a : b);
    if (time >= lastPoint.time) {
      return lastPoint.duty;
    }
    
    // Find the surrounding points
    var beforePoint = widget.points.last;
    var afterPoint = widget.points.first;
    
    for (int i = 0; i < widget.points.length; i++) {
      if (widget.points[i].time > time) {
        afterPoint = widget.points[i];
        beforePoint = i > 0 ? widget.points[i - 1] : widget.points.last;
        break;
      }
    }
    
    // Linear interpolation
    double timeDiff = afterPoint.time - beforePoint.time;
    if (timeDiff <= 0) {
      timeDiff += widget.maxDuration;
    }
    double progress = (time - beforePoint.time) / timeDiff;
    return beforePoint.duty + (afterPoint.duty - beforePoint.duty) * progress;
  }

  @override
  Widget build(BuildContext context) {
    final brightness = _currentBrightness.clamp(0.0, 1.0);
    return Container(
      width: 80,
      height: 80,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black,
          border: Border.all(
            color: const Color(0xFFFFD700), // Golden yellow
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF8C00).withOpacity((brightness * 0.7).clamp(0.0, 1.0)), // Dark orange
              blurRadius: 12,
              spreadRadius: 6,
            ),
            BoxShadow(
              color: const Color(0xFFFFD700).withOpacity((brightness * 0.5).clamp(0.0, 1.0)), // Golden yellow
              blurRadius: 6,
              spreadRadius: 3,
            ),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                Color.lerp(
                  const Color(0xFFFFD700), // Golden yellow
                  const Color(0xFFFF8C00), // Dark orange
                  1 - brightness
                )!.withOpacity(brightness),
                Colors.transparent,
              ],
              stops: const [0.7, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}

class _FadeEditorState extends State<FadeEditor> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _durationController = TextEditingController(text: '1000');
  final List<FadePoint> _points = [];
  int? _selectedPointIndex;
  double _maxDuration = 1000.0;
  Fade? _editingFade; // Track the fade being edited

  @override
  void initState() {
    super.initState();
    _durationController.addListener(_updateMaxDuration);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  void _updateMaxDuration() {
    final newDuration = double.tryParse(_durationController.text);
    if (newDuration != null && newDuration > 0) {
      setState(() {
        _maxDuration = newDuration;
        // Scale existing points to new duration if needed
        if (_points.isNotEmpty) {
          final oldMax = _points.map((p) => p.time).reduce(max);
          if (oldMax > _maxDuration) {
            final scale = _maxDuration / oldMax;
            for (var i = 0; i < _points.length; i++) {
              _points[i] = FadePoint(_points[i].time * scale, _points[i].duty);
            }
          }
        }
      });
    }
  }

  void _addPoint(double x, double y) {
    // Don't add a point if we're too close to an existing one
    for (var point in _points) {
      if ((point.time - x).abs() < _maxDuration * 0.01) {  // Scale minimum distance with duration
        return;
      }
    }

    setState(() {
      _points.add(FadePoint(x.clamp(0, _maxDuration), y.clamp(0, 1)));
      _points.sort((a, b) => a.time.compareTo(b.time));
    });
  }

  void _updatePoint(int index, double x, double y) {
    setState(() {
      _points[index] = FadePoint(x.clamp(0, _maxDuration), y.clamp(0, 1));
      _points.sort((a, b) => a.time.compareTo(b.time));
      // Update selected point index after sorting
      if (_selectedPointIndex == index) {
        _selectedPointIndex = _points.indexWhere((p) => p.time == x && p.duty == y);
      }
    });
  }

  void _removePoint(int index) {
    setState(() {
      _points.removeAt(index);
      if (_selectedPointIndex == index) {
        _selectedPointIndex = null;
      } else if (_selectedPointIndex != null && _selectedPointIndex! > index) {
        _selectedPointIndex = _selectedPointIndex! - 1;
      }
    });
  }

  void _resetEditor() {
    setState(() {
      _editingFade = null;
      _nameController.clear();
      _points.clear();
      _selectedPointIndex = null;
      _formKey.currentState?.reset(); // Reset validation state
    });
  }

  void _saveFade() {
    if (_formKey.currentState!.validate() && _points.isNotEmpty) {
      final state = context.read<DesignerState>();
      if (_editingFade != null) {
        // Update existing fade
        final updatedFade = Fade(
          name: _editingFade!.name, // Keep original internal name
          displayName: _nameController.text, // Use new display name
          points: List.from(_points),
          sampleRate: _editingFade!.sampleRate, // Preserve sample rate
        );
        state.updateFade(updatedFade);
      } else {
        // Add new fade
        final newFade = Fade(
          name: _nameController.text, // Will become displayName in addFade
          points: List.from(_points),
          // Default sampleRate is handled in Fade constructor
        );
        state.addFade(newFade);
      }
      _resetEditor(); // Reset editor after save/update
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DesignerState>();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left panel - Existing fades
        SizedBox(
          width: 250,
          child: Card(
            margin: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Saved Fades',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: state.fades.length,
                    itemBuilder: (context, index) {
                      final fade = state.fades[index];
                      return ListTile(
                        title: Text(fade.displayName),
                        subtitle: Text('${fade.points.length} points, ${fade.duration.toStringAsFixed(0)}ms'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () {
                                setState(() {
                                  _editingFade = fade; // Track the fade being edited
                                  _nameController.text = fade.displayName;
                                  _points.clear();
                                  _points.addAll(fade.points);
                                  _maxDuration = fade.duration;
                                  _durationController.text = _maxDuration.toString();
                                });
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () => context.read<DesignerState>().deleteFade(fade),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        // Right panel - Editor
        Expanded(
          child: Card(
            margin: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Form controls
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Form(
                    key: _formKey,
                    child: Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Fade Name',
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a name';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 120,
                          child: TextFormField(
                            controller: _durationController,
                            decoration: const InputDecoration(
                              labelText: 'Duration (ms)',
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Required';
                              }
                              final duration = double.tryParse(value);
                              if (duration == null || duration <= 0) {
                                return 'Invalid duration';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Chart and Preview
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Chart
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(
                              child: _buildChart(),
                            ),
                            const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text('Click to add points, drag to move them'),
                            ),
                          ],
                        ),
                      ),
                      // LED Preview
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'LED Preview',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            LedPreview(
                              points: _points,
                              maxDuration: _maxDuration,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Action buttons
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _resetEditor,
                        child: const Text('Clear'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _saveFade,
                        child: const Text('Save Fade'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChart() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fixed padding values that match the chart's internal padding
        // Adjusted these values slightly to potentially fix hitbox offset
        const double leftPadding = 44.0; // Was 40.0
        const double rightPadding = 5.0; // Was 8.0
        const double topPadding = 5.0; // Was 12.0
        const double bottomPadding = 24.0; // Was 20.0

        // Calculate the actual plotting area dimensions
        final plotWidth = constraints.maxWidth - leftPadding - rightPadding;
        final plotHeight = constraints.maxHeight - topPadding - bottomPadding;

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (details) {
            final localPosition = details.localPosition;
            // Only handle clicks within the plotting area
            if (localPosition.dx >= leftPadding && 
                localPosition.dx <= constraints.maxWidth - rightPadding &&
                localPosition.dy >= topPadding &&
                localPosition.dy <= constraints.maxHeight - bottomPadding) {
              
              final x = ((localPosition.dx - leftPadding) / plotWidth * _maxDuration).clamp(0.0, _maxDuration);
              final y = (1.0 - (localPosition.dy - topPadding) / plotHeight).clamp(0.0, 1.0);
              _addPoint(x, y);
            }
          },
          onPanStart: (details) {
            final localPosition = details.localPosition;
            if (localPosition.dx < leftPadding || 
                localPosition.dx > constraints.maxWidth - rightPadding ||
                localPosition.dy < topPadding ||
                localPosition.dy > constraints.maxHeight - bottomPadding) {
              return;
            }

            final x = ((localPosition.dx - leftPadding) / plotWidth * _maxDuration).clamp(0.0, _maxDuration);
            final y = (1.0 - (localPosition.dy - topPadding) / plotHeight).clamp(0.0, 1.0);
            
            // Find the nearest point
            double minDistance = double.infinity;
            int? nearestIndex;
            
            for (var i = 0; i < _points.length; i++) {
              final point = _points[i];
              // Convert point coordinates to pixels
              final pointX = point.time / _maxDuration * plotWidth + leftPadding;
              final pointY = (1.0 - point.duty) * plotHeight + topPadding;
              
              final dx = pointX - localPosition.dx;
              final dy = pointY - localPosition.dy;
              final distance = dx * dx + dy * dy;
              
              if (distance < minDistance && distance < 900) { // 30 pixel radius
                minDistance = distance;
                nearestIndex = i;
              }
            }
            
            setState(() {
              _selectedPointIndex = nearestIndex;
            });
          },
          onPanUpdate: (details) {
            if (_selectedPointIndex != null) {
              final localPosition = details.localPosition;
              final x = ((localPosition.dx - leftPadding) / plotWidth * _maxDuration).clamp(0.0, _maxDuration);
              final y = (1.0 - (localPosition.dy - topPadding) / plotHeight).clamp(0.0, 1.0);
              _updatePoint(_selectedPointIndex!, x, y);
            }
          },
          child: SizedBox.expand(
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: _maxDuration,
                minY: 0,
                maxY: 1,
                gridData: FlGridData(show: true),
                borderData: FlBorderData(show: true),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    axisNameWidget: const Text('Time (ms)'),
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        return Text(value.toInt().toString());
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    axisNameWidget: const Text('Duty Cycle'),
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        return Text(value.toStringAsFixed(1));
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: _points
                        .map((p) => FlSpot(p.time, p.duty))
                        .toList(),
                    isCurved: true,
                    curveSmoothness: 0.3,
                    preventCurveOverShooting: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) {
                        final isSelected = index == _selectedPointIndex;
                        return FlDotCirclePainter(
                          radius: isSelected ? 8 : 6,
                          color: isSelected ? Colors.red : Colors.blue,
                          strokeWidth: isSelected ? 3 : 2,
                          strokeColor: isSelected ? Colors.red.shade800 : Colors.blue.shade800,
                        );
                      },
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(enabled: false),
              ),
            ),
          ),
        );
      },
    );
  }
}