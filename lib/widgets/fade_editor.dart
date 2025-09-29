import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';
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
  final _pointXController = TextEditingController();
  final _pointYController = TextEditingController();
  final List<FadePoint> _points = [];
  int? _selectedPointIndex;
  double _maxDuration = 1000.0;
  Fade? _editingFade; // Track the fade being edited
  CurveType _curveType = CurveType.linear; // Current curve type
  bool _useLogScale = false; // Use logarithmic scale

  @override
  void initState() {
    super.initState();
    // Removed continuous listener - duration updates only on blur/enter
  }

  @override
  void dispose() {
    _nameController.dispose();
    _durationController.dispose();
    _pointXController.dispose();
    _pointYController.dispose();
    super.dispose();
  }

  void _handleDurationUpdate() {
    final newDuration = double.tryParse(_durationController.text);
    if (newDuration != null && newDuration > 0 && newDuration != _maxDuration) {
      setState(() {
        // Rescale all existing points proportionally
        if (_points.isNotEmpty) {
          final oldDuration = _maxDuration;
          final scale = newDuration / oldDuration;
          for (var i = 0; i < _points.length; i++) {
            _points[i] = FadePoint(_points[i].time * scale, _points[i].duty);
          }
        }
        _maxDuration = newDuration;
        _updatePointValueControllers(); // Update if a point is selected
      });
    }
  }

  void _updatePointValueControllers() {
    if (_selectedPointIndex != null && _selectedPointIndex! < _points.length) {
      final point = _points[_selectedPointIndex!];
      _pointXController.text = point.time.toStringAsFixed(1);
      _pointYController.text = (point.duty * 100).toStringAsFixed(1);
    } else {
      _pointXController.clear();
      _pointYController.clear();
    }
  }

  void _handlePointValueUpdate() {
    if (_selectedPointIndex == null) return;

    final newX = double.tryParse(_pointXController.text);
    final newY = double.tryParse(_pointYController.text);

    if (newX != null && newY != null && newX >= 0 && newX <= _maxDuration && newY >= 0 && newY <= 100) {
      setState(() {
        _points[_selectedPointIndex!] = FadePoint(newX, newY / 100.0);
        _points.sort((a, b) => a.time.compareTo(b.time));
        // Update selected index after sorting
        _selectedPointIndex = _points.indexWhere((p) => p.time == newX && p.duty == (newY / 100.0));
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

    // Convert y back from log scale if needed
    final actualY = _transformFromLog(y);

    setState(() {
      _points.add(FadePoint(x.clamp(0, _maxDuration), actualY.clamp(0, 1)));
      _points.sort((a, b) => a.time.compareTo(b.time));
    });
  }

  void _updatePoint(int index, double x, double y) {
    // Convert y back from log scale if needed
    final actualY = _transformFromLog(y);

    setState(() {
      _points[index] = FadePoint(x.clamp(0, _maxDuration), actualY.clamp(0, 1));
      _points.sort((a, b) => a.time.compareTo(b.time));
      // Update selected point index after sorting
      if (_selectedPointIndex == index) {
        _selectedPointIndex = _points.indexWhere((p) => p.time == x && p.duty == actualY);
      }
      _updatePointValueControllers();
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
      _updatePointValueControllers();
    });
  }

  void _showPointContextMenu(BuildContext context, Offset globalPosition, int pointIndex) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: [
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.delete, size: 18),
              SizedBox(width: 8),
              Text('Delete Point'),
            ],
          ),
          onTap: () => _removePoint(pointIndex),
        ),
      ],
    );
  }

  void _resetEditor() {
    setState(() {
      _editingFade = null;
      _nameController.clear();
      _points.clear();
      _selectedPointIndex = null;
      _curveType = CurveType.linear;
      _formKey.currentState?.reset();
      _updatePointValueControllers();
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
          curveType: _curveType,
        );
        state.updateFade(updatedFade);
        // Update the editing fade reference with the new fade
        _editingFade = updatedFade;
      } else {
        // Add new fade
        final newFade = Fade(
          name: _nameController.text, // Will become displayName in addFade
          points: List.from(_points),
          curveType: _curveType,
          // Default sampleRate is handled in Fade constructor
        );
        state.addFade(newFade);
        // Set the editing fade to the new fade so it can be updated in future saves
        _editingFade = newFade;
      }
      // Don't reset editor after save - keep current state
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
                                  _curveType = fade.curveType; // Load curve type
                                  _selectedPointIndex = null; // Clear selection
                                  _updatePointValueControllers(); // Clear point value fields
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
                          child: Focus(
                            onFocusChange: (hasFocus) {
                              if (!hasFocus) {
                                _handleDurationUpdate();
                              }
                            },
                            child: TextFormField(
                              controller: _durationController,
                              decoration: const InputDecoration(
                                labelText: 'Duration (ms)',
                              ),
                              keyboardType: TextInputType.number,
                              onFieldSubmitted: (_) => _handleDurationUpdate(),
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
                        ),
                        const SizedBox(width: 16),
                        Row(
                          children: [
                            Checkbox(
                              value: _curveType == CurveType.bezier,
                              onChanged: (value) {
                                setState(() {
                                  _curveType = value == true ? CurveType.bezier : CurveType.linear;
                                });
                              },
                            ),
                            const Text('Bézier Curves'),
                          ],
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Checkbox(
                            value: _useLogScale,
                            onChanged: (value) {
                              setState(() {
                                _useLogScale = value == true;
                              });
                            },
                          ),
                          const Text('Log Scale'),
                          // Point value fields (only show when point is selected)
                          if (_selectedPointIndex != null) ...[
                            const SizedBox(width: 32),
                            const Text('Selected Point:'),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 100,
                              child: Focus(
                                onFocusChange: (hasFocus) {
                                  if (!hasFocus) {
                                    _handlePointValueUpdate();
                                  }
                                },
                                child: TextFormField(
                                  controller: _pointXController,
                                  decoration: const InputDecoration(
                                    labelText: 'Time (ms)',
                                    isDense: true,
                                  ),
                                  keyboardType: TextInputType.number,
                                  onFieldSubmitted: (_) => _handlePointValueUpdate(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 80,
                              child: Focus(
                                onFocusChange: (hasFocus) {
                                  if (!hasFocus) {
                                    _handlePointValueUpdate();
                                  }
                                },
                                child: TextFormField(
                                  controller: _pointYController,
                                  decoration: const InputDecoration(
                                    labelText: 'Duty %',
                                    isDense: true,
                                  ),
                                  keyboardType: TextInputType.number,
                                  onFieldSubmitted: (_) => _handlePointValueUpdate(),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Row(
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

  /// Transform value to logarithmic scale for display
  double _transformToLog(double value) {
    if (!_useLogScale) return value;
    // Use log10 for easier reading, map [0.001, 1.0] to [0.0, 1.0]
    const minValue = 0.001;
    const maxValue = 1.0;

    // Clamp the value to avoid log(0)
    double clampedValue = value.clamp(minValue, maxValue);

    // Transform to log scale: log10(minValue) to log10(maxValue) => -3 to 0
    double logValue = log(clampedValue) / ln10; // log10
    double logMin = log(minValue) / ln10; // -3
    double logMax = log(maxValue) / ln10; // 0

    // Normalize to 0-1 range
    return (logValue - logMin) / (logMax - logMin);
  }

  /// Transform value back from logarithmic scale
  double _transformFromLog(double normalizedLogValue) {
    if (!_useLogScale) return normalizedLogValue;

    const minValue = 0.001;
    const maxValue = 1.0;

    double logMin = log(minValue) / ln10; // -3
    double logMax = log(maxValue) / ln10; // 0

    // Convert back from normalized to log value
    double logValue = logMin + normalizedLogValue * (logMax - logMin);

    // Convert back to linear
    return pow(10, logValue).toDouble();
  }

  /// Get the Y-axis label values that fl_chart would display
  List<double> _getYAxisLabels() {
    if (!_useLogScale) {
      // For linear scale, fl_chart typically shows labels at 0.1 intervals
      return [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
          .map((v) => v)
          .toList();
    } else {
      // For log scale, we need to determine where fl_chart would place labels
      // Based on the chart's internal logic and our log transformation
      final labels = <double>[];

      // Add labels at key percentage points transformed to log scale
      final keyPercentages = [0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0];

      for (final percentage in keyPercentages) {
        final linearValue = percentage / 100.0;
        if (linearValue >= 0.001 && linearValue <= 1.0) {
          final logValue = _transformToLog(linearValue);
          labels.add(logValue);
        }
      }

      return labels..sort();
    }
  }

  Widget _buildChart() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fixed padding values that match the chart's internal padding
        const double leftPadding = 82.0;
        const double rightPadding = 2.0;
        const double topPadding = 2.0;
        const double bottomPadding = 24.0;

        // Calculate the actual plotting area dimensions
        final plotWidth = constraints.maxWidth - leftPadding - rightPadding;
        final plotHeight = constraints.maxHeight - topPadding - bottomPadding;

        return Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent && _selectedPointIndex != null) {
              if (event.logicalKey == LogicalKeyboardKey.delete ||
                  event.logicalKey == LogicalKeyboardKey.backspace) {
                _removePoint(_selectedPointIndex!);
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
          onTapDown: (details) {
            final localPosition = details.localPosition;
            // Only handle clicks within the plotting area
            if (localPosition.dx >= leftPadding &&
                localPosition.dx <= constraints.maxWidth - rightPadding &&
                localPosition.dy >= topPadding &&
                localPosition.dy <= constraints.maxHeight - bottomPadding) {

              // First check if we're clicking near an existing point
              double minDistance = double.infinity;
              int? nearestIndex;

              for (var i = 0; i < _points.length; i++) {
                final point = _points[i];
                // Convert point coordinates to pixels
                final pointX = point.time / _maxDuration * plotWidth + leftPadding;
                final transformedDuty = _transformToLog(point.duty);
                final pointY = (1.0 - transformedDuty) * plotHeight + topPadding;

                final dx = pointX - localPosition.dx;
                final dy = pointY - localPosition.dy;
                final distance = dx * dx + dy * dy;

                if (distance < minDistance && distance < 900) { // 30 pixel radius
                  minDistance = distance;
                  nearestIndex = i;
                }
              }

              if (nearestIndex != null) {
                // Select the existing point
                setState(() {
                  _selectedPointIndex = nearestIndex;
                  _updatePointValueControllers();
                });
              } else {
                // Add a new point
                final x = ((localPosition.dx - leftPadding) / plotWidth * _maxDuration).clamp(0.0, _maxDuration);
                final y = (1.0 - (localPosition.dy - topPadding) / plotHeight).clamp(0.0, 1.0);
                _addPoint(x, y);
              }
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

            // Find the nearest point
            double minDistance = double.infinity;
            int? nearestIndex;
            
            for (var i = 0; i < _points.length; i++) {
              final point = _points[i];
              // Convert point coordinates to pixels
              final pointX = point.time / _maxDuration * plotWidth + leftPadding;
              final transformedDuty = _transformToLog(point.duty);
              final pointY = (1.0 - transformedDuty) * plotHeight + topPadding;
              
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
              _updatePointValueControllers();
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
          onSecondaryTapDown: (details) {
            final localPosition = details.localPosition;
            if (localPosition.dx < leftPadding ||
                localPosition.dx > constraints.maxWidth - rightPadding ||
                localPosition.dy < topPadding ||
                localPosition.dy > constraints.maxHeight - bottomPadding) {
              return;
            }

            // Find the nearest point for right-click deletion
            double minDistance = double.infinity;
            int? nearestIndex;

            for (var i = 0; i < _points.length; i++) {
              final point = _points[i];
              // Convert point coordinates to pixels
              final pointX = point.time / _maxDuration * plotWidth + leftPadding;
              final transformedDuty = _transformToLog(point.duty);
              final pointY = (1.0 - transformedDuty) * plotHeight + topPadding;

              final dx = pointX - localPosition.dx;
              final dy = pointY - localPosition.dy;
              final distance = dx * dx + dy * dy;

              if (distance < 900) { // 30 pixel radius
                if (distance < minDistance) {
                  minDistance = distance;
                  nearestIndex = i;
                }
              }
            }

            if (nearestIndex != null) {
              // Show context menu
              _showPointContextMenu(context, details.globalPosition, nearestIndex);
            }
          },
          child: SizedBox.expand(
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: _maxDuration,
                minY: 0,
                maxY: 1,
                gridData: _useLogScale ? FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  drawHorizontalLine: true,
                  horizontalInterval: 0.01,
                  checkToShowHorizontalLine: (value) {
                    // Get the Y-axis labels that would be shown by fl_chart
                    final yLabels = _getYAxisLabels();

                    // Check if this value corresponds to a Y-axis label (major grid line)
                    for (final labelValue in yLabels) {
                      if ((value - labelValue).abs() < 0.001) {
                        return true; // Show major grid line
                      }

                      // Check for minor grid lines (5 evenly spaced lines between each pair of labels)
                      final nextLabel = yLabels.where((l) => l > labelValue).isNotEmpty
                        ? yLabels.where((l) => l > labelValue).reduce((a, b) => a < b ? a : b)
                        : null;

                      if (nextLabel != null) {
                        final step = (nextLabel - labelValue) / 6; // 5 minor lines + 1 gap
                        for (int i = 1; i <= 5; i++) {
                          final minorValue = labelValue + (step * i);
                          if ((value - minorValue).abs() < 0.001) {
                            return true; // Show minor grid line
                          }
                        }
                      }
                    }

                    return false;
                  },
                  getDrawingHorizontalLine: (value) {
                    // Determine if this is a major or minor line
                    final yLabels = _getYAxisLabels();
                    final isMajorLine = yLabels.any((labelValue) => (value - labelValue).abs() < 0.001);

                    return FlLine(
                      color: isMajorLine ? Colors.grey.shade600 : Colors.grey.shade400,
                      strokeWidth: isMajorLine ? 1.0 : 0.5,
                    );
                  },
                ) : FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: 0.1,
                ),
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
                    axisNameWidget: Text(_useLogScale ? 'Duty Cycle % (Log)' : 'Duty Cycle %'),
                    axisNameSize: 32,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      getTitlesWidget: (value, meta) {
                        if (_useLogScale) {
                          // Convert back to linear value for display as percentage
                          final linearValue = _transformFromLog(value);
                          return Padding(
                            padding: const EdgeInsets.only(right: 4.0),
                            child: Text('${linearValue < .13 ? (linearValue * 100).toStringAsFixed(1) : (linearValue * 100).toStringAsFixed(0)}%', textAlign: TextAlign.right),
                          );
                        } else {
                          return Padding(
                            padding: const EdgeInsets.only(right: 4.0),
                            child: Text('${(value * 100).toInt()}%', textAlign: TextAlign.right),
                          );
                        }
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: _points
                        .map((p) => FlSpot(p.time, _transformToLog(p.duty)))
                        .toList(),
                    isCurved: _curveType == CurveType.bezier,
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
        ),
        );
      },
    );
  }
}