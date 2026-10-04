import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/models/book_model.dart';
import '../database/db_helper.dart';

class DownloadService {
  static final DownloadService _i = DownloadService._();
  factory DownloadService() => _i;
  DownloadService._();

  /// آدرس پایه‌ی سرور شما (بدون /api انتهایی)
  static const String _serverBase = 'https://api.fanoosy.ir';

  final Map<int, double> _progress = {};
  final Map<int, bool> _downloading = {};

  double? progressFor(int bookId) => _progress[bookId];
  bool isDownloading(int bookId) => _downloading[bookId] == true;

  /// ساخت URL کامل و صحیح
  String _buildFullUrl(String fileUrl) {
    if (fileUrl.startsWith('http://') || fileUrl.startsWith('https://')) {
      return fileUrl;
    }
    final cleanPath = fileUrl.startsWith('/') ? fileUrl : '/$fileUrl';
    final cleanBase = _serverBase.endsWith('/')
        ? _serverBase.substring(0, _serverBase.length - 1)
        : _serverBase;
    return '$cleanBase$cleanPath';
  }

  /// دانلود کتاب با dio
  Future<String?> download({
    required BookModel book,
    String? baseUrl,
    Function(double)? onProgress,
  }) async {
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
      // ========== ۱. ساخت URL ==========
      final fullUrl = _buildFullUrl(book.fileUrl);
      debugPrint('════════════════════════════════════════');
      debugPrint('🌐 Book: ${book.title}');
      debugPrint('🌐 Full URL: $fullUrl');
      debugPrint('════════════════════════════════════════');

      final uri = Uri.tryParse(fullUrl);
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
        throw Exception('URL نامعتبر: $fullUrl');
      }

      // ========== ۲. مسیر ذخیره ==========
      final appDir = await getApplicationDocumentsDirectory();
      final subFolder = _folderFor(book.type);
      final dir = Directory('${appDir.path}/library/$subFolder');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final ext = _extensionFor(book.type);
      final safeTitle = _sanitize(book.title);
      final fileName = 'book_${book.id}_$safeTitle.$ext';
      final savePath = '${dir.path}/$fileName';

      debugPrint('💾 Save to: $savePath');

      // ========== ۳. اگر فایل موجود و کامل است، برگردان ==========
      final existingFile = File(savePath);
      if (await existingFile.exists()) {
        final size = await existingFile.length();
        if (size > 0) {
          debugPrint('✅ File already exists ($size bytes)');
          await _markDownloaded(book, savePath);
          _progress[bookId] = 1.0;
          onProgress?.call(1.0);
          return savePath;
        } else {
          // فایل خالی، حذف کن
          await existingFile.delete();
        }
      }

      // ========== ۴. دانلود با dio ==========
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 30),
        sendTimeout: const Duration(minutes: 5),
        headers: {
          'Accept': '*/*',
          'User-Agent': 'ShahidLibrary/1.0',
        },
        followRedirects: true,
        validateStatus: (status) => status != null && status < 500,
      ));

      debugPrint('📡 Starting download...');

      final response = await dio.download(
        fullUrl,
        savePath,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final p = received / total;
            _progress[bookId] = p;
            onProgress?.call(p);
            if (kDebugMode && received % (1024 * 1024) < 4096) {
              debugPrint(
                  '📥 ${(received / 1024 / 1024).toStringAsFixed(1)} MB / '
                  '${(total / 1024 / 1024).toStringAsFixed(1)} MB');
            }
          }
        },
      );

      debugPrint('📡 Response status: ${response.statusCode}');

      if (response.statusCode != 200) {
        throw Exception('خطای سرور: ${response.statusCode}');
      }

      // ========== ۵. بررسی فایل دانلود شده ==========
      final downloadedFile = File(savePath);
      if (!await downloadedFile.exists()) {
        throw Exception('فایل دانلود شده یافت نشد');
      }

      final fileSize = await downloadedFile.length();
      debugPrint('💾 File size after download: $fileSize bytes');

      if (fileSize == 0) {
        await downloadedFile.delete();
        throw Exception('فایل دانلود شده خالی است');
      }

      // ========== ۶. ذخیره در دیتابیس ==========
      await _markDownloaded(book, savePath);

      _progress[bookId] = 1.0;
      onProgress?.call(1.0);

      debugPrint('✅✅✅ DOWNLOAD COMPLETE');
      debugPrint('════════════════════════════════════════');

      return savePath;
    } on DioException catch (e) {
      debugPrint('❌❌❌ DIO ERROR');
      debugPrint('❌ Type: ${e.type}');
      debugPrint('❌ Message: ${e.message}');
      debugPrint('❌ Response: ${e.response?.statusCode}');
      if (e.response?.data != null) {
        debugPrint('❌ Body: ${e.response?.data}');
      }
      _progress[bookId] = 0;
      return null;
    } catch (e, stackTrace) {
      debugPrint('❌❌❌ DOWNLOAD FAILED');
      debugPrint('❌ Error: $e');
      debugPrint('❌ Stack: $stackTrace');
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

  String _folderFor(String type) {
    switch (type) {
      case 'pdf':
        return 'books';
      case 'audio':
        return 'audio';
      case 'video':
        return 'video';
      default:
        return 'other';
    }
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
