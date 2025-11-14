import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import '../models/camera_settings.dart';
import '../models/file_info.dart';
import 'logger_service.dart';

class ApiService {
  final String baseUrl;
  final String host;
  final int port;
  final ClientLoggerService logger = ClientLoggerService();
  late final HttpClient _httpClient;

  ApiService({
    required String host,
    required int port,
  }) : baseUrl = 'http://$host:$port',
       host = host,
       port = port {
    // 创建自定义的HttpClient，强制使用IPv4
    _httpClient = HttpClient();
    _httpClient.autoUncompress = true;
    _httpClient.connectionTimeout = const Duration(seconds: 3); // 缩短连接超时时间
    _httpClient.idleTimeout = const Duration(seconds: 5); // 设置空闲超时
  }

  // 释放资源
  void dispose() {
    _httpClient.close(force: true);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
      };

  // 发送HTTP请求的通用方法
  Future<Map<String, dynamic>> _sendRequest({
    required String method,
    required String path,
    Map<String, String>? headers,
    String? body,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      logger.log('尝试连接到: $uri', tag: 'CONNECTION');
      
      // 强制使用IPv4解析
      final addresses = await InternetAddress.lookup(host, type: InternetAddressType.IPv4);
      if (addresses.isEmpty) {
        throw Exception('无法解析主机地址: $host');
      }
      
      final request = await _httpClient.openUrl(method, uri);
      request.headers.set('Content-Type', 'application/json');
      if (headers != null) {
        headers.forEach((key, value) {
          request.headers.set(key, value);
        });
      }
      
      if (body != null) {
        request.write(body);
      }
      
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      
      logger.log('响应状态码: ${response.statusCode}', tag: 'CONNECTION');
      
      if (response.statusCode == 200 || response.statusCode == 206) {
        try {
          return json.decode(responseBody) as Map<String, dynamic>;
        } catch (e) {
          return {'success': true, 'data': responseBody};
        }
      } else {
        try {
          return json.decode(responseBody) as Map<String, dynamic>;
        } catch (e) {
          return {
            'success': false,
            'error': 'HTTP ${response.statusCode}: ${response.reasonPhrase}'
          };
        }
      }
    } catch (e, stackTrace) {
      logger.logError('请求失败: $method $path', error: e, stackTrace: stackTrace);
      logger.log('连接错误详情: $e', tag: 'CONNECTION');
      return {'success': false, 'error': e.toString()};
    }
  }

