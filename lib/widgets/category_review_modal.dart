import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import 'category_review_card.dart';

class CategoryReviewModal extends StatelessWidget {
  final Map<String, int> counts;
  final List<String> categoryOrder;
  final Function(String) onCategorySelected;

  const CategoryReviewModal({
    super.key,
    required this.counts,
    required this.categoryOrder,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    
    // Predefined colors
    final colors = [
      Colors.blueAccent,
      Colors.orange,
      Colors.redAccent,
      Colors.green,
      Colors.purpleAccent,
      Colors.teal,
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: const BoxDecoration(
        color: Color(0xFFF1F5F9),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(32),
          topRight: Radius.circular(32),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.selectCategory,
            textAlign: TextAlign.center,
            style: GoogleFonts.lora(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 24),
          ...categoryOrder.asMap().entries.map((entry) {
            final index = entry.key;
            final catName = entry.value;
            final count = counts[catName] ?? 0;
            if (count == 0) return const SizedBox.shrink();
            
            final color = colors[index % colors.length];
            
            return CategoryReviewCard(
              title: catName,
              icon: Icons.menu_book_rounded,
              iconColor: color,
              count: count,
              onTap: () {
                Navigator.pop(context);
                onCategorySelected(catName);
              },
            );
          }).toList(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
