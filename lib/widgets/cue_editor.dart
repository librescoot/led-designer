import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/cue.dart';
import '../providers/designer_state.dart';

class CueEditor extends StatefulWidget {
  const CueEditor({super.key});

  @override
  State<CueEditor> createState() => _CueEditorState();
}

class _CueEditorState extends State<CueEditor> {
  final List<CueAction> _actions = [];
  int _selectedLedIndex = 0;
  Cue? _editingCue;

  void _addFadeAction(int fadeIndex) {
    setState(() {
      _actions.add(CueAction(
        ledIndex: _selectedLedIndex,
        type: CueActionType.fade,
        value: fadeIndex,
      ));
    });
  }

  void _addDutyAction(double duty) {
    setState(() {
      _actions.add(CueAction(
        ledIndex: _selectedLedIndex,
        type: CueActionType.duty,
        value: duty,
      ));
    });
  }

  void _removeAction(int index) {
    setState(() {
      _actions.removeAt(index);
    });
  }

  void _startEditingCue(Cue cue) {
    setState(() {
      _editingCue = cue;
      _actions.clear();
      _actions.addAll(cue.actions);
    });
  }

  void _saveCueChanges() {
    if (_editingCue != null) {
      final updatedCue = Cue(
        name: _editingCue!.name,
        actions: List.from(_actions),
        cueIndex: _editingCue!.cueIndex,
      );
      context.read<DesignerState>().updateCue(updatedCue);
      setState(() {
        _editingCue = null;
        _actions.clear();
      });
    }
  }

  void _cancelEditing() {
    setState(() {
      _editingCue = null;
      _actions.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DesignerState>();

    return Row(
      children: [
        // Left panel - Existing cues
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
                    'Cues',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: state.cues.length,
                    itemBuilder: (context, index) {
                      final cue = state.cues[index];
                      final isEditing = _editingCue?.name == cue.name;
                      return ListTile(
                        title: Text(cue.name),
                        subtitle: Text('${cue.actions.length} actions'),
                        selected: isEditing,
                        trailing: IconButton(
                          icon: Icon(isEditing ? Icons.edit_off : Icons.edit),
                          onPressed: () => isEditing ? _cancelEditing() : _startEditingCue(cue),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        // Right panel - Cue editor
        Expanded(
          child: _editingCue == null
              ? const Center(child: Text('Select a cue to edit'))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        children: [
                          Text(
                            'Editing: ${_editingCue!.name}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: _cancelEditing,
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _saveCueChanges,
                            child: const Text('Save Changes'),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        children: [
                          const Text('LED Index:'),
                          const SizedBox(width: 8),
                          DropdownButton<int>(
                            value: _selectedLedIndex,
                            items: const [
                              DropdownMenuItem(value: 0, child: Text('0: Headlight')),
                              DropdownMenuItem(value: 1, child: Text('1: Front ring')),
                              DropdownMenuItem(value: 2, child: Text('2: Brake light')),
                              DropdownMenuItem(value: 3, child: Text('3: Blinker front left')),
                              DropdownMenuItem(value: 4, child: Text('4: Blinker front right')),
                              DropdownMenuItem(value: 5, child: Text('5: Number plates')),
                              DropdownMenuItem(value: 6, child: Text('6: Blinker rear left')),
                              DropdownMenuItem(value: 7, child: Text('7: Blinker rear right')),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _selectedLedIndex = value);
                              }
                            },
                          ),
                          const Spacer(),
                          PopupMenuButton<int>(
                            child: const Chip(
                              avatar: Icon(Icons.lightbulb),
                              label: Text('Add Fade'),
                            ),
                            itemBuilder: (context) {
                              return state.fades.asMap().entries.map((entry) {
                                return PopupMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value.displayName),
                                );
                              }).toList();
                            },
                            onSelected: _addFadeAction,
                          ),
                          const SizedBox(width: 8),
                          PopupMenuButton<int>(
                            child: const Chip(
                              avatar: Icon(Icons.brightness_medium),
                              label: Text('Add Duty'),
                            ),
                            itemBuilder: (context) {
                              return [0, 25, 50, 75, 100].map((duty) {
                                return PopupMenuItem(
                                  value: duty,
                                  child: Text('$duty%'),
                                );
                              }).toList();
                            },
                            onSelected: (duty) {
                              _addDutyAction((duty / 100.0) as double);
                            },
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _actions.length,
                        itemBuilder: (context, index) {
                          final action = _actions[index];
                          String ledName = '';
                          switch (action.ledIndex) {
                            case 0: ledName = 'Headlight'; break;
                            case 1: ledName = 'Front ring'; break;
                            case 2: ledName = 'Brake light'; break;
                            case 3: ledName = 'Blinker front left'; break;
                            case 4: ledName = 'Blinker front right'; break;
                            case 5: ledName = 'Number plates'; break;
                            case 6: ledName = 'Blinker rear left'; break;
                            case 7: ledName = 'Blinker rear right'; break;
                          }

                          return ListTile(
                            leading: Icon(
                              action.type == CueActionType.fade
                                  ? Icons.timeline
                                  : Icons.brightness_medium,
                            ),
                            title: Text(
                              action.type == CueActionType.fade
                                  ? 'Play Fade: ${state.fades[action.value].displayName}'
                                  : 'Set Duty: ${(action.value * 100).round()}%',
                            ),
                            subtitle: Text('LED ${action.ledIndex}: $ledName'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () => _removeAction(index),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
} 