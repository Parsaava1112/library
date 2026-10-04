import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/user_model.dart';
import '../data/models/book_model.dart';
import '../data/models/rating_model.dart';
import '../core/database/db_helper.dart';

class ApiService {
  // ==================== تنظیمات ====================
  static String baseUrl = 'https://api.fanoosy.ir/api';

  static String get fileBaseUrl {
    final url = baseUrl;
    if (url.endsWith('/api/')) {
      return url.substring(0, url.length - 5);
    }
    if (url.endsWith('/api')) {
      return url.substring(0, url.length - 4);
    }
    return url;
  }

  static const Duration _timeout = Duration(seconds: 30);
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  static String? _authToken;
  static UserModel? _currentUser;

  // ==================== مدیریت توکن و کاربر ====================

  static Future<void> setAuthToken(String token) async {
    _authToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  static Future<void> loadAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    _authToken = prefs.getString('auth_token');
  }

  static Future<void> clearAuthToken() async {
    _authToken = null;
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('current_user');
  }

  static Future<void> setCurrentUser(UserModel user) async {
    _currentUser = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_user', jsonEncode(user.toMap()));
  }

  static Future<UserModel?> getCurrentUser() async {
    if (_currentUser != null) return _currentUser;

    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('current_user');
    if (data != null) {
      try {
        _currentUser = UserModel.fromMap(jsonDecode(data));
        return _currentUser;
      } catch (_) {}
    }

    final users = await DBHelper.getAllUsers();
    if (users.isNotEmpty) {
      _currentUser = users.first;
      return _currentUser;
    }

    return null;
  }

  // ==================== هدرها ====================

