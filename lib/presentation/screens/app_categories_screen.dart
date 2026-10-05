import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/app_category_model.dart';
import '../../services/app_info_service.dart';
import '../widgets/app_icon_widget.dart';
import '../widgets/category_pill.dart';

class AppCategoriesScreen extends StatefulWidget {
  final VoidCallback? onBackToHome;

  const AppCategoriesScreen({super.key, this.onBackToHome});

  @override
  State<AppCategoriesScreen> createState() => _AppCategoriesScreenState();
}

class _AppCategoriesScreenState extends State<AppCategoriesScreen> {
  final AppInfoService _appInfoService = AppInfoService();
  List<AppCategoryInfo> _apps = List.from(MockDataRepository.allAppCategories);
  String _searchQuery = '';
  int _selectedFilterIndex = 0; // 0: All, 1: Productive, 2: Neutral, 3: Negative

  @override
  void initState() {
    super.initState();
    _loadAppCategories();
  }

  Future<void> _loadAppCategories() async {
    final loaded = await _appInfoService.getAppCategories();
    if (mounted && loaded.isNotEmpty) {
      setState(() {
        _apps = loaded;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    List<AppCategoryInfo> filteredList = _apps.where((app) {
      final matchesSearch = app.appName.toLowerCase().contains(_searchQuery.toLowerCase());
      if (!matchesSearch) return false;

      if (_selectedFilterIndex == 1) return app.category == AppCategoryType.productive;
      if (_selectedFilterIndex == 2) return app.category == AppCategoryType.neutral;
      if (_selectedFilterIndex == 3) return app.category == AppCategoryType.negative;
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('App Categories'),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded, size: 28),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else if (widget.onBackToHome != null) {
              widget.onBackToHome!();
            }
          },
        ),
      ),
      body: Column(
        children: [
          // Search & Filters Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                // Search Field
                TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Search apps...',
                    hintStyle: const TextStyle(fontSize: 14, color: AppColors.textMuted),
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 20),
                    filled: true,
                    fillColor: AppColors.inputBackground,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Horizontal Category Filter Pills
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterPill(0, 'All'),
                      const SizedBox(width: 8),
                      _buildFilterPill(1, 'Productive'),
                      const SizedBox(width: 8),
                      _buildFilterPill(2, 'Neutral'),
                      const SizedBox(width: 8),
                      _buildFilterPill(3, 'Negative'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // App List
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              itemCount: filteredList.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = filteredList[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        AppIconWidget(iconKey: item.iconAsset, size: 40),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            item.appName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        CategoryPill(
                          category: item.category,
                          isDropdown: true,
                          onTap: () => _showCategoryChangeDialog(item),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.textMuted,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPill(int index, String label) {
    final isSelected = _selectedFilterIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilterIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryGreen : AppColors.inputBackground,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  void _showCategoryChangeDialog(AppCategoryInfo item) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Change category for ${item.appName}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.check_circle_outline, color: AppColors.productive),
                title: const Text('Productive'),
                onTap: () {
                  _updateCategory(item.packageName, AppCategoryType.productive);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.remove_circle_outline, color: AppColors.neutral),
                title: const Text('Neutral'),
                onTap: () {
                  _updateCategory(item.packageName, AppCategoryType.neutral);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.warning_amber_rounded, color: AppColors.negative),
                title: const Text('Negative'),
                onTap: () {
                  _updateCategory(item.packageName, AppCategoryType.negative);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _updateCategory(String packageName, AppCategoryType newCategory) {
    setState(() {
      final index = _apps.indexWhere((element) => element.packageName == packageName);
      if (index != -1) {
        _apps[index] = _apps[index].copyWith(category: newCategory);
      }
    });
    _appInfoService.updateCategory(packageName, newCategory);
  }
}
