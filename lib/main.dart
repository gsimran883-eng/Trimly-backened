import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';

import 'media_loader.dart';
import 'screens/home_screen.dart';
import 'screens/editor_screen.dart';
import 'services/monetization_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MonetizationService.instance.initialize();
  runApp(const ClipSnapApp());
}

Future<Uint8List?> readPickedBytes(PlatformFile file) async {
  if (file.bytes != null) {
    return file.bytes;
  }

  final path = file.path;
  if (path == null || path.isEmpty) {
    return null;
  }

  try {
    return File(path).readAsBytes();
  } catch (_) {
    return null;
  }
}

class EditorHomePage extends StatefulWidget {
  final int initialIndex;

  const EditorHomePage({super.key, this.initialIndex = 0});

  @override
  State<EditorHomePage> createState() => _EditorHomePageState();
}

class _EditorHomePageState extends State<EditorHomePage> {
  String _activeTool = 'Adjust';

  void _selectTool(String tool) {
    setState(() => _activeTool = tool);
  }

  @override
  Widget build(BuildContext context) {
    final toolTitle = switch (_activeTool) {
      'Text' => 'Text Overlay',
      'Stickers' => 'Sticker Pack',
      'Adjust' => 'Active: Adjust',
      _ => _activeTool,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('ClipSnap')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Import Media',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                ActionChip(
                  label: const Text('Adjust'),
                  onPressed: () => _selectTool('Adjust'),
                ),
                ActionChip(
                  label: const Text('Filters'),
                  onPressed: () => _selectTool('Filters'),
                ),
                ActionChip(
                  key: const ValueKey('tool-text'),
                  label: const Text('Text'),
                  onPressed: () => _selectTool('Text'),
                ),
                ActionChip(
                  key: const ValueKey('tool-stickers'),
                  label: const Text('Stickers'),
                  onPressed: () => _selectTool('Stickers'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              toolTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class ClipSnapApp extends StatelessWidget {
  const ClipSnapApp({super.key});

  @override
  Widget build(BuildContext context) {
    const accentStart = Color(0xFF3E56FF);
    const accentEnd = Color(0xFF47C8FF);
    final textTheme = GoogleFonts.plusJakartaSansTextTheme(
      ThemeData.dark(useMaterial3: true).textTheme,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ClipSnap',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accentStart,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF000000),
        textTheme: textTheme.copyWith(
          titleLarge: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: Colors.white,
          ),
          titleMedium: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          bodyMedium: textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w400,
            color: Colors.white,
          ),
          bodySmall: textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w300,
            color: Color(0xFF8A94A6),
          ),
          labelMedium: textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: Color(0xFF8A94A6),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        iconTheme: const IconThemeData(color: accentEnd),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xEB1E2230),
          elevation: 10,
          insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 84),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
          actionTextColor: accentEnd,
        ),
      ),
      routes: {
        '/editor': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          final launchConfig = args is ClipSnapEditorLaunchConfig
              ? args
              : const ClipSnapEditorLaunchConfig();

          return ClipSnapVideoEditor(
            initialMode: launchConfig.mode,
            autoOpenPicker: launchConfig.autoOpenPicker,
            initialAspectRatio: launchConfig.aspectRatio,
            initialWorkflow: launchConfig.workflow,
            initialAiTool: launchConfig.initialAiTool,
            initialAiConfig: launchConfig.initialAiConfig,
            initialVideoFile: launchConfig.initialVideoFile,
            launchSource: launchConfig.source,
          );
        },
      },
      home: const HomeScreen(),
    );
  }
}
