
import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:sqflite/sqlite_api.dart';
import 'package:path/path.dart';

/// 网络请求缓存层
///
/// 注意，该对象业务层不需要关心
///
/// 这里存储请求对应的服务端缓存数据
/// 如何确认是同一个请求？即：
/// key = MD5(url + params)
class APNetworkCache {
  
  /// 单例
  factory APNetworkCache({int lruCacheSize = 100, APNetworkCacheDB mockDB}) {
    return _getInstance(lruCacheSize: lruCacheSize, mockDB: mockDB);
  }
  
  static APNetworkCache get instance => _getInstance(lruCacheSize: 100);
  static APNetworkCache _instance;
  
  static APNetworkCache _getInstance({int lruCacheSize, APNetworkCacheDB mockDB}) {
    if (_instance == null) {
      _instance = APNetworkCache._init(lruCacheSize: lruCacheSize, mockDB: mockDB);
    }
    return _instance;
  }
  
  static void release() {
    _instance = null;
  }
  
  /// 初始化完成标记
  bool _initOk;
  
  /// 持久化缓存管理
  APNetworkCacheDB _db;
  
  /// LRU缓存
  _LRUCache<String, _CacheData> _lruCache;
  
  /// 独立缓存
  Map<String, _CacheData> _normalCache;

  /// ------------------- 初始化 ---------------------
  
  APNetworkCache._init({int lruCacheSize, APNetworkCacheDB mockDB}) {
    _initOk = false;
    _lruCache = _LRUCache<String, _CacheData>(cacheSize: lruCacheSize);
    _normalCache = Map<String, _CacheData>();
    _db = mockDB ?? APNetworkCacheDB();
  }
  
  /// 数据初始化，加载本地缓存
  Future<void> initSetup() async {
    
    await _db.initSetup();

    // 设置LRU的上限移除监听
    _lruCache.evictionHandler = (_CacheData data) {
      _db.delete(data.key);
    };

    // 加载LRU缓存
    List<_CacheData> lruDatas = await _db.getAll(isLRU: true);
    if (lruDatas != null && lruDatas.length > 0) {
      for (_CacheData data in lruDatas) {
        _lruCache[data.key] = data;
      }
    }
    
    // 加载普通缓存
    List<_CacheData> normalDatas = await _db.getAll(isLRU: false);
    if (normalDatas != null && normalDatas.length > 0) {
      for (_CacheData data in normalDatas) {
        _normalCache[data.key] = data;
      }
    }
    
    _initOk = true;
  }
  
  /// 添加缓存
  ///
  /// 如果缓存达到上限，会移除最不常用的
  Future<void> saveCache(
      String key,
      Map<String, dynamic> data,
      {Duration duration, bool useLRU = true}) async {
    
    if (key == null || !(key is String)
        || data == null || !(data is Map)) {
      return;
    }
    
    if (_initOk == false) return;
    
    // 查看是否有老数据
    _CacheData oldData;
    if (useLRU == true) {
      oldData = _lruCache[key];
    }
    else {
      oldData = _normalCache[key];
    }
    
    // 新的数据
    _CacheData cacheData = _CacheData.newData(
        key: key,
        data: data,
        isLRUCache: useLRU,
        duration: duration
    );
    if (useLRU == true) {
      _lruCache[key] = cacheData;
    }
    else {
      _normalCache[key] = cacheData;
    }
    
    if (oldData == null) {
      await _db.insert(cacheData);
    }
    else {
      await _db.update(cacheData);
    }
  }
  
  /// 加载缓存
  ///
  /// 如果缓存有时限，若时限已到，则返回null，并移除
  Map<String, dynamic> loadCache(String key, {bool useLRU = true}) {
  
    if (key == null || !(key is String)) return null;
    if (_initOk == false) return null;
    
    _CacheData cacheData;
    if (useLRU == true) {
      cacheData = _lruCache[key];
    }
    else {
      cacheData = _normalCache[key];
    }
    
    if (cacheData?.isExpire == true) {
      if (useLRU) {
        _lruCache.remove(key);
      }
      else {
        _normalCache.remove(key);
      }
      return null;
    }
    
    return cacheData?.data;
  }
  
  /// 清空所有缓存
  ///
  /// 比如登出的时候
  Future<void> cleanCache() async {
    _lruCache.clearAll();
    _normalCache.clear();
    await _db.deleteAll();
  }
}

/// 缓存数据体
class _CacheData {
  
  /// 所属request的md5Key
  String key;
  
  /// 缓存数据，来自服务端的原始数据
  Map<String, dynamic> data;
  
  /// 是否是LRU缓存
  bool isLRUCache;
  
  /// 缓存创建时间
  DateTime createTime;
  
  /// 缓存持续时间，秒
  Duration duration;
  
  /// 缓存是否失效
  bool get isExpire {
    if (duration == null) return false;
    if (createTime?.add(duration)?.isBefore(DateTime.now()) == true) return true;
    return false;
  }
  
  _CacheData.newData({this.key, this.data, this.isLRUCache, this.duration}) {
    this.data = data;
    this.createTime = DateTime.now();
  }
  
  _CacheData.fromSQLiteMap(Map<String, dynamic> map) {
    
    key = map[APNetworkCacheDB.ColumnId];
    data = json.decode(map[APNetworkCacheDB.ColumnData]);
    isLRUCache = map[APNetworkCacheDB.ColumnIsLRU] == 1 ? true : false;
    createTime = DateTime.parse(map[APNetworkCacheDB.ColumnCreateTime]);
    if (map[APNetworkCacheDB.ColumnDuration] != null) {
      duration = Duration(seconds: map[APNetworkCacheDB.ColumnDuration]);
    }
  }
  
