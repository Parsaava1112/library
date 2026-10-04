import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:universal_downloader/universal_downloader.dart';

import '../../data/models/book_model.dart';
import '../database/db_helper.dart';

class DownloadService {
  static final DownloadService _i = DownloadService._();
  factory DownloadService() => _i;
  DownloadService._();

  final Map<int, double> _progress = {};
  final Map<int, bool> _downloading = {};

  double? progressFor(int bookId) => _progress[bookId];
  bool isDownloading(int bookId) => _downloading[bookId] == true;

  /// دانلود فایل با استفاده از universal_downloader
  /// [baseUrl] باید آدرس پایه بدون /api باشد (مثال: https://api.fanoosy.ir)
  Future<String?> download({
    required BookModel book,
    required String baseUrl,
    Function(double)? onProgress,
  }) async {
    // ========== اعتبارسنجی اولیه ==========
    if (book.id == null) {
      debugPrint('❌ Download: book.id == null');
      return null;
    }
    final bookId = book.id!;

    if (_downloading[bookId] == true) {
      debugPrint('⚠️ Already downloading book $bookId');
      return null;
    }

    _downloading[bookId] = true;
    _progress[bookId] = 0;
    onProgress?.call(0);

    try {
      // ========== ساخت URL کامل و صحیح ==========
      String fullUrl;
      if (book.fileUrl.startsWith('http')) {
        // اگر fileUrl از قبل کامل است (http/https)
        fullUrl = book.fileUrl;
      } else {
        // اطمینان از اینکه baseUrl با / تمام نشود و fileUrl با / شروع شود
        final cleanBase = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl;
        final cleanPath =
            book.fileUrl.startsWith('/') ? book.fileUrl : '/${book.fileUrl}';
        fullUrl = '$cleanBase$cleanPath';
      }

      debugPrint('🌐 Download URL: $fullUrl');

      // ========== تعیین نام فایل ==========
      final ext = _extensionFor(book.type);
      final fileName = 'book_${book.id}_${_sanitize(book.title)}.$ext';

      // ========== اجرای دانلود ==========
      final result = await UniversalDownloader.downloadFromUrlStream(
        url: fullUrl,
        filename: fileName,
        onProgress: (progress) {
          final p = progress.percentage / 100;
          _progress[bookId] = p;
          onProgress?.call(p);
        },
        onComplete: (filePath) {
          debugPrint('✅ Download complete: $filePath');
        },
        onError: (error) {
          debugPrint('❌ Download error: $error');
        },
      );

      // ========== بررسی نتیجه ==========
      if (!result.isSuccess) {
        throw Exception(result.errorMessage ?? 'Unknown download error');
      }

      final savedPath = result.filePath;
      if (savedPath == null || savedPath.isEmpty) {
        throw Exception('File path is null after download');
      }

      // ========== ذخیره در دیتابیس ==========
      await _markDownloaded(book, savedPath);

      _progress[bookId] = 1.0;
      onProgress?.call(1.0);

      return savedPath;
    } catch (e, stackTrace) {
      debugPrint('❌❌❌ DOWNLOAD FAILED');
      debugPrint('❌ Error: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      _progress[bookId] = 0;
      return null;
    } finally {
      _downloading[bookId] = false;
    }
  }

  // ==================== حذف دانلود ====================

  Future<bool> deleteDownload(BookModel book) async {
    if (book.id == null) return false;
    try {
      if (book.filePath.isNotEmpty) {
        final file = File(book.filePath);
        if (await file.exists()) await file.delete();
      }
      final db = await DBHelper.database;
      await db.update(
        'books',
        {
          'is_downloaded': 0,
          'file_path': '',
          'downloaded_at': null,
        },
        where: 'id = ?',
        whereArgs: [book.id],
      );
      return true;
    } catch (e) {
      debugPrint('Delete error: $e');
      return false;
    }
  }

  // ==================== توابع کمکی ====================

  Future<void> _markDownloaded(BookModel book, String path) async {
    final db = await DBHelper.database;
    await db.update(
      'books',
      {
        'is_downloaded': 1,
        'file_path': path,
        'downloaded_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [book.id],
    );
  }

  String _extensionFor(String type) {
    switch (type) {
      case 'pdf':
        return 'pdf';
      case 'audio':
        return 'mp3';
      case 'video':
        return 'mp4';
      default:
        return 'dat';
    }
  }

  String _sanitize(String name) {
    return name.replaceAll(RegExp(r'[^\w\u0600-\u06FF]'), '_');
  }
}
