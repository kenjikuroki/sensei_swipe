import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CategoryReviewModal extends StatelessWidget {
  final Map<String, int> weaknessCounts;
  final Function(String) onCategoryTap;

  const CategoryReviewModal({
    super.key,
    required this.weaknessCounts,
    required this.onCategoryTap,
  });

  @override
  Widget build(BuildContext context) {
    // Define the categories to match HomePage
    final categories = [
      {'key': 'part1', 'title': '潜水業務', 'icon': Icons.waves, 'color': Colors.blueAccent},
      {'key': 'part2', 'title': '送気、潜降及び浮上', 'icon': Icons.arrow_downward, 'color': Colors.orange},
      {'key': 'part3', 'title': '高気圧障害', 'icon': Icons.medical_services, 'color': Colors.redAccent},
      {'key': 'part4', 'title': '関係法令', 'icon': Icons.gavel, 'color': Colors.green},
    ];

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(32),
          topRight: Radius.circular(32),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "カテゴリーを選択",
            style: GoogleFonts.lora(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 24),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: categories.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final cat = categories[index];
                final count = weaknessCounts[cat['key']] ?? 0;
                
                return _CategoryCard(
                  title: cat['title'] as String,
                  icon: cat['icon'] as IconData,
                  iconColor: cat['color'] as Color,
                  count: count,
                  onTap: () {
                    Navigator.pop(context);
                    onCategoryTap(cat['key'] as String);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final int count;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "$count問",
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
