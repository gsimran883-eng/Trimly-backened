import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/template_model.dart';

class CustomTemplateCard extends StatefulWidget {
  final VideoTemplate template;
  final VoidCallback onTap;

  const CustomTemplateCard({
    super.key,
    required this.template,
    required this.onTap,
  });

  @override
  State<CustomTemplateCard> createState() => _CustomTemplateCardState();
}

class _CustomTemplateCardState extends State<CustomTemplateCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motionController;

  @override
  void initState() {
    super.initState();
    _motionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat();
  }

  @override
  void dispose() {
    _motionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCyberpunkTokyo = widget.template.id == 'cyberpunk_tokyo';
    final accent =
        widget.template.isPremium ? Colors.amberAccent : Colors.cyanAccent;
    final cardAccent = isCyberpunkTokyo ? const Color(0xFF67E8F9) : accent;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isCyberpunkTokyo
                ? [
                    const Color(0xFF0F172A).withValues(alpha: 0.92),
                    const Color(0xFF1E1B4B).withValues(alpha: 0.88),
                  ]
                : [
                    Colors.cyan.withValues(alpha: 0.15),
                    Colors.purple.withValues(alpha: 0.05),
                  ],
          ),
          border: Border.all(
            color: cardAccent.withValues(alpha: isCyberpunkTokyo ? 0.9 : 0.5),
            width: isCyberpunkTokyo ? 2.2 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: cardAccent.withValues(alpha: isCyberpunkTokyo ? 0.32 : 0.1),
              blurRadius: isCyberpunkTokyo ? 18 : 12,
              spreadRadius: isCyberpunkTokyo ? 3 : 2,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedBuilder(
              animation: _motionController,
              builder: (context, child) {
                final progress = _motionController.value;
                final scale =
                    1.02 + (progress < 0.5 ? progress : 1 - progress) * 0.045;
                final horizontalShift = (progress - 0.5) * 8;
                return ClipRect(
                  child: Transform.translate(
                    offset: Offset(horizontalShift, 0),
                    child: Transform.scale(scale: scale, child: child),
                  ),
                );
              },
              child: _buildPreview(),
            ),
            AnimatedBuilder(
              animation: _motionController,
              builder: (context, child) {
                final scanlinePosition =
                    -0.35 + (_motionController.value * 1.7);
                return FractionalTranslation(
                  translation: Offset(0, scanlinePosition),
                  child: child,
                );
              },
              child: IgnorePointer(
                child: FractionallySizedBox(
                  heightFactor: 0.22,
                  alignment: Alignment.topCenter,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          accent.withValues(alpha: 0.14),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.1),
                    Colors.black.withValues(alpha: 0.7),
                    Colors.black.withValues(alpha: 0.95),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.cyanAccent.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            widget.template.badgeText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                      if (widget.template.isPremium) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.amberAccent,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.amber.withValues(alpha: 0.5),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.lock_rounded,
                            size: 10,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.template.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.template.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (widget.template.previewImagePath.toLowerCase().endsWith('.svg')) {
      return SvgPicture.asset(
        widget.template.previewImagePath,
        fit: BoxFit.cover,
        placeholderBuilder: (context) => _previewFallback(),
      );
    }
    return Image.asset(
      widget.template.previewImagePath,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _previewFallback(),
    );
  }

  Widget _previewFallback() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEC4899), Color(0xFF172554)],
        ),
      ),
    );
  }
}
