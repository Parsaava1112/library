import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/database/db_helper.dart';
import '../../core/services/download_service.dart';
import '../../data/models/book_model.dart';
import '../../services/api_service.dart';
import '../widgets/book_cover.dart';
import '../widgets/rating_widget.dart';
import 'pdf_reader_screen.dart';
import 'audio_player_screen.dart';
import 'video_player_screen.dart';

class BookDetailScreen extends StatefulWidget {
  final BookModel book;
  const BookDetailScreen({super.key, required this.book});

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  late BookModel _book;
  bool _downloading = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _book = widget.book;
    _checkDownloaded();
  }

  /// بررسی وضعیت دانلود از دیتابیس (با ID محلی)
  Future<void> _checkDownloaded() async {
    if (_book.id == null) return;
    final fresh = await DBHelper.getBookById(_book.id!);
    if (fresh != null && mounted) {
      setState(() => _book = fresh);
    }
  }

  Future<void> _download() async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _progress = 0;
    });

    try {
      final path = await DownloadService().download(
        book: _book,
        baseUrl: ApiService.fileBaseUrl,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );

      if (!mounted) return;

      if (path != null) {
        await _checkDownloaded();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Text(
                  'کتاب با موفقیت دانلود شد',
                  style: GoogleFonts.vazirmatn(),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade700,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'خطا در دانلود کتاب',
              style: GoogleFonts.vazirmatn(),
            ),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ _download error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا: $e', style: GoogleFonts.vazirmatn()),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _progress = 0;
        });
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'حذف دانلود',
          style: GoogleFonts.vazirmatn(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'آیا می‌خواهید این کتاب را از حافظه حذف کنید؟',
          style: GoogleFonts.vazirmatn(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('انصراف', style: GoogleFonts.vazirmatn()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text('حذف', style: GoogleFonts.vazirmatn()),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DownloadService().deleteDownload(_book);
      await _checkDownloaded();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حذف شد', style: GoogleFonts.vazirmatn()),
          ),
        );
      }
    }
  }

  void _open() {
    Widget screen;
    switch (_book.type) {
      case 'audio':
        screen = AudioPlayerScreen(book: _book);
        break;
      case 'video':
        screen = VideoPlayerScreen(book: _book);
        break;
      default:
        screen = PdfReaderScreen(book: _book);
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            backgroundColor: theme.colorScheme.primary,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.primary.withOpacity(0.7),
                      theme.colorScheme.background,
                    ],
                  ),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 40, bottom: 20),
                    child: Hero(
                      // 🔑 Hero tag یکتا بر اساس ID محلی - باید با home_screen.dart یکی باشد
                      tag: 'book_cover_${_book.id}',
                      child: BookCover(
                        book: _book,
                        width: 160,
                        height: 220,
                        radius: 16,
                        baseUrl: ApiService.fileBaseUrl,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTitle(theme),
                  const SizedBox(height: 16),
                  _buildInfoRow(theme),
                  const SizedBox(height: 24),
                  _buildDescription(theme),
                  const SizedBox(height: 24),
                  _buildActionButtons(theme),
                  const SizedBox(height: 24),
                  RatingWidget(
                    bookId: _book.id ?? 0,
                    initialRating: _book.rating,
                    onRatingChanged: (value) {
                      _checkDownloaded();
                    },
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitle(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _book.title,
                style: GoogleFonts.vazirmatn(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _book.author,
                style: GoogleFonts.vazirmatn(
                  fontSize: 14,
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
        if (_book.isDownloaded)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.download_done_rounded,
                    size: 16, color: Colors.green.shade800),
                const SizedBox(width: 4),
                Text(
                  'دانلود شده',
                  style: GoogleFonts.vazirmatn(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade800,
                  ),
                ),
              ],
            ),
          ),
      ],
    ).animate().fadeIn().slideY(begin: 0.15, end: 0);
  }

  Widget _buildInfoRow(ThemeData theme) {
    return Row(
      children: [
        _infoChip(
          theme,
          Icons.star_rounded,
          '${_book.rating.toStringAsFixed(1)} (${_book.ratingCount})',
          theme.colorScheme.secondary,
        ),
        const SizedBox(width: 8),
        _infoChip(
          theme,
          _book.type == 'pdf'
              ? Icons.picture_as_pdf_rounded
              : _book.type == 'audio'
                  ? Icons.headphones_rounded
                  : Icons.videocam_rounded,
          _book.category,
          theme.colorScheme.primary,
        ),
        if (_book.fileSize > 0) ...[
          const SizedBox(width: 8),
          _infoChip(
            theme,
            Icons.storage_rounded,
            _book.readableSize,
            Colors.blueGrey,
          ),
        ],
      ],
    ).animate().fadeIn(delay: 100.ms);
  }

  Widget _infoChip(
      ThemeData theme, IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.vazirmatn(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescription(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.description_rounded,
                size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              'درباره این اثر',
              style: GoogleFonts.vazirmatn(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          _book.description.isEmpty
              ? 'توضیحی برای این اثر ثبت نشده است.'
              : _book.description,
          style: GoogleFonts.vazirmatn(
            fontSize: 14,
            height: 1.9,
            color: theme.colorScheme.onSurface.withOpacity(0.8),
          ),
        ),
      ],
    ).animate().fadeIn(delay: 200.ms);
  }

  Widget _buildActionButtons(ThemeData theme) {
    // ============ اگر دانلود شده: دکمه‌های باز کردن و حذف ============
    if (_book.isDownloaded) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _open,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(
                _book.type == 'pdf'
                    ? 'شروع مطالعه'
                    : _book.type == 'audio'
                        ? 'پخش کتاب صوتی'
                        : 'پخش ویدیو',
                style: GoogleFonts.vazirmatn(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Colors.red),
              label: Text(
                'حذف از حافظه',
                style: GoogleFonts.vazirmatn(
                  fontSize: 14,
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
              ),
            ),
          ),
        ],
      ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.15, end: 0);
    }

    // ============ اگر دانلود نشده: دکمه دریافت ============
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: _downloading ? null : _download,
            icon: _downloading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download_rounded),
            label: Text(
              _downloading
                  ? 'در حال دانلود... ${(_progress * 100).toInt()}%'
                  : 'دریافت این اثر',
              style: GoogleFonts.vazirmatn(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        if (_downloading) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 6,
              backgroundColor:
                  theme.colorScheme.onSurface.withOpacity(0.1),
              valueColor:
                  AlwaysStoppedAnimation(theme.colorScheme.primary),
            ),
          ),
        ],
      ],
    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.15, end: 0);
  }
}
