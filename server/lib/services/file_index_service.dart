import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/file_info.dart';
import 'logger_service.dart';

/// 文件索引服务：记录保存到相册的文件信息
class FileIndexService {
  static const String _dbName = 'file_index.db';
  static const String _tableName = 'files';
  static const int _dbVersion = 1;
  
  Database? _database;
  final LoggerService _logger = LoggerService();

  /// 初始化数据库
  Future<void> initialize() async {
    try {
      final dbPath = await _getDatabasePath();
      _database = await openDatabase(
        dbPath,
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
      _logger.log('文件索引数据库已初始化', tag: 'FILE_INDEX');
    } catch (e, stackTrace) {
      _logger.logError('初始化文件索引数据库失败', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// 获取数据库路径
  Future<String> _getDatabasePath() async {
    final appDir = await getApplicationDocumentsDirectory();
    return path.join(appDir.path, _dbName);
  }

  /// 创建数据库表
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        gallery_path TEXT NOT NULL,
        file_type TEXT NOT NULL,
        size INTEGER NOT NULL,
        created_time INTEGER NOT NULL,
        modified_time INTEGER NOT NULL,
        UNIQUE(gallery_path)
      )
    ''');
    _logger.log('文件索引表已创建', tag: 'FILE_INDEX');
  }

  /// 数据库升级
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 未来版本升级逻辑
  }

  /// 添加文件索引
  Future<void> addFile({
    required String name,
    required String galleryPath,
    required String fileType, // 'image' or 'video'
    required int size,
    required DateTime createdTime,
    required DateTime modifiedTime,
  }) async {
    if (_database == null) {
      await initialize();
    }

    try {
      await _database!.insert(
        _tableName,
        {
          'name': name,
          'gallery_path': galleryPath,
          'file_type': fileType,
          'size': size,
          'created_time': createdTime.millisecondsSinceEpoch,
          'modified_time': modifiedTime.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      _logger.log('文件索引已添加: $name', tag: 'FILE_INDEX');
    } catch (e, stackTrace) {
      _logger.logError('添加文件索引失败', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// 获取文件列表（支持分页和增量获取）
  /// [page] 页码，从1开始
  /// [pageSize] 每页大小
  /// [since] 增量获取：只获取该时间之后新增/修改的文件（时间戳，毫秒）
  Future<Map<String, dynamic>> getFileList({
    int? page,
    int? pageSize,
    int? since,
  }) async {
    if (_database == null) {
      await initialize();
    }

    try {
      // 构建查询条件
      String? whereClause;
      List<dynamic>? whereArgs;
      
      if (since != null) {
        whereClause = 'modified_time >= ?';
        whereArgs = [since];
      }
      
      // 先获取总数（用于分页）
      final countResult = await _database!.rawQuery(
        'SELECT COUNT(*) as count FROM $_tableName${whereClause != null ? ' WHERE $whereClause' : ''}',
        whereArgs,
      );
      final totalCount = countResult.first['count'] as int;
      
      // 构建查询
      var query = _database!.query(
        _tableName,
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'modified_time DESC',
      );
      
      // 应用分页
      if (page != null && pageSize != null) {
        final offset = (page - 1) * pageSize;
        query = _database!.query(
          _tableName,
          where: whereClause,
          whereArgs: whereArgs,
          orderBy: 'modified_time DESC',
          limit: pageSize,
          offset: offset,
        );
      }
      
      final List<Map<String, dynamic>> maps = await query;

      final List<FileInfo> pictures = [];
      final List<FileInfo> videos = [];

      for (var map in maps) {
        final galleryPath = map['gallery_path'] as String;
        
        // 验证文件是否仍然存在
        final file = File(galleryPath);
        if (!await file.exists()) {
          // 文件不存在，从索引中删除
          await _database!.delete(_tableName, where: 'gallery_path = ?', whereArgs: [galleryPath]);
          continue;
        }

        final fileInfo = FileInfo(
          name: map['name'] as String,
          path: galleryPath, // 使用相册路径
          size: map['size'] as int,
          createdTime: DateTime.fromMillisecondsSinceEpoch(map['created_time'] as int),
          modifiedTime: DateTime.fromMillisecondsSinceEpoch(map['modified_time'] as int),
        );

        if (map['file_type'] == 'image') {
          pictures.add(fileInfo);
        } else if (map['file_type'] == 'video') {
          videos.add(fileInfo);
        }
      }

      // 计算分页信息
      final hasMore = page != null && pageSize != null 
          ? (page * pageSize < totalCount)
          : false;
      final totalPages = page != null && pageSize != null
          ? ((totalCount + pageSize - 1) ~/ pageSize)
          : 1;

      return {
        'pictures': pictures,
        'videos': videos,
        'total': totalCount,
        'page': page ?? 1,
        'pageSize': pageSize ?? totalCount,
        'totalPages': totalPages,
        'hasMore': hasMore,
      };
    } catch (e, stackTrace) {
      _logger.logError('获取文件列表失败', error: e, stackTrace: stackTrace);
      return {
        'pictures': <FileInfo>[],
        'videos': <FileInfo>[],
        'total': 0,
        'page': 1,
        'pageSize': 0,
        'totalPages': 0,
        'hasMore': false,
      };
    }
  }
  
  /// 获取文件列表（兼容旧接口）
  Future<Map<String, List<FileInfo>>> getFileListLegacy() async {
    final result = await getFileList();
    return {
      'pictures': result['pictures'] as List<FileInfo>,
      'videos': result['videos'] as List<FileInfo>,
    };
  }

  /// 根据文件名获取文件信息
  Future<FileInfo?> getFileByName(String fileName) async {
    if (_database == null) {
      await initialize();
    }

    try {
      final maps = await _database!.query(
        _tableName,
        where: 'name = ?',
        whereArgs: [fileName],
        limit: 1,
      );

      if (maps.isEmpty) {
        return null;
      }

      final map = maps.first;
      final galleryPath = map['gallery_path'] as String;
      
      // 验证文件是否仍然存在
      final file = File(galleryPath);
      if (!await file.exists()) {
        // 文件不存在，从索引中删除
        await _database!.delete(_tableName, where: 'gallery_path = ?', whereArgs: [galleryPath]);
        return null;
      }

      return FileInfo(
        name: map['name'] as String,
        path: galleryPath,
        size: map['size'] as int,
        createdTime: DateTime.fromMillisecondsSinceEpoch(map['created_time'] as int),
        modifiedTime: DateTime.fromMillisecondsSinceEpoch(map['modified_time'] as int),
      );
    } catch (e, stackTrace) {
      _logger.logError('根据文件名获取文件信息失败', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// 删除文件索引
  Future<void> deleteFile(String galleryPath) async {
    if (_database == null) {
      await initialize();
    }

    try {
      await _database!.delete(
        _tableName,
        where: 'gallery_path = ?',
        whereArgs: [galleryPath],
      );
      _logger.log('文件索引已删除: $galleryPath', tag: 'FILE_INDEX');
    } catch (e, stackTrace) {
      _logger.logError('删除文件索引失败', error: e, stackTrace: stackTrace);
    }
  }

  /// 关闭数据库
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}

