import 'package:flutter/material.dart';

class VoiceOption {
  const VoiceOption({
    required this.id,
    required this.name,
    required this.category,
  });

  final String id;
  final String name;
  final String category;
}

class VoicePickerDialog extends StatefulWidget {
  const VoicePickerDialog({
    super.key,
    required this.onGenerate,
  });

  final void Function(VoiceOption selectedVoice, String text) onGenerate;

  @override
  State<VoicePickerDialog> createState() => _VoicePickerDialogState();
}

class _VoicePickerDialogState extends State<VoicePickerDialog> {
  final TextEditingController _textController = TextEditingController();

  final List<VoiceOption> _voices = const [
    VoiceOption(
      id: '21m00Tcm4TlvDq8ikWAM',
      name: 'Rachel (Narrative)',
      category: 'Natural',
    ),
    VoiceOption(
      id: 'AZnzlk1XvdvUeBnXmlld',
      name: 'Domi (Energetic)',
      category: 'Vlog',
    ),
    VoiceOption(
      id: 'EXAVITQu4vr4xnSDxMaL',
      name: 'Bella (Soft)',
      category: 'Storytelling',
    ),
  ];

  late VoiceOption _selectedVoice;

  @override
  void initState() {
    super.initState();
    _selectedVoice = _voices.first;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _textController.text.trim().isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: const [
                    Icon(Icons.record_voice_over, color: Colors.deepPurpleAccent),
                    SizedBox(width: 10),
                    Text(
                      'AI SPEECH',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Select a voice and write a script for the generated track.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _textController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Enter text to convert to voice...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.deepPurpleAccent),
                    ),
                  ),
                  maxLines: 4,
                  minLines: 2,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                Text(
                  'Voice style',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 46,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _voices.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final voice = _voices[index];
                      final isSelected = voice.id == _selectedVoice.id;

                      return ChoiceChip(
                        label: Text(voice.name),
                        selected: isSelected,
                        selectedColor: Colors.deepPurpleAccent,
                        backgroundColor: Colors.white10,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                        ),
                        onSelected: (_) {
                          setState(() => _selectedVoice = voice);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Selected voice',
                        style: TextStyle(color: Colors.white70),
                      ),
                      Expanded(
                        child: Text(
                          '${_selectedVoice.name} • ${_selectedVoice.category}',
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Generate AI VoiceTrack'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurpleAccent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: hasText
                      ? () {
                          final text = _textController.text.trim();
                          widget.onGenerate(_selectedVoice, text);
                        }
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