  // 测试连接
  Future<bool> ping() async {
    try {
      logger.logCommand('ping', details: '测试服务器连接');
      logger.logApiCall('GET', '/ping');
      logger.log('尝试连接到: $baseUrl/ping', tag: 'CONNECTION');
      
      // 强制使用IPv4解析
      final addresses = await InternetAddress.lookup(host, type: InternetAddressType.IPv4);
      if (addresses.isEmpty) {
        logger.logError('无法解析主机地址', error: Exception('无法解析: $host'));
        logger.logCommandResponse('ping', success: false, error: '无法解析主机地址: $host');
        return false;
      }
      
      final uri = Uri.parse('$baseUrl/ping');
      // 使用超时包装，确保快速失败
      final request = await _httpClient.getUrl(uri).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          throw TimeoutException('Ping超时', const Duration(seconds: 3));
        },
      );
      final response = await request.close().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          throw TimeoutException('响应超时', const Duration(seconds: 3));
        },
      );
      final responseBody = await response.transform(utf8.decoder).join().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          throw TimeoutException('读取响应超时', const Duration(seconds: 2));
        },
      );
      
      logger.logApiResponse('/ping', response.statusCode, body: responseBody);
      final success = response.statusCode == 200 && responseBody.trim() == 'pong';
      logger.log('Ping结果: $success (状态码: ${response.statusCode}, 响应: ${responseBody.trim()})', tag: 'CONNECTION');
      logger.logCommandResponse('ping', success: success, result: {'statusCode': response.statusCode, 'response': responseBody});
      return success;
    } catch (e, stackTrace) {
      logger.logError('Ping失败', error: e, stackTrace: stackTrace);
      logger.log('连接错误详情: $e', tag: 'CONNECTION');
      logger.logCommandResponse('ping', success: false, error: e.toString());
      return false;
    }
  }

  // 拍照
  Future<Map<String, dynamic>> capture() async {
    try {
      logger.logCommand('capture', details: '拍照指令');
      logger.logApiCall('POST', '/capture', headers: _headers);
      final result = await _sendRequest(
        method: 'POST',
        path: '/capture',
        headers: _headers,
      );
      final statusCode = result['success'] == true ? 200 : 500;
      logger.logApiResponse('/capture', statusCode, body: result, error: result['success'] == false ? result['error'] : null);
      logger.logCommandResponse('capture', success: result['success'] == true, result: result, error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('拍照请求失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('capture', success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  // 开始录像
  Future<Map<String, dynamic>> startRecording() async {
    try {
      logger.logCommand('startRecording', details: '开始录像指令');
      logger.logApiCall('POST', '/recording/start', headers: _headers);
      final result = await _sendRequest(
        method: 'POST',
        path: '/recording/start',
        headers: _headers,
      );
      final statusCode = result['success'] == true ? 200 : 500;
      logger.logApiResponse('/recording/start', statusCode, body: result, error: result['success'] == false ? result['error'] : null);
      logger.logCommandResponse('startRecording', success: result['success'] == true, result: result, error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('开始录像请求失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('startRecording', success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  // 停止录像
  Future<Map<String, dynamic>> stopRecording() async {
    try {
      logger.logCommand('stopRecording', details: '停止录像指令');
      logger.logApiCall('POST', '/recording/stop', headers: _headers);
      final result = await _sendRequest(
        method: 'POST',
        path: '/recording/stop',
        headers: _headers,
      );
      final statusCode = result['success'] == true ? 200 : 500;
      logger.logApiResponse('/recording/stop', statusCode, body: result, error: result['success'] == false ? result['error'] : null);
      logger.logCommandResponse('stopRecording', success: result['success'] == true, result: result, error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('停止录像请求失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('stopRecording', success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  // 获取文件列表
  Future<Map<String, dynamic>> getFileList() async {
    try {
      logger.logCommand('getFileList', details: '获取文件列表指令');
      logger.logApiCall('GET', '/files', headers: _headers);
      final result = await _sendRequest(
        method: 'GET',
        path: '/files',
        headers: _headers,
      );
      
      if (result['success']) {
        // 将JSON转换为FileInfo对象
        result['pictures'] = (result['pictures'] as List)
            .map((json) => FileInfo.fromJson(json))
            .toList();
        result['videos'] = (result['videos'] as List)
            .map((json) => FileInfo.fromJson(json))
            .toList();
      }
      
      final statusCode = result['success'] == true ? 200 : 500;
      logger.logApiResponse('/files', statusCode, body: {'pictures_count': (result['pictures'] as List?)?.length ?? 0, 'videos_count': (result['videos'] as List?)?.length ?? 0}, error: result['success'] == false ? result['error'] : null);
      logger.logCommandResponse('getFileList', success: result['success'] == true, result: {'pictures_count': (result['pictures'] as List?)?.length ?? 0, 'videos_count': (result['videos'] as List?)?.length ?? 0}, error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('获取文件列表失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('getFileList', success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  // 删除文件
  Future<Map<String, dynamic>> deleteFile(String remotePath) async {
    try {
      logger.logCommand('deleteFile', params: {'path': remotePath}, details: '删除文件指令');
      final uri = Uri.parse('$baseUrl/file/delete')
          .replace(queryParameters: {'path': remotePath});
      logger.logApiCall('DELETE', uri.path + (uri.query.isNotEmpty ? '?${uri.query}' : ''), params: {'path': remotePath}, headers: _headers);
      final result = await _sendRequest(
        method: 'DELETE',
        path: uri.path + (uri.query.isNotEmpty ? '?${uri.query}' : ''),
        headers: _headers,
      );
      final statusCode = result['success'] == true ? 200 : 500;
      logger.logApiResponse('/file/delete', statusCode, body: result, error: result['success'] == false ? result['error'] : null);
      logger.logCommandResponse('deleteFile', success: result['success'] == true, result: result, error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('删除文件失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('deleteFile', success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  // 获取设置状态
  Future<Map<String, dynamic>> getSettingsStatus() async {
    try {
      logger.logCommand('getSettingsStatus', details: '获取设置状态指令');
      logger.logApiCall('GET', '/settings/status', headers: _headers);
      final result = await _sendRequest(
        method: 'GET',
        path: '/settings/status',
        headers: _headers,
      );
      final statusCode = result['success'] == true ? 200 : 500;
      logger.logApiResponse('/settings/status', statusCode, body: result, error: result['success'] == false ? result['error'] : null);
      logger.logCommandResponse('getSettingsStatus', success: result['success'] == true, result: result, error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('获取设置状态失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('getSettingsStatus', success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  // 更新设置
  Future<Map<String, dynamic>> updateSettings(CameraSettings settings) async {
    try {
      logger.logCommand('updateSettings', params: settings.toJson(), details: '更新相机设置');
      final body = json.encode(settings.toJson());
      logger.logApiCall('POST', '/settings/update', headers: _headers, body: body);
      final result = await _sendRequest(
        method: 'POST',
        path: '/settings/update',
        headers: _headers,
        body: body,
      );
      final statusCode = result['success'] == true ? 200 : 500;
      logger.logApiResponse('/settings/update', statusCode, body: result, error: result['success'] == false ? result['error'] : null);
      logger.logCommandResponse('updateSettings', success: result['success'] == true, result: result, error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('更新设置失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('updateSettings', success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  // 获取当前设置
  Future<Map<String, dynamic>> getSettings() async {
    try {
      logger.logCommand('getSettings', details: '获取相机设置指令');
      logger.logApiCall('GET', '/settings', headers: _headers);
      final result = await _sendRequest(
        method: 'GET',
        path: '/settings',
        headers: _headers,
      );
      
      if (result['success'] && result['settings'] != null) {
        result['settings'] = CameraSettings.fromJson(result['settings']);
      }
      
      final statusCode = result['success'] == true ? 200 : 500;
      logger.logApiResponse('/settings', statusCode, body: result['settings'], error: result['success'] == false ? result['error'] : null);
      logger.logCommandResponse('getSettings', success: result['success'] == true, result: result['settings'], error: result['error']);
      return result;
    } catch (e, stackTrace) {
      logger.logError('获取设置失败', error: e, stackTrace: stackTrace);
      logger.logCommandResponse('getSettings', success: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  // 获取预览流URL
  String getPreviewStreamUrl() {
    return '$baseUrl/preview/stream';
  }

  // 获取文件下载URL
  String getFileDownloadUrl(String remotePath) {
    return '$baseUrl/file/download?path=${Uri.encodeComponent(remotePath)}';
  }

  // 获取缩略图URL（支持照片和视频）
  String getThumbnailUrl(String remotePath, bool isVideo) {
    return '$baseUrl/file/thumbnail?path=${Uri.encodeComponent(remotePath)}&type=${isVideo ? 'video' : 'image'}';
  }

  // 下载缩略图（支持照片和视频）
  Future<Uint8List?> downloadThumbnail(String remotePath, bool isVideo) async {
    try {
      final uri = Uri.parse(getThumbnailUrl(remotePath, isVideo));
      final request = await _httpClient.getUrl(uri);
      final response = await request.close();
      
      if (response.statusCode == 200) {
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
        }
        return Uint8List.fromList(bytes);
      }
      return null;
    } catch (e) {
      logger.logError('下载缩略图失败', error: e);
      return null;
    }
  }
}

