import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_controller.dart';
import '../../core/database/db_helper.dart';
import '../../core/services/achievement_service.dart';
import '../../data/models/book_model.dart';
import '../../data/models/user_model.dart';
import '../../services/api_service.dart';
import '../widgets/animated_background.dart';
import '../widgets/dicebear_avatar.dart';
import '../widgets/book_cover.dart';
import 'book_detail_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'achievements_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<BookModel> _books = [];
  List<BookModel> _filteredBooks = [];
  UserModel? _user;
  Map<String, dynamic> _stats = {};
  bool _loading = true;
  String _selectedCategory = 'همه';

  final List<String> _categories = [
    'همه',
    'کتاب',
    'کتاب صوتی',
    'پادکست تصویری',
  ];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      await AchievementService.initialize();

      List<BookModel> books = [];
      try {
        final serverAvailable = await ApiService.isServerAvailable();
        if (serverAvailable) {
          debugPrint('📚 Server available, fetching books...');
          books = await ApiService.fetchBooksAndCache();
          debugPrint('📚 Books from server (with local IDs): ${books.length}');
        } else {
          debugPrint('⚠️ Server not available, using local DB');
        }
      } catch (e) {
        debugPrint('❌ Server fetch error: $e');
      }

      if (books.isEmpty) {
        books = await DBHelper.getAllBooks();
        debugPrint('📚 Books from local DB: ${books.length}');
      }

      // ⚠️ حذف seed SampleData که باعث اشتباه می‌شد
      // اگر هیچ کتابی نبود، لیست خالی بمان
      // (کاربر می‌تواند با همگام‌سازی، کتاب‌ها را از سرور بگیرد)

      final user = await ApiService.getCurrentUser();

      Map<String, dynamic> stats = {
        'total_books_read': 0,
        'total_minutes_read': 0,
        'current_streak': 0,
        'xp': 0,
      };
      if (user?.id != null) {
        stats = await DBHelper.getUserStats(user!.id!);
        await AchievementService.checkAndUnlock(user.id!);
      }

      if (!mounted) return;
      setState(() {
        _books = books;
        _applyFilter();
        _user = user;
        _stats = stats;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    if (_selectedCategory == 'همه') {
      _filteredBooks = List.from(_books);
    } else {
      final type = _getTypeFromCategory(_selectedCategory);
      _filteredBooks = _books.where((b) => b.type == type).toList();
    }
  }

  void _filterBooks(String category) {
    setState(() {
      _selectedCategory = category;
      _applyFilter();
    });
  }

  String _getTypeFromCategory(String category) {
    switch (category) {
      case 'کتاب':
        return 'pdf';
      case 'کتاب صوتی':
        return 'audio';
      case 'پادکست تصویری':
        return 'video';
      default:
        return 'pdf';
    }
  }

  int get _xp => (_stats['xp'] as num?)?.toInt() ?? 0;
  int get _level => AchievementService.levelForXp(_xp);

  Future<void> _manualSync() async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Text('در حال همگام‌سازی...', style: GoogleFonts.vazirmatn()),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );

    await _loadAll();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Text(
                '${_books.length} اثر بارگذاری شد',
                style: GoogleFonts.vazirmatn(),
              ),
            ],
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeController = context.watch<ThemeController>();

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      floatingActionButton: FloatingActionButton(
        onPressed: _manualSync,
        backgroundColor: theme.colorScheme.primary,
        child: const Icon(Icons.sync_rounded, color: Colors.white),
      ),
      body: AnimatedBackground(
        blobCount: 5,
        intensity: 0.8,
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadAll,
                  color: theme.colorScheme.primary,
                  child: CustomScrollView(
                    slivers: [
                      _buildAppBar(theme, themeController),
                      _buildWelcomeBanner(theme),
                      _buildStatsRow(theme),
                      _buildCategoryChips(theme),
                      _buildBookList(theme),
                      const SliverToBoxAdapter(child: SizedBox(height: 100)),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildAppBar(ThemeData theme, ThemeController themeController) {
    return SliverAppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      floating: true,
      pinned: false,
      expandedHeight: 80,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Row(
          children: [
            DiceBearAvatar(
              seed: _user?.avatarSeed ?? _user?.nationalCode ?? 'shahid',
              style: _user?.avatarStyle ?? 'adventurer',
              size: 40,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                ).then((_) => _loadAll());
              },
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'سلام، ${_user?.name.split(' ').first ?? 'کاربر'}',
                    style: GoogleFonts.vazirmatn(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    'کتابخانه شهید سلیمانی',
                    style: GoogleFonts.vazirmatn(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(
            themeController.isDark
                ? Icons.light_mode_rounded
                : Icons.dark_mode_rounded,
            color: theme.colorScheme.onSurface,
          ),
          onPressed: () => themeController.toggle(),
        ),
        IconButton(
          icon: Icon(Icons.settings_rounded,
              color: theme.colorScheme.onSurface),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildWelcomeBanner(ThemeData theme) {
    final xpInLevel = AchievementService.xpInCurrentLevel(_xp).toDouble();
    final xpNeeded = AchievementService.xpForLevel(_level).toDouble();
    final progress =
        xpNeeded > 0 ? (xpInLevel / xpNeeded).clamp(0.0, 1.0) : 0.0;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                theme.colorScheme.primary,
                theme.colorScheme.primary.withOpacity(0.75),
                theme.colorScheme.secondary.withOpacity(0.9),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.auto_awesome,
                        color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'سطح $_level',
                          style: GoogleFonts.vazirmatn(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '$_xp XP کل',
                          style: GoogleFonts.vazirmatn(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AchievementsScreen(),
                        ),
                      ).then((_) => _loadAll());
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.emoji_events_rounded,
                          color: Colors.white, size: 22),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${xpInLevel.toInt()} / ${xpNeeded.toInt()} XP تا سطح ${_level + 1}',
                style: GoogleFonts.vazirmatn(
                  fontSize: 11,
                  color: Colors.white.withOpacity(0.85),
                ),
              ),
            ],
          ),
        )
            .animate()
            .fadeIn(duration: 500.ms)
            .slideY(begin: 0.15, end: 0, curve: Curves.easeOutCubic),
      ),
    );
  }

  Widget _buildStatsRow(ThemeData theme) {
    final booksRead = (_stats['total_books_read'] as num?)?.toInt() ?? 0;
    final minutes = (_stats['total_minutes_read'] as num?)?.toInt() ?? 0;
    final streak = (_stats['current_streak'] as num?)?.toInt() ?? 0;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            _statCard(
              theme,
              icon: Icons.menu_book_rounded,
              label: 'کتاب',
              value: '$booksRead',
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            _statCard(
              theme,
              icon: Icons.timer_rounded,
              label: 'دقیقه',
              value: '$minutes',
              color: Colors.orange,
            ),
            const SizedBox(width: 12),
            _statCard(
              theme,
              icon: Icons.local_fire_department_rounded,
              label: 'استریک',
              value: '$streak',
              color: Colors.redAccent,
            ),
          ],
        )
            .animate()
            .fadeIn(delay: 100.ms, duration: 500.ms)
            .slideY(begin: 0.15, end: 0),
      ),
    );
  }

  Widget _statCard(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.15), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.vazirmatn(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.onSurface,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.vazirmatn(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChips(ThemeData theme) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 60,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _categories.length,
          itemBuilder: (context, i) {
            final cat = _categories[i];
            final active = _selectedCategory == cat;
            return Padding(
              padding: const EdgeInsets.only(left: 8, top: 8, bottom: 8),
              child: ChoiceChip(
                label: Text(cat),
                selected: active,
                onSelected: (_) => _filterBooks(cat),
                labelStyle: GoogleFonts.vazirmatn(
                  color:
                      active ? Colors.white : theme.colorScheme.onSurface,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
                selectedColor: theme.colorScheme.primary,
                backgroundColor: theme.colorScheme.surface,
                side: BorderSide(
                  color: active
                      ? theme.colorScheme.primary
                      : theme.colorScheme.primary.withOpacity(0.2),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBookList(ThemeData theme) {
    if (_filteredBooks.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_outlined,
                  size: 80,
                  color: theme.colorScheme.primary.withOpacity(0.3)),
              const SizedBox(height: 16),
              Text(
                'کتابی یافت نشد',
                style: GoogleFonts.vazirmatn(
                  fontSize: 16,
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _manualSync,
                icon: const Icon(Icons.sync_rounded),
                label: Text(
                  'همگام‌سازی با سرور',
                  style: GoogleFonts.vazirmatn(),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList.builder(
        itemCount: _filteredBooks.length,
        itemBuilder: (context, i) {
          final book = _filteredBooks[i];
          return _BookCard(
            // 🔑 کلید یکتا بر اساس ID محلی کتاب
            key: ValueKey('book_card_${book.id}'),
            book: book,
            index: i,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  // 🔑 پاس دادن همان کتاب با ID محلی درست
                  builder: (_) => BookDetailScreen(book: book),
                ),
              );
              // 🔄 بعد از بازگشت، لیست را رفرش کن (برای وضعیت دانلود)
              await _loadAll();
            },
          );
        },
      ),
    );
  }
}

// ==================== Book Card ====================

class _BookCard extends StatelessWidget {
  final BookModel book;
  final int index;
  final VoidCallback onTap;

  const _BookCard({
    super.key,
    required this.book,
    required this.index,
    required this.onTap,
  });

  Color _color(ThemeData theme) {
    switch (book.type) {
      case 'pdf':
        return theme.colorScheme.primary;
      case 'audio':
        return Colors.orange;
      case 'video':
        return Colors.redAccent;
      default:
        return theme.colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _color(theme);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: color.withOpacity(0.15),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // 🔑 Hero tag یکتا بر اساس ID محلی
                Hero(
                  tag: 'book_cover_${book.id}',
                  child: BookCover(
                    book: book,
                    width: 64,
                    height: 84,
                    radius: 14,
                    baseUrl: ApiService.fileBaseUrl,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.vazirmatn(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        book.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.vazirmatn(
                          fontSize: 12,
                          color:
                              theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.star_rounded,
                              color: theme.colorScheme.secondary, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            '${book.rating.toStringAsFixed(1)}',
                            style: GoogleFonts.vazirmatn(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '(${book.ratingCount})',
                            style: GoogleFonts.vazirmatn(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface
                                  .withOpacity(0.5),
                            ),
                          ),
                          const Spacer(),
                          if (book.isDownloaded)
                            Icon(Icons.download_done_rounded,
                                color: color, size: 18),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_back_ios_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurface.withOpacity(0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(delay: (60 * index).ms, duration: 400.ms)
        .slideX(begin: 0.1, end: 0, curve: Curves.easeOutCubic);
  }
}
