import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  String? token;
  String? t1;
  String? sessionId;

  Future<dynamic> get(String path, [Map<String, Object?> query = const {}]) {
    return _sendWithRetry(
      () => _client.get(AppConfig.apiUri(path, query), headers: _headers),
    );
  }

  /// 直接请求外部 URI（不经过 AppConfig.apiUri），返回原始 JSON。
  /// 用于跨平台 API 调用（如网易云 API）。
  Future<dynamic> getRaw(Uri uri) {
    return _sendWithRetry(() => _client.get(uri, headers: {
          'Accept': 'application/json',
        }));
  }

  Future<dynamic> post(
    String path, {
    Map<String, Object?> query = const {},
    Map<String, Object?>? body,
  }) {
    return _sendWithRetry(
      () => _client.post(
        AppConfig.apiUri(path, query),
        headers: _headers,
        body: body == null ? null : jsonEncode(body),
      ),
      // POST 多为非幂等操作（发验证码、加歌等），失败重试可能造成重复提交，
      // 因此不在网络错误/5xx 时自动重试，由调用方决定是否重试。
      allowRetry: false,
    );
  }

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };

    if (token case final value?) {
      //headers['Authorization'] = 'Bearer $value';
      headers['X-Kg-Session-Id'] = value;
    }
    if (t1 case final value?) {
      headers['t1'] = value;
    }
    if (sessionId case final value?) {
      headers['X-Kg-Session-Id'] = value;
    }

    return headers;
  }

  /// 单个请求的超时时间。超时视为可重试的网络故障。
  static const _requestTimeout = Duration(seconds: 15);

  /// 带超时与自动重试的请求发送。
  ///
  /// 对连接超时、请求超时、5xx 服务器错误自动重试，指数退避（500ms、1s）。
  /// 其他错误（如 4xx、格式异常）不重试，直接抛出。
  /// [allowRetry] 为 false 时（非幂等 POST）任何错误都不重试。
  Future<dynamic> _sendWithRetry(
    Future<http.Response> Function() request, {
    int maxRetries = 2,
    bool allowRetry = true,
  }) async {
    final attempts = allowRetry ? maxRetries : 0;
    for (var attempt = 0; attempt <= attempts; attempt++) {
      try {
        // http 包没有内置超时：挂起的连接会无限等待，重试逻辑也永远不会触发。
        final response = await request().timeout(_requestTimeout);
        // 5xx 服务器错误可重试
        if (response.statusCode >= 500 && attempt < attempts) {
          await Future.delayed(Duration(milliseconds: 500 * (1 << attempt)));
          continue;
        }
        return await _processResponse(response);
      } on http.ClientException {
        // 网络连接异常（连接失败、断网等），重试
        if (attempt < attempts) {
          await Future.delayed(Duration(milliseconds: 500 * (1 << attempt)));
          continue;
        }
        rethrow;
      } on TimeoutException {
        // 请求超时（服务器挂起/网络极慢），重试
        if (attempt < attempts) {
          await Future.delayed(Duration(milliseconds: 500 * (1 << attempt)));
          continue;
        }
        throw ApiException('请求超时（>${_requestTimeout.inSeconds}s）');
      } on FormatException {
        // 非 5xx 的格式异常不重试
        rethrow;
      }
    }
    // 理论上不会到达这里，但为了保证编译器认为有返回值
    throw ApiException('请求失败，已重试 $attempts 次');
  }

  /// 处理响应：更新 sessionId、校验状态码、解码 JSON。
  Future<dynamic> _processResponse(http.Response response) {
    final responseSessionId = response.headers['x-kg-session-id'];
    if (responseSessionId != null && responseSessionId.isNotEmpty) {
      sessionId = responseSessionId;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.body, statusCode: response.statusCode);
    }
    if (response.body.trim().isEmpty) {
      return Future.value(null);
    }
    try {
      final decoded = jsonDecode(response.body);
      return Future.value(unwrapData(decoded));
    } on FormatException {
      return Future.value(response.body);
    }
  }

  void close() => _client.close();
}

dynamic unwrapData(dynamic json) {
  if (json is Map<String, dynamic>) {
    final data = json['data'];
    if (data != null) {
      return data;
    }
  }
  return json;
}
