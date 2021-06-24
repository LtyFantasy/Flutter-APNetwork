
import 'dart:convert';

import 'ap_http_request.dart';

import 'package:sqflite/sqflite.dart';
import 'package:sqflite/sqlite_api.dart';
import 'package:path/path.dart';

/// Promise持久化存储
///
/// 注意，该对象业务层不需要关心
class APNetworkPromise {
  
  late APNetworkPromiseDB _db;
  
  /// 业务线Promise队列映射
  late Map<String?, List<APHttpRequest>> _businessMap;
  
  /// 单例
  factory APNetworkPromise({APNetworkPromiseDB? mockDB}) {
    return _getInstance(mockDB: mockDB)!;
  }
  
  static APNetworkPromise? get instance => _getInstance();
  static APNetworkPromise? _instance;
  
  static APNetworkPromise? _getInstance({APNetworkPromiseDB? mockDB}) {
    if (_instance == null) {
      _instance = APNetworkPromise._init(mockDB: mockDB);
    }
    return _instance;
  }

  APNetworkPromise._init({APNetworkPromiseDB? mockDB}) {
    _db = mockDB ?? APNetworkPromiseDB();
    _businessMap = Map();
  }

  /// ------------------- 初始化 ---------------------
  
  // 加载之前的缓存数据
  Future<void> initSetup() async {
    
    await _db.initSetup();
    List<APHttpRequest> requestList = await _db.getAll();
    if (requestList.length == 0) return;
    // 按照业务线分类，加载到Map中
    for (APHttpRequest request in requestList) {
      
      List<APHttpRequest>? list = _businessMap[request.businessIdentifier];
      if (list == null) {
        list = List.empty(growable: true);
        _businessMap[request.businessIdentifier] = list;
      }
      list.add(request);
    }
  }
  
  /// ------------------- 数据操作 ---------------------

  /// 存储请求到Promise队列中
  ///
  /// 队列和Business挂钩
  Future<void> saveRequest(APHttpRequest request) async {
    
    List<APHttpRequest>? list = _businessMap[request.businessIdentifier];
    if (list == null) {
      list = List.empty(growable: true);
      _businessMap[request.businessIdentifier] = list;
    }
    
    list.add(request);
    return _db.insert(request);
  }
  
  /// 获取请求队列
  ///
  /// @param: businessIdentifier 业务线识别码
  /// @param: paths 请求的path数组，用来判定具体是什么请求
  List<APHttpRequest>? loadBusinessRequests(String businessIdentifier, {List<String>? paths}) {
    
    List<APHttpRequest>? list = _businessMap[businessIdentifier];
    if (paths == null || paths.length == 0) return list;
    if (list == null) return null;

    List<APHttpRequest> result = List.empty(growable: true);
    // Path对得上的，放入list
    for (APHttpRequest request in list) {
      if (paths.contains(request.apiPath)) {
        result.add(request);
      }
    }
    
    return result;
  }
  
  /// 删除指定的请求
  Future<void> deleteRequestWithKey(String? businessIdentifier, String? promiseKey) async {
    
    if (businessIdentifier == null) return;
    List<APHttpRequest> list = _businessMap[businessIdentifier]!;
    list.removeWhere((request) => request.promise.key == promiseKey);
    await _db.delete(promiseKey);
  }
  
  /// 清空数据
  Future<void> cleanAll() async {
    _businessMap.clear();
    await _db.deleteAll();
  }
}

/// Cache的本地持久化存储
class APNetworkPromiseDB {
  /// 数据库版本号
  static const int Version = 1000;
  
  /// 表名
  static const String Table = "promise";
  
  /// 列名 - Id - 主键(promiseKey)
  static const String ColumnId = "id";

  /// 列名 - 业务线识别码
  static const String ColumnBusiness = 'business_id';

  /// 列名 - Path请求路径
  static const String ColumnPath = 'path';
  
  /// 列名 - 数据
  static const String ColumnData = "data";
  
  /// 所有列
  static List<String> get allColumns =>
      [ColumnId, ColumnBusiness, ColumnPath, ColumnData];
  
  /// 数据库对象
  late Database db;
  
  /// 初始化设置
  Future<void> initSetup() async {
    String path = await getDatabasesPath();
    path = join(path, 'ap_network_promise.db');
    // 打开数据
    db = await openDatabase(path,
        version: Version, onCreate: _onCreate, onUpgrade: _versionUpgrade);
  }
  
  /// 初始化创建
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      create table $Table (
        $ColumnId varchar(64) primary key,
        $ColumnBusiness varchar(64) not null,
        $ColumnPath varchar(128) not null,
        $ColumnData text not null
      )
      ''');
  }
  
  /// 版本迁移处理
  void _versionUpgrade(Database db, int oldVersion, int newVersion) {}
  
  /// 增
  Future<void> insert(APHttpRequest request) async {
    
    try {
      await db.insert(Table, requestToMap(request));
    }
    catch (e) {
      if (e is DatabaseException) {
        DatabaseException databaseException = e;
        if (databaseException.isUniqueConstraintError()) {
          update(request);
        }
      }
    }
  }
  
  /// 改
  Future<void> update(APHttpRequest request) async {
    try {
      await db.update(Table, requestToMap(request),
          where: '$ColumnId = ?', whereArgs: [request.promise.key]);
    }
    catch (e) {}
  }

  /// 删 - 单个
  Future<void> delete(String? key) async {
    try {
      await db.delete(Table, where: '$ColumnId = ?', whereArgs: [key]);
    }
    catch (e) {}
  }

  /// 删 - 所有
  Future<void> deleteAll() async {
    try {
      await db.delete(Table);
    }
    catch (e) {}
  }

  /// 查 - 所有
  Future<List<APHttpRequest>> getAll() async {
    
    try {
    
      List<Map> maps = await db.query(Table);
      if (maps.length > 0) {
      
        List<APHttpRequest> list = [];
        for (Map map in maps) {
          APHttpRequest? request = APHttpRequest.fromMap(json.decode(map[ColumnData]));
          if (request != null) {
            list.add(request);
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
  

  Map<String, dynamic> requestToMap(APHttpRequest request) {
    Map<String, dynamic> map = Map();
    map[ColumnId] = request.promise.key;
    map[ColumnBusiness] = request.businessIdentifier;
    map[ColumnPath] = request.apiPath;
    map[ColumnData] = json.encode(request.toMap());
    return map;
  }
}