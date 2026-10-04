import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/database/db_helper.dart';
import '../../data/models/book_model.dart';
import '../../services/api_service.dart';
import '../widgets/animated_background.dart';
import '../widgets/book_cover.dart';
import 'book_detail_screen.dart';

class MyBooksScreen extends StatefulWidget {
  const MyBooksScreen({super.key});

  @override
  State<MyBooksScreen> createState() => _MyBooksScreenState();
}

class _MyBooksScreenState extends State<MyBooksScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<BookModel> _all = [];
  bool _loading = true;

  final _tabs = ['همه', 'کتاب', 'صوتی', 'ویدیویی'];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _tabs.length, vsync: this);
    _tab.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await DBHelper.getDownloadedBooks();
    if (!mounted) return;
    setState(() {
      _all = list;
      _loading = false;
    });
  }

  List<BookModel> _filtered() {
    switch (_tab.index) {
      case 1:
        return _all.where((b) => b.type == 'pdf').toList();
      case 2:
        return _all.where((b) => b.type == 'audio').toList();
      case 3:
        return _all.where((b) => b.type == 'video').toList();
      default:
        return _all;
    }
  }

  int get _totalSize => _all.fold(0, (sum, b) => sum + b.fileSize);

  String get _readableTotalSize {
    if (_totalSize < 1024 * 1024) {
      return '${(_totalSize / 1024).toStringAsFixed(1)} KB';
    }
    if (_totalSize < 1024 * 1024 * 1024) {
      return '${(_totalSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(_totalSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'کتاب‌های من',
          style: GoogleFonts.vazirmatn(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          indicatorColor: theme.colorScheme.primary,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor:
              theme.colorScheme.onSurface.withOpacity(0.5),
          labelStyle: GoogleFonts.vazirmatn(
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: AnimatedBackground(
        blobCount: 3,
        intensity: 0.5,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                color: theme.colorScheme.primary,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildSummary(theme)),
                    if (_filtered().isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildEmpty(theme),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.all(16),
                        sliver: SliverGrid.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                            childAspectRatio: 0.62,
                          ),
                          itemCount: _filtered().length,
                          itemBuilder: (context, i) {
                            return _bookGridItem(
                                theme, _filtered()[i], i);
                          },
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 60)),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSummary(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              theme.colorScheme.primary,
              theme.colorScheme.secondary,
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.25),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.folder_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_all.length} اثر ذخیره شده',
                    style: GoogleFonts.vazirmatn(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'حجم کل: $_readableTotalSize',
                    style: GoogleFonts.vazirmatn(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ).animate().fadeIn().slideY(begin: 0.1, end: 0),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.library_books_outlined,
              size: 90,
              color: theme.colorScheme.primary.withOpacity(0.3),
            ),
            const SizedBox(height: 20),
            Text(
              'هنوز کتابی دانلود نکرده‌اید',
              style: GoogleFonts.vazirmatn(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'برای دسترسی آفلاین، روی دکمه «دریافت این اثر» بزنید',
              textAlign: TextAlign.center,
              style: GoogleFonts.vazirmatn(
                fontSize: 13,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bookGridItem(ThemeData theme, BookModel book, int index) {
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BookDetailScreen(book: book),
          ),
        );
        _load();
      },
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: theme.colorScheme.primary.withOpacity(0.12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: BookCover(
                    book: book,
                    width: 110,
                    height: 150,
                    radius: 12,
                    // ✅ اصلاح: استفاده از fileBaseUrl
                    baseUrl: ApiService.fileBaseUrl,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.vazirmatn(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.storage_rounded,
                          size: 12,
                          color: theme.colorScheme.onSurface
                              .withOpacity(0.5)),
                      const SizedBox(width: 3),
                      Text(
                        book.readableSize,
                        style: GoogleFonts.vazirmatn(
                          fontSize: 10,
                          color: theme.colorScheme.onSurface
                              .withOpacity(0.5),
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.download_done_rounded,
                          size: 14, color: Colors.green.shade600),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(delay: (60 * index).ms, duration: 400.ms)
        .slideY(begin: 0.1, end: 0);
  }
}