  static Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json; charset=UTF-8',
      'Accept': 'application/json',
    };
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  // ==================== متدهای HTTP ====================

  static Future<http.Response> _get(String endpoint) async {
    return _retryRequest(() async {
      final uri = Uri.parse('$baseUrl$endpoint');
      debugPrint('🔵 GET: $uri');
      return await http.get(uri, headers: _headers).timeout(_timeout);
    });
  }

  static Future<http.Response> _post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    return _retryRequest(() async {
      final uri = Uri.parse('$baseUrl$endpoint');
      debugPrint('🔵 POST: $uri');
      return await http
          .post(uri, headers: _headers, body: jsonEncode(body))
          .timeout(_timeout);
    });
  }

  static Future<http.Response> _put(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    return _retryRequest(() async {
      final uri = Uri.parse('$baseUrl$endpoint');
      return await http
          .put(uri, headers: _headers, body: jsonEncode(body))
          .timeout(_timeout);
    });
  }

  static Future<http.Response> _retryRequest(
    Future<http.Response> Function() request,
  ) async {
    int attempts = 0;
    while (attempts < _maxRetries) {
      try {
        final response = await request();
        if (response.statusCode >= 500 && attempts < _maxRetries - 1) {
          attempts++;
          await Future.delayed(_retryDelay * attempts);
          continue;
        }
        return response;
      } on SocketException catch (e) {
        attempts++;
        debugPrint('SocketException (attempt $attempts): $e');
        if (attempts >= _maxRetries) rethrow;
        await Future.delayed(_retryDelay * attempts);
      } on TimeoutException catch (e) {
        attempts++;
        debugPrint('TimeoutException (attempt $attempts): $e');
        if (attempts >= _maxRetries) rethrow;
        await Future.delayed(_retryDelay * attempts);
      } catch (e) {
        rethrow;
      }
    }
    throw Exception('عدم پاسخگویی سرور پس از $_maxRetries تلاش');
  }

  static dynamic _handleResponse(http.Response response) {
    final bodyPreview = response.body.length > 200
        ? response.body.substring(0, 200)
        : response.body;
    debugPrint('🟢 Response [${response.statusCode}]: $bodyPreview...');

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      String errorMessage = 'خطای نامشخص';
      try {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        errorMessage = errorBody['error'] ??
            errorBody['message'] ??
            'خطای سرور (${response.statusCode})';
      } catch (_) {
        errorMessage = 'خطای سرور (${response.statusCode})';
      }
      throw ApiException(errorMessage, response.statusCode);
    }
  }

  // ==================== بررسی سلامت سرور ====================

  static Future<bool> isServerAvailable() async {
    try {
      final uri = Uri.parse('$baseUrl/health');
      final response =
          await http.get(uri).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ==================== احراز هویت ====================

  static Future<Map<String, dynamic>> login({
    required String name,
    required String nationalCode,
  }) async {
    try {
      final response = await _post('/login', {
        'name': name,
        'national_code': nationalCode,
      });
      final data = _handleResponse(response);

      final user = UserModel.fromMap(data['user']);
      await setCurrentUser(user);
      if (data['token'] != null) {
        await setAuthToken(data['token']);
      }

      await DBHelper.insertUser(user);

      return {
        'success': true,
        'user': user,
        'message': data['message'] ?? 'ورود موفق',
      };
    } on ApiException catch (e) {
      return {'success': false, 'error': e.message};
    } on SocketException {
      return {
        'success': false,
        'error': 'اتصال به سرور برقرار نیست. حالت آفلاین فعال است.',
        'offline': true,
      };
    } catch (e) {
      return {'success': false, 'error': 'خطای غیرمنتظره: $e'};
    }
  }

  // ==================== کتاب‌ها ====================

  /// دریافت کتاب‌ها از سرور و ذخیره در دیتابیس محلی
  /// 🔑 برگرداندن لیست با ID محلی (نه سرور)
  static Future<List<BookModel>> fetchBooksAndCache({
    String? type,
    String? category,
  }) async {
    try {
      String endpoint = '/books';
      final params = <String>[];
      if (type != null) params.add('type=$type');
      if (category != null) params.add('category=$category');
      if (params.isNotEmpty) endpoint += '?${params.join('&')}';

      debugPrint('📚 Fetching books from: $baseUrl$endpoint');
      final response = await _get(endpoint);
      final data = _handleResponse(response) as List;
      debugPrint('📚 Server returned ${data.length} books');

      final serverBooks = data.map((e) => BookModel.fromMap(e)).toList();

      if (serverBooks.isNotEmpty) {
        await _saveBooksLocally(serverBooks);
        debugPrint('📚 Saved ${serverBooks.length} books to local DB');
      }

      // 🔑 مهم: همیشه از دیتابیس محلی بخوان تا ID محلی داشته باشی
      final localBooks = await DBHelper.getAllBooks();
      debugPrint('📚 Returning ${localBooks.length} books (local IDs)');
      return localBooks;
    } catch (e) {
      debugPrint('❌ fetchBooksAndCache error: $e');
      return await DBHelper.getAllBooks();
    }
  }

  /// ذخیره کتاب‌ها در دیتابیس محلی
  /// کتاب‌های موجود را آپدیت می‌کند، کتاب‌های جدید را درج می‌کند
  static Future<void> _saveBooksLocally(List<BookModel> serverBooks) async {
    for (final serverBook in serverBooks) {
      try {
        // پیدا کردن کتاب با همین عنوان در دیتابیس محلی
        final existing = await DBHelper.findBookByTitle(serverBook.title);

        if (existing != null) {
          // کتاب موجود → فقط اطلاعات غیرمحلی را آپدیت کن
          final updated = BookModel(
            // 🔑 ID محلی را نگه دار
            id: existing.id,
            title: serverBook.title,
            author: serverBook.author,
            description: serverBook.description,
            coverUrl: serverBook.coverUrl,
            fileUrl: serverBook.fileUrl,
            // 🔑 مسیر فایل دانلود شده را نگه دار
            filePath: existing.filePath,
            fileSize: serverBook.fileSize,
            type: serverBook.type,
            category: serverBook.category,
            rating: serverBook.rating,
            ratingCount: serverBook.ratingCount,
            // 🔑 وضعیت دانلود را نگه دار
            isDownloaded: existing.isDownloaded,
            downloadedAt: existing.downloadedAt,
          );
          await DBHelper.updateBook(updated);
        } else {
          // کتاب جدید → درج کن
          await DBHelper.insertBook(serverBook);
        }
      } catch (e) {
        debugPrint('Save book error for "${serverBook.title}": $e');
      }
    }
  }

  static Future<List<BookModel>> fetchBooks({
    String? type,
    String? category,
  }) async {
    return fetchBooksAndCache(type: type, category: category);
  }

  static Future<BookModel?> fetchBookDetail(int bookId) async {
    try {
      final response = await _get('/books/$bookId');
      final data = _handleResponse(response);
      return BookModel.fromMap(data);
    } catch (e) {
      debugPrint('fetchBookDetail error: $e');
      return null;
    }
  }

  // ==================== امتیازات ====================

  static Future<Map<String, dynamic>> submitRating({
    required int bookId,
    required String userName,
    required double rating,
    String? comment,
  }) async {
    try {
      final response = await _post('/ratings', {
        'book_id': bookId,
        'user_name': userName,
        'rating': rating,
        if (comment != null) 'comment': comment,
      });
      _handleResponse(response);
      return {'success': true, 'message': 'امتیاز ثبت شد'};
    } on ApiException catch (e) {
      await _queueRating(bookId, userName, rating, comment);
      return {'success': false, 'error': e.message, 'queued': true};
    } catch (e) {
      await _queueRating(bookId, userName, rating, comment);
      return {
        'success': false,
        'error': 'در صف آفلاین ذخیره شد',
        'queued': true,
      };
    }
  }

  static Future<void> _queueRating(
    int bookId,
    String userName,
    double rating,
    String? comment,
  ) async {
    final payload = jsonEncode({
      'book_id': bookId,
      'user_name': userName,
      'rating': rating,
      'comment': comment,
    });
    await DBHelper.addToSyncQueue('rating', payload);
  }

  static Future<List<RatingModel>> fetchRatings(int bookId) async {
    try {
      final response = await _get('/ratings/$bookId');
      final data = _handleResponse(response) as List;
      return data.map((e) => RatingModel.fromMap(e)).toList();
    } catch (e) {
      return await DBHelper.getRatingsForBook(bookId);
    }
  }

  // ==================== هوش مصنوعی ====================

  static Future<List<BookModel>> fetchRecommendations({
    required int userId,
    int limit = 5,
  }) async {
    try {
      final response =
          await _get('/ai/recommendations/$userId?limit=$limit');
      final data = _handleResponse(response) as List;
      return data.map((e) => BookModel.fromMap(e)).toList();
    } catch (e) {
      final all = await DBHelper.getAllBooks();
      all.sort((a, b) => b.rating.compareTo(a.rating));
      return all.take(limit).toList();
    }
  }

  static Future<String> fetchMotivationalMessage(int userId) async {
    try {
      final response = await _get('/ai/message/$userId');
      final data = _handleResponse(response);
      return data['message'] ?? _getLocalMotivationalMessage();
    } catch (e) {
      return _getLocalMotivationalMessage();
    }
  }

  static String _getLocalMotivationalMessage() {
    final messages = [
      'امروز یه کتاب خوب بخون. حتی ۱۰ دقیقه.',
      'شهید سلیمانی می‌فرمود: «هرچه داریم از کتاب و مطالعه است.»',
      'کتاب بهترین دوستیه که هیچ‌وقت تنهات نمی‌ذاره.',
      'با هر صفحه‌ای که می‌خونی، یه پله بالاتر می‌ری.',
      'دانش سلاح امروزه. با کتاب مسلح شو.',
    ];
    messages.shuffle();
    return messages.first;
  }

  static Future<Map<String, dynamic>> fetchUserStats(int userId) async {
    try {
      final response = await _get('/ai/stats/$userId');
      final data = _handleResponse(response) as Map<String, dynamic>;
      return data;
    } catch (e) {
      return {
        'total_books_read': 0,
        'total_minutes_read': 0,
        'current_streak': 0,
        'badges': [],
      };
    }
  }

  static Future<bool> recordActivity({
    required int userId,
    required int bookId,
    required String action,
    int minutes = 0,
  }) async {
    try {
      final response = await _post('/ai/activity', {
        'user_id': userId,
        'book_id': bookId,
        'action': action,
        'minutes': minutes,
      });
      _handleResponse(response);
      return true;
    } catch (e) {
      await DBHelper.addToSyncQueue(
        'activity',
        jsonEncode({
          'user_id': userId,
          'book_id': bookId,
          'action': action,
          'minutes': minutes,
        }),
      );
      return false;
    }
  }

  // ==================== لیدربورد ====================

  static Future<List<Map<String, dynamic>>> fetchLeaderboard({
    String period = 'weekly',
  }) async {
    try {
      final response = await _get('/leaderboard?period=$period');
      final data = _handleResponse(response) as List;
      return data.cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  // ==================== حلقه‌های مطالعه ====================

  static Future<List<Map<String, dynamic>>> fetchCircles() async {
    try {
      final response = await _get('/circles');
      final data = _handleResponse(response) as List;
      return data.cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> createCircle({
    required String name,
    required int userId,
    String? description,
    int? bookId,
  }) async {
    try {
      final response = await _post('/circles', {
        'name': name,
        'user_id': userId,
        if (description != null) 'description': description,
        if (bookId != null) 'book_id': bookId,
      });
      final data = _handleResponse(response);
      return {'success': true, 'data': data};
    } on ApiException catch (e) {
      return {'success': false, 'error': e.message};
    } catch (e) {
      return {'success': false, 'error': 'خطای غیرمنتظره: $e'};
    }
  }

  static Future<Map<String, dynamic>> joinCircle({
    required int circleId,
    required int userId,
  }) async {
    try {
      final response = await _post('/circles/$circleId/join', {
        'user_id': userId,
      });
      _handleResponse(response);
      return {'success': true, 'message': 'عضو شدید'};
    } on ApiException catch (e) {
      return {'success': false, 'error': e.message};
    } catch (e) {
      return {'success': false, 'error': 'خطای غیرمنتظره: $e'};
    }
  }

  // ==================== همگام‌سازی آفلاین ====================

  static Future<Map<String, int>> syncPendingOperations() async {
    int successCount = 0;
    int failCount = 0;

    try {
      final queue = await DBHelper.getSyncQueue();
      debugPrint('Syncing ${queue.length} pending operations...');

      for (final item in queue) {
        try {
          final payload = jsonDecode(item['payload']);
          final operation = item['operation'];

          bool success = false;
          switch (operation) {
            case 'rating':
              final result = await submitRating(
                bookId: payload['book_id'],
                userName: payload['user_name'],
                rating: (payload['rating'] as num).toDouble(),
                comment: payload['comment'],
              );
              success = result['success'] == true;
              break;
            case 'activity':
              success = await recordActivity(
                userId: payload['user_id'],
                bookId: payload['book_id'],
                action: payload['action'],
                minutes: payload['minutes'] ?? 0,
              );
              break;
            default:
              success = true;
          }

          if (success) {
            await DBHelper.removeFromSyncQueue(item['id']);
            successCount++;
          } else {
            failCount++;
          }
        } catch (e) {
          failCount++;
        }
      }
    } catch (e) {
      debugPrint('syncPendingOperations error: $e');
    }

    return {'success': successCount, 'failed': failCount};
  }

  // ==================== FCM Token ====================

  static Future<bool> registerFcmToken({
    required int userId,
    required String token,
  }) async {
    try {
      final response = await _post('/users/$userId/fcm-token', {
        'fcm_token': token,
      });
      _handleResponse(response);
      return true;
    } catch (e) {
      return false;
    }
  }

  // ==================== بروزرسانی پروفایل ====================

  static Future<Map<String, dynamic>> updateUserProfile({
    required int userId,
    String? name,
    String? bio,
    String? avatarSeed,
    String? avatarStyle,
    String? themePreference,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (bio != null) body['bio'] = bio;
      if (avatarSeed != null) body['avatar_seed'] = avatarSeed;
      if (avatarStyle != null) body['avatar_style'] = avatarStyle;
      if (themePreference != null) body['theme_preference'] = themePreference;

      final response = await _put('/users/$userId', body);
      final data = _handleResponse(response);

      if (data['user'] != null) {
        final updated = UserModel.fromMap(data['user']);
        await setCurrentUser(updated);
        await DBHelper.updateUser(updated);
      }

      return {'success': true, 'user': data['user']};
    } on ApiException catch (e) {
      return {'success': false, 'error': e.message};
    } catch (e) {
      return {'success': false, 'error': 'خطای غیرمنتظره: $e'};
    }
  }
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}