  Map<String, dynamic> toSQLiteMap() {
    
    Map<String, dynamic> map = Map();
    map[APNetworkCacheDB.ColumnId] = key;
    map[APNetworkCacheDB.ColumnData] = json.encode(data);
    map[APNetworkCacheDB.ColumnIsLRU] = isLRUCache == true ? 1 : 0;
    map[APNetworkCacheDB.ColumnCreateTime] = createTime.toString();
    if (duration != null) {
      map[APNetworkCacheDB.ColumnDuration] = duration.inSeconds;
    }
    return map;
  }
}

/// LRU缓存器
class _LRUCache<K, V> {
  /// 有序哈希表
  final LinkedHashMap<K, V> _map = new LinkedHashMap<K, V>();
  
  /// 缓存总大小
  final int cacheSize;
  
  /// 当前缓存大小
  int get currentSize => _map.length;
  
  /// 移除处理通知（达到上限时，移除最不常用的）
  void Function(V value) evictionHandler;
  
  _LRUCache({this.cacheSize = 100});
  
  /// 取数据
  ///
  /// 保证取了后，该数据重新置顶，更新新鲜度
  V get(K key) {
    V value = _map.remove(key);
    if (value != null) {
      _map[key] = value;
    }
    return value;
  }
  
  /// 放数据
  ///
  /// 新数据一定位于顶部
  void put(K key, V value) {
    _map.remove(key);
    _map[key] = value;
    
    // 如果超出上限，移除末尾最不常用的数据
    if (_map.length > cacheSize) {
      V removeValue = _map.remove(_map.keys.first);
      if (removeValue != null && evictionHandler != null) {
        evictionHandler(removeValue);
      }
    }
  }
  
  /// []下标操作，运算符重载
  V operator [](K key) {
    return get(key);
  }
  
  /// []=下标赋值操作，运算符重载
  void operator []=(K key, V value) {
    if (value == null) {
      remove(key);
    } else {
      put(key, value);
    }
  }
  
  /// 删除数据
  void remove(K key) {
    _map.remove(key);
  }
  
  /// 清除所有数据
  void clearAll() {
    _map.clear();
  }
}

/// Cache的本地持久化存储
class APNetworkCacheDB {
  /// 数据库版本号
  static const int Version = 1000;
  
  /// 表名
  static const String Table = "cache";
  
  /// 列名 - Id - 主键(cache的md5Key)
  static const String ColumnId = "id";
  
  /// 列名 - 数据
  static const String ColumnData = "data";
  
  /// 列名 - 是否是LRU缓存
  static const String ColumnIsLRU = 'is_lru';
  
  /// 列名 - 创建时间
  static const String ColumnCreateTime = "create_time";
  
  /// 列名 - 有效时间（秒）
  static const String ColumnDuration = "duration";
  
  /// 所有列
  static List<String> get allColumns =>
      [ColumnId, ColumnData, ColumnIsLRU, ColumnCreateTime, ColumnDuration];
  
  /// 数据库对象
  Database db;
  
  /// 初始化设置
  Future<void> initSetup() async {
    String path = await getDatabasesPath();
    path = join(path, 'ap_network_cache.db');
    // 打开数据
    db = await openDatabase(path,
        version: Version, onCreate: _onCreate, onUpgrade: _versionUpgrade);
  }
  
  /// 初始化创建
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      create table $Table (
        $ColumnId varchar(64) primary key,
        $ColumnData text not null,
        $ColumnIsLRU tinyint not null,
        $ColumnCreateTime varchar(32) not null,
        $ColumnDuration integer
      )
      ''');
  }
  
  /// 版本迁移处理
  void _versionUpgrade(Database db, int oldVersion, int newVersion) {}
  
  /// 增
  Future<void> insert(_CacheData cache, {bool isLRU = true}) async {
    
    try {
      await db.insert(Table, cache.toSQLiteMap());
    }
    catch (e) {
      if (e is DatabaseException) {
        DatabaseException databaseException = e;
        if (databaseException.isUniqueConstraintError()) {
          update(cache);
        }
      }
    }
  }
  
  /// 删 - 单个Profile
  Future<void> delete(String id) async {
    try {
      await db.delete(Table, where: '$ColumnId = ?', whereArgs: [id]);
    }
    catch (e) {}
  }
  
  /// 删 - 所有Profile
  Future<void> deleteAll() async {
    try {
      await db.delete(Table);
    }
    catch (e) {}
  }
  
  /// 改
  Future<void> update(_CacheData cache) async {
    try {
      await db.update(Table, cache.toSQLiteMap(),
          where: '$ColumnId = ?', whereArgs: [cache.key]);
    }
    catch (e) {}
  }
  
  /// 查 - 单个Profile
  Future<_CacheData> get(String id) async {
    try {
      List<Map> maps = await db.query(
          Table,
          columns: allColumns,
          where: '$ColumnId = ?',
          whereArgs: [id]);
      
      if (maps.length > 0) {
        return _CacheData.fromSQLiteMap(maps.first);
      }
      return null;
    }
    catch (e) {
      return null;
    }
  }
  
  /// 查 - 所有Profile
  Future<List<_CacheData>> getAll({bool isLRU}) async {
    
    if (isLRU == null) return null;
    try {
      
      List<Map> maps = await db.query(
        Table,
        columns: allColumns,
        where: '$ColumnIsLRU = ?',
        whereArgs: [isLRU == true ? 1 : 0]
      );
      if (maps.length > 0) {
        
        List<_CacheData> list = [];
        for (Map map in maps) {
          _CacheData cache = _CacheData.fromSQLiteMap(map);
          if (cache != null) {
            list.add(cache);
          }
        }
        return list;
      }
      return [];
    }
    catch (e) {
      return [];
    }
  }
}