import '../../storage/database/app_database.dart';
import '../models/album.dart';

/// 相册数据仓库
class AlbumRepository {
  final AppDatabase _db;

  AlbumRepository({AppDatabase? db}) : _db = db ?? AppDatabase.instance;

  // ==================== 基础 CRUD ====================

  /// 创建相册
  Future<void> insert(Album album) => _db.insertAlbum(album);

  /// 更新相册
  Future<void> update(Album album) => _db.updateAlbum(album);

  /// 删除相册
  Future<void> delete(String id) => _db.deleteAlbum(id);

  /// 获取单个相册
  Future<Album?> getById(String id) => _db.getAlbum(id);

  // ==================== 查询 ====================

  /// 获取所有相册
  Future<List<Album>> getAll() => _db.getAllAlbums();

  /// 监听所有相册
  Stream<List<Album>> watchAll() => _db.watchAllAlbums();

  /// 获取用户创建的相册（排除系统相册）
  Future<List<Album>> getUserAlbums() async {
    final albums = await _db.getAllAlbums();
    return albums.where((a) => !a.isSystem).toList();
  }

  /// 获取系统相册
  Future<List<Album>> getSystemAlbums() async {
    final albums = await _db.getAllAlbums();
    return albums.where((a) => a.isSystem).toList();
  }

  /// 按类型获取相册
  Future<List<Album>> getByType(AlbumType type) async {
    final albums = await _db.getAllAlbums();
    return albums.where((a) => a.type == type).toList();
  }

  // ==================== 操作 ====================

  /// 更新相册封面
  Future<void> updateCover(String albumId, String? coverMediaId) async {
    final album = await _db.getAlbum(albumId);
    if (album != null) {
      await _db.updateAlbum(album.copyWith(
        coverMediaId: coverMediaId,
        modifiedAt: DateTime.now(),
      ));
    }
  }

  /// 更新相册媒体数量
  Future<void> updateMediaCount(String albumId, int count) async {
    final album = await _db.getAlbum(albumId);
    if (album != null) {
      await _db.updateAlbum(album.copyWith(
        mediaCount: count,
        modifiedAt: DateTime.now(),
      ));
    }
  }

  /// 重命名相册
  Future<void> rename(String albumId, String newName) async {
    final album = await _db.getAlbum(albumId);
    if (album != null && !album.isSystem) {
      await _db.updateAlbum(album.copyWith(
        name: newName,
        modifiedAt: DateTime.now(),
      ));
    }
  }
}
