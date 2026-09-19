class BRollSuggestion {
  final String keyword;
  final String category;
  final int startMs;
  final String stockQuery;
  final String overlayPrompt;

  const BRollSuggestion({
    required this.keyword,
    required this.category,
    required this.startMs,
    required this.stockQuery,
    required this.overlayPrompt,
  });
}

class BRollSuggester {
  static const Map<String, List<String>> _categoryKeywords = {
    'Coffee': ['coffee', 'cafe', 'latte', 'espresso', 'brew'],
    'Gaming': ['game', 'gaming', 'stream', 'victory', 'rank', 'boss', 'clip'],
    'Money': ['money', 'cash', 'profit', 'earn', 'revenue', 'income', 'sales'],
    'Travel': ['travel', 'airport', 'flight', 'hotel', 'beach', 'road', 'trip'],
    'Fitness': ['gym', 'workout', 'fitness', 'run', 'training', 'lift'],
    'Food': ['food', 'cook', 'recipe', 'meal', 'eat', 'restaurant', 'snack'],
    'Tech': ['phone', 'camera', 'laptop', 'app', 'ai', 'software', 'edit'],
    'Vlog': ['morning', 'day', 'walk', 'talk', 'story', 'life', 'vlog'],
  };

  static const Set<String> _stopWords = {
    'the', 'and', 'for', 'with', 'that', 'this', 'from', 'your', 'you', 'are',
    'but', 'not', 'was', 'were', 'have', 'has', 'had', 'about', 'just', 'like',
    'really', 'very', 'yeah', 'okay', 'umm', 'um', 'uh', 'i', 'me',
    'my', 'we', 'our', 'they', 'them', 'his', 'her', 'its', 'at', 'to', 'of',
    'in', 'on', 'it', 'is', 'as', 'be', 'by', 'an', 'a', 'or', 'so', 'if',
  };

  List<BRollSuggestion> suggestFromTranscript(List<Map<String, dynamic>> transcriptLayers) {
    final suggestions = <BRollSuggestion>[];
    final seen = <String>{};

    for (final layer in transcriptLayers) {
      final text = (layer['text'] as String? ?? '').toLowerCase();
      final startMs = layer['startMs'] as int? ?? 0;
      final tokens = text
          .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
          .split(RegExp(r'\s+'))
          .where((token) => token.isNotEmpty && !_stopWords.contains(token))
          .toList();

      for (final categoryEntry in _categoryKeywords.entries) {
        for (final keyword in categoryEntry.value) {
          if (!text.contains(keyword)) {
            continue;
          }
          if (!seen.add('$keyword@$startMs')) {
            continue;
          }
          suggestions.add(
            BRollSuggestion(
              keyword: keyword,
              category: categoryEntry.key,
              startMs: startMs,
              stockQuery: '$keyword b-roll',
              overlayPrompt: 'Generate a ${categoryEntry.key.toLowerCase()} sticker or stock clip for "$keyword"',
            ),
          );
        }
      }

      if (tokens.isNotEmpty) {
        final keyword = tokens.first;
        if (seen.add('$keyword@$startMs')) {
          suggestions.add(
            BRollSuggestion(
              keyword: keyword,
              category: 'Keyword',
              startMs: startMs,
              stockQuery: '$keyword b-roll',
              overlayPrompt: 'Suggest matching b-roll for "$keyword"',
            ),
          );
        }
      }
    }

    return suggestions.take(12).toList();
  }
}
