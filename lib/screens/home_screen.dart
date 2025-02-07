import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/designer_state.dart';
import '../widgets/fade_editor.dart';
import '../widgets/cue_editor.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _saveProject(BuildContext context) async {
    try {
      final state = context.read<DesignerState>();
      final json = jsonEncode(state.toJson());
      
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save LED Project',
        fileName: 'led_project.json',
      );

      if (outputFile != null) {
        await File(outputFile).writeAsString(json);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Project saved successfully')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving project: $e')),
        );
      }
    }
  }

  Future<void> _loadProject(BuildContext context) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Load LED Project',
        allowedExtensions: ['json'],
        type: FileType.custom,
      );

      if (result != null) {
        final file = File(result.files.single.path!);
        final json = await file.readAsString();
        final data = jsonDecode(json) as Map<String, dynamic>;
        
        context.read<DesignerState>().loadFromJson(data);
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Project loaded successfully')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading project: $e')),
        );
      }
    }
  }

  Future<void> _exportProject(BuildContext context) async {
    try {
      String? outputDir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Export LED Project',
      );

      if (outputDir != null) {
        final state = context.read<DesignerState>();
        await state.exportAll(outputDir);
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Project exported successfully')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting project: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('LED Designer'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Fades', icon: Icon(Icons.timeline)),
              Tab(text: 'Cues', icon: Icon(Icons.playlist_play)),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: () => _saveProject(context),
            ),
            IconButton(
              icon: const Icon(Icons.folder_open),
              onPressed: () => _loadProject(context),
            ),
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: () => _exportProject(context),
            ),
          ],
        ),
        body: TabBarView(
          children: [
            FadeEditor(),
            CueEditor(),
          ],
        ),
      ),
    );
  }
} 
