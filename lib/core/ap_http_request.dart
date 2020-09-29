
import 'dart:async';
import 'dart:convert';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:uuid/uuid.dart';
import 'ap_http_model.dart';
import 'ap_http_response.dart';

typedef ModelConverter<T extends APHttpModel> = T Function(Map<String, dynamic> map);

enum _APHttpRequestDataType {
  Map,
  String,
  Other,
}

/// 网络通信请求体
///
/// 包含的内容：
/// 1，接口地址，参数
/// 2，上传下载进度监控
/// 3，返回值Future
///
/// 对于业务层，await HttpRequest.response即可等待获取返回结果
class APHttpRequest<T extends APHttpModel> {
  
  /// 请求所属业务线
  final String businessIdentifier;
  
  /// 接口请求路径，不包含基地址，eg: /user
  final String apiPath;
  
  /// 请求路径参数，如 /:userId/like
  final String pathParam;
  
  /// 请求的发起URL
  ///
  /// 如果[pathParam]为null，则就是apiPath
  /// 否则，就是两者的组合，eg: /user/:userId/like
  final String _path;
  String get path => _path;
  
  /// 请求参数 - Query
  final Map<String, dynamic> queryParams;
  
  /// 请求参数 - Data
  ///
  /// 绝大多数接口，都是json，即Map<String,dynamic
  /// 上传接口，是FormData对象
  final dynamic data;
  
  /// 请求参数的类型
  ///
  /// 有的请求是Map参数，有的是String参数
  _APHttpRequestDataType _dataType;
  
  /// 对应的返回数据模型的转换器
  ModelConverter<T> converter;
  
  /// 用于撤销请求，多个请求可以绑定同一个cancelToken实现批量取消
  final CancelToken cancelToken;
  
  /// Dio请求相关配置
  final Options dioOptions;

  /// 发送进度回调
  ProgressCallback onSendProgress;

  /// 接收进度回调
  ProgressCallback onRecvProgress;
  
  /// 返回数据Completer
  final Completer<APHttpResponse<T>> _completer = Completer();
  bool get isComplete => _completer.isCompleted;
  Future<APHttpResponse<T>> get response => _completer.future;

  /// 请求发起起始时间，网络框架发起请求前会自动设置该值
  DateTime requestStartTime;
  
  /// 额外信息标记值
  ///
  /// 根据业务层需要，自行使用，网络框架本身不会使用该值
  int extraTag;

  /// ------------------ 请求体 附属功能 -------------------
  
  /// 重试能力
  final APHttpRequestRetry retry;

  /// 缓存能力
  final APHttpRequestCache<T> cache;

  /// Promise能力
  final APHttpRequestPromise promise;
  
  /// Mock能力
  final APHttpRequestMock mock;
  
  /// 不建议使用该构造方法，请使用下面的便捷构造
  APHttpRequest({
    this.businessIdentifier,
    String method,
    this.apiPath,
    this.pathParam,
    String contentType,
    ResponseType responseType,
    Map<String, dynamic> headers,
    this.queryParams,
    this.data,
    this.converter,
    CancelToken cancelToken,
    Duration sendTimeout,
    Duration recvTimeout,
    this.onSendProgress,
    this.onRecvProgress,
    // ----- 重试能力 -----
    APHTTPRequestRetryType retryType,
    int maxRetry,
    int retryIntervalMS,
    // ----- 缓存能力 -----
    bool cacheEnable,
    bool cacheUseLRU,
    bool cacheIgnoreOnce,
    Duration cacheDuration,
    // ----- Promise能力 -----
    bool promiseEnable,
    // ----- Mock能力 -----
    bool mockEnable,
    int mockProjectId,
  }) :
    assert(businessIdentifier != null && businessIdentifier.length > 0, '[APHttpRequest] businessIdentifier is empty'),
    assert(method != null && method.length > 0, '[APHttpRequest] method is empty'),
    assert(apiPath != null && apiPath.length > 0, '[APHttpRequest] apiPath is empty'),
    _path = pathParam == null ? apiPath : apiPath + pathParam,
    cancelToken = cancelToken ?? CancelToken(),
    dioOptions = Options(
      method: method,
      contentType: contentType ?? Headers.jsonContentType,
      responseType: responseType ?? ResponseType.json,
      headers: headers ?? <String, dynamic>{},
      sendTimeout: sendTimeout?.inMilliseconds,
      receiveTimeout: recvTimeout?.inMilliseconds,
    ),
    retry = APHttpRequestRetry(
      type: retryType ?? APHTTPRequestRetryType.Never,
      max: maxRetry ?? -1,
      retryIntervalMS: retryIntervalMS
    ),
    cache = APHttpRequestCache<T>(
      enable: cacheEnable ?? false,
      useLRU: cacheUseLRU ?? true,
      ignoreOnce: cacheIgnoreOnce ?? false,
      duration: cacheDuration,
    ),
    promise = APHttpRequestPromise(
      enable: promiseEnable ?? false
    ),
    mock = APHttpRequestMock(
      enable: mockEnable ?? false,
      projectId: mockProjectId ?? 0,
      originPath: pathParam == null ? apiPath : apiPath + pathParam,
    ) {
    
    if (data is Map) {
      _dataType = _APHttpRequestDataType.Map;
    }
    else if (data is String) {
      _dataType = _APHttpRequestDataType.String;
    }
    else {
      _dataType = _APHttpRequestDataType.Other;
    }
  }
  
  /// GET请求
  APHttpRequest.get({
    String businessIdentifier,
    String apiPath,
    String pathParam,
    String contentType,
    ResponseType responseType,
    Map<String, dynamic> headers,
    Map<String, dynamic> params,
    ModelConverter converter,
    CancelToken cancelToken,
    Duration sendTimeout,
    Duration recvTimeout,
    ProgressCallback onRecvProgress,
    APHTTPRequestRetryType retryType,
    int maxRetry,
    int retryIntervalMS,
    bool cacheEnable = false,
    bool cacheUseLRU = true,
    bool cacheIgnoreOnce = false,
    Duration cacheDuration,
    bool promiseEnable,
    bool mockEnable,
    int mockProjectId,
  }) : this(
    businessIdentifier: businessIdentifier,
    method : "GET",
    apiPath: apiPath,
    pathParam: pathParam,
    contentType: contentType,
    responseType: responseType,
    headers: headers,
    queryParams: params,
    converter: converter,
    cancelToken: cancelToken,
    sendTimeout: sendTimeout,
    recvTimeout: recvTimeout,
    onRecvProgress: onRecvProgress,
    retryType: retryType,
    maxRetry: maxRetry,
    retryIntervalMS: retryIntervalMS,
    cacheEnable: cacheEnable,
    cacheUseLRU: cacheUseLRU,
    cacheIgnoreOnce: cacheIgnoreOnce,
    cacheDuration: cacheDuration,
    promiseEnable: promiseEnable,
    mockEnable: mockEnable,
    mockProjectId: mockProjectId,
  );

  APHttpRequest.delete({
    String businessIdentifier,
    String apiPath,
    String pathParam,
    String contentType,
    ResponseType responseType,
    Map<String, dynamic> headers,
    Map<String, dynamic> queryParams,
    dynamic data,
    ModelConverter converter,
    CancelToken cancelToken,
    Duration sendTimeout,
    Duration recvTimeout,
    ProgressCallback onSendProgress,
    ProgressCallback onRecvProgress,
    APHTTPRequestRetryType retryType,
    int maxRetry,
    int retryIntervalMS,
    bool cacheEnable = false,
    bool cacheUseLRU = true,
    bool cacheIgnoreOnce = false,
    Duration cacheDuration,
    bool promiseEnable,
    bool mockEnable,
    int mockProjectId,
  }) : this(
    businessIdentifier: businessIdentifier,
    method : "DELETE",
    apiPath: apiPath,
    pathParam: pathParam,
    contentType: contentType,
    responseType: responseType,
    headers: headers,
    queryParams: queryParams,
    data: data,
    converter: converter,
    cancelToken: cancelToken,
    sendTimeout: sendTimeout,
    recvTimeout: recvTimeout,
    onSendProgress: onSendProgress,
    onRecvProgress: onRecvProgress,
    retryType: retryType,
    maxRetry: maxRetry,
    retryIntervalMS: retryIntervalMS,
    cacheEnable: cacheEnable,
    cacheUseLRU: cacheUseLRU,
    cacheIgnoreOnce: cacheIgnoreOnce,
    cacheDuration: cacheDuration,
    promiseEnable: promiseEnable,
    mockEnable: mockEnable,
    mockProjectId: mockProjectId,
  );

  APHttpRequest.post({
    String businessIdentifier,
    String apiPath,
    String pathParam,
    String contentType,
    ResponseType responseType,
    Map<String, dynamic> headers,
    Map<String, dynamic> queryParams,
    dynamic data,
    ModelConverter converter,
    CancelToken cancelToken,
    Duration sendTimeout,
    Duration recvTimeout,
    ProgressCallback onSendProgress,
    ProgressCallback onRecvProgress,
    APHTTPRequestRetryType retryType,
    int maxRetry,
    int retryIntervalMS,
    bool cacheEnable = false,
    bool cacheUseLRU = true,
    bool cacheIgnoreOnce = false,
    Duration cacheDuration,
    bool promiseEnable,
    bool mockEnable,
    int mockProjectId,
  }) : this(
      businessIdentifier: businessIdentifier,
      method : "POST",
      apiPath: apiPath,
      pathParam: pathParam,
      contentType: contentType,
      responseType: responseType,
      headers: headers,
      queryParams: queryParams,
      data: data,
      converter: converter,
      cancelToken: cancelToken,
      sendTimeout: sendTimeout,
      recvTimeout: recvTimeout,
      onSendProgress: onSendProgress,
      onRecvProgress: onRecvProgress,
      retryType: retryType,
      maxRetry: maxRetry,
      retryIntervalMS: retryIntervalMS,
      cacheEnable: cacheEnable,
      cacheUseLRU: cacheUseLRU,
      cacheIgnoreOnce: cacheIgnoreOnce,
      cacheDuration: cacheDuration,
      promiseEnable: promiseEnable,
      mockEnable: mockEnable,
      mockProjectId: mockProjectId,
  );
  
  /// 当拿到返回值后，传递给Request的completer
  void responseComplete(APHttpResponse response) {
    
    APHttpResponse<T> tResponse = APHttpResponse<T>(
      headers: response.headers,
      data: response.data,
      model: response.model is T ? response.model as T : null,
      error: response.error
    );
    
    if (_completer.isCompleted == false) {
      _completer.complete(tResponse);
    }
  }

  /// ------------------ 缓存Key操作 -------------------

  /// 生成当前Request的Key
  ///
  /// 该操作由网络框架层在请求发起前调用，确保此时参数不可能再被更改
  void generateMD5Key() {
    
    String value = '';
    if (businessIdentifier != null) value += businessIdentifier;
    if (dioOptions.method != null) value += dioOptions.method;
    if (apiPath != null) value += apiPath;
    if (pathParam != null) value += pathParam;
    if (queryParams != null) {
      value += json.encode(queryParams);
    }
    
    // 大多数接口都是Map，少部分上传接口是FormData，这种接口不可能做缓存
    if (data != null && data is Map) {
      value += json.encode(data);
    }
    
    List<int> valueData = Utf8Encoder().convert(value);
    Digest digest = md5.convert(valueData);
    cache._md5Key = hex.encode(digest.bytes);
  }

  /// ------------------ Promise 操作 -------------------

  /// 生成Promise存储Key
  ///
  /// 由网络框架层调用
  void generatePromiseKey() {
    promise._key = Uuid().v5(null, 'Promise');
  }
  
  /// ------------------ 归档、解档 -------------------
  
  /// 转换成Map
  Map<String, dynamic> toMap() {
    
    try {
  
      Map<String, dynamic> map = Map();
      map['businessIdentifier'] = businessIdentifier;
      map['apiPath'] = apiPath;
      map['pathParam'] = pathParam;
  
      if (queryParams != null) {
        map['queryParams'] = json.encode(queryParams);
      }
  
      // 目前仅支持FormData Map String的Body参数存储
      map['_dataType'] = _dataType.index;
      if (_dataType == _APHttpRequestDataType.Map) {
        map['data'] = json.encode(data);
      }
      else if (_dataType == _APHttpRequestDataType.String) {
        map['data'] = data;
      }
  
      // Option部分
      Map<String, dynamic> optionMap = Map();
      optionMap['method'] = dioOptions.method;
      optionMap['contentType'] = dioOptions.contentType;
      optionMap['responseType'] = dioOptions.responseType.index;
      optionMap['headers'] = json.encode(dioOptions.headers);
      // 单位ms
      if (dioOptions.sendTimeout != null) {
        optionMap['sendTimeout'] = dioOptions.sendTimeout;
      }

      // 单位ms
      if (dioOptions.receiveTimeout != null) {
        optionMap['receiveTimeout'] = dioOptions.receiveTimeout;
      }
      map['dioOptions'] = json.encode(optionMap);
  
      if (extraTag != null) {
        map['extraTag'] = extraTag;
      }
      
      // 重试相关
      map['retry'] = json.encode(retry.toMap());
      // 缓存相关
      map['cache'] = json.encode(cache.toMap());
      // Promise相关
      map['promise'] = json.encode(promise.toMap());
      // Mock相关
      map['mock'] = json.encode(mock.toMap());
      
      return map;
    }
    catch (e, stack) {
      
      assert((){
        debugPrintStack(stackTrace: stack);
        return false;
      }(), e.toString());
      
      return null;
    }
  }
  
  static APHttpRequest fromMap(Map<String, dynamic> map) {
    
    try {
      String businessIdentifier = map['businessIdentifier'];
      String apiPath = map['apiPath'];
      String pathParam = map['pathParam'];
  
      Map<String, dynamic> queryParams;
      if (map['queryParams'] != null) {
        queryParams = json.decode(map['queryParams']);
      }
  
      // Body参数解析
      dynamic data;
      _APHttpRequestDataType dataType = _APHttpRequestDataType.values[map['_dataType']];
      if (dataType == _APHttpRequestDataType.Map) {
        data = json.decode(map['data']);
      }
      else {
        data = map['data'];
      }
  
      // Option部分，optionMap不可能为null
      Map<String, dynamic> optionMap = json.decode(map['dioOptions']);
      String method = optionMap['method'];
      String contentType = optionMap['contentType'];
      ResponseType responseType = ResponseType.values[optionMap['responseType']];
      Map<String, dynamic> headers = json.decode(optionMap['headers']);
      // map中的时间单位，ms
      Duration sendTimeout;
      if (optionMap['sendTimeout'] != null) {
        sendTimeout = Duration(milliseconds: optionMap['sendTimeout']);
      }
  
      Duration recvTimeout;
      if (optionMap['receiveTimeout'] != null) {
        recvTimeout = Duration(milliseconds: optionMap['receiveTimeout']);
      }
      
      int extraTag = map['extraTag'];
  
      // 重试部分
      APHttpRequestRetry retry = APHttpRequestRetry.fromMap(json.decode(map['retry']));
      // 缓存部分
      APHttpRequestCache cache = APHttpRequestCache.fromMap(json.decode(map['cache']));
      // Promise部分
      APHttpRequestPromise promise = APHttpRequestPromise.fromMap(json.decode(map['promise']));
      // Mock部分
      APHttpRequestMock mock = APHttpRequestMock.fromMap(json.decode(map['mock']));
      
      APHttpRequest request = APHttpRequest(
          businessIdentifier: businessIdentifier,
          method: method,
          apiPath: apiPath,
          pathParam: pathParam,
          contentType: contentType,
          responseType: responseType,
          headers: headers,
          queryParams: queryParams,
          data: data,
          sendTimeout: sendTimeout,
          recvTimeout: recvTimeout,
          retryType: retry.type,
          maxRetry: retry.max,
          retryIntervalMS: retry.retryIntervalMS,
          cacheEnable: cache.enable,
          cacheUseLRU: cache.useLRU,
          cacheIgnoreOnce: cache.ignoreOnce,
          cacheDuration: cache.duration,
          promiseEnable: promise.enable,
          mockEnable: mock.enable,
          mockProjectId: mock.projectId,
          
      );
      request.promise._key = promise.key;
      request.extraTag = extraTag;
      return request;
    }
    catch (e, stack) {
  
      assert((){
        debugPrintStack(stackTrace: stack);
        return false;
      }(), e.toString());
  
      return null;
    }
  }

  @override
  String toString() {
    return '''
    APHttpRequest $businessIdentifier ${dioOptions?.method} $path
    |Hash: $hashCode
    |RetryType: ${retry?.type} RetryCount: ${retry?.count} MaxRetry: ${retry?.max}
    |Headers: ${dioOptions?.headers}
    |QueryParams: $queryParams
    |Data: $data
    ''';
  }
  
  String toLogDBString () {
    return '''
    ${dioOptions?.method} $path
    |RetryType: ${retry?.type} RetryCount: ${retry?.count} MaxRetry: ${retry?.max}
    |Headers: ${dioOptions?.headers}
    |QueryParams: $queryParams
    |Data: $data
    ''';
  }
  
  String toBuglyString() {
    return '${dioOptions?.method} $path';
  }
}

/// 接口失败，重试类型
enum APHTTPRequestRetryType {
  Never,      // 从不
  Limit,      // 有限次，最大值为[maxRetry]
  Forever     // 无限，直到业务层表明无需重试或者成功为止
}

/// 重试能力
class APHttpRequestRetry {
  
  /// 重试类型
  final APHTTPRequestRetryType type;
  
  /// 最多重试多少次，前提retryType为[APHTTPRequestRetryType.Limit]
  final int max;

  /// 当前接口失败重试次数计数
  int count = 0;
  
  /// 重试间隔时间，ms
  int retryIntervalMS;

  APHttpRequestRetry({this.type, this.max, this.retryIntervalMS});

  Map<String, dynamic> toMap() {
    
    Map<String, dynamic> map = Map();
    map['type'] = type.index;
    map['max'] = max;
    map['retryIntervalMS'] = retryIntervalMS;
    return map;
  }
  
  static APHttpRequestRetry fromMap(Map<String, dynamic> map) {
    
    APHTTPRequestRetryType retryType = APHTTPRequestRetryType.values[map['type']];
    return APHttpRequestRetry(
      type: retryType,
      max: map['max'],
      retryIntervalMS: map['retryIntervalMS']
    );
  }
}

/// 缓存能力
class APHttpRequestCache<T extends APHttpModel> {
  
  /// 缓存MD5码，作为Key使用
  String _md5Key;
  String get md5Key => _md5Key;
  
  /// 是否开启缓存
  ///
  /// 开启缓存，意味着请求成功返回后，会缓存数据，方便下次读取
  ///
  /// 有缓存数据时，若[ignoreOnce]为true，则发起请求后会读取缓存赋值给[response]
  /// 有缓存数据时，若[ignoreOnce]为false，则发起请求后，不会尝试去读缓存数据
  final bool enable;
  
  /// 缓存是否走LRU机制
  ///
  /// 默认所有缓存都走LRU机制，但是不排除个别接口需要独立、或长期缓存
  final bool useLRU;
  
  /// 开启缓存的情况下，如果有cache，本次请求不读cache，但是仍然要存最新cache
  ///
  /// 个别业务场景下，可能会强制本次请求不读缓存
  final bool ignoreOnce;
  
  /// 缓存时长
  ///
  /// 如果读取缓存时，发现缓存数据的保存时间已经超过，则会放弃该缓存
  /// 为null表示无期限保存
  final Duration duration;
  
  /// 缓存数据，可能为null
  APHttpResponse<T> _response;
  APHttpResponse<T> get response => _response;
  set response (APHttpResponse response) {
  
    APHttpResponse<T> tResponse = APHttpResponse<T>(
        headers: response.headers,
        data: response.data,
        model: response.model is T ? response.model as T : null,
        error: response.error
    );
    _response = tResponse;
  }

  APHttpRequestCache({
    this.enable,
    this.useLRU,
    this.ignoreOnce,
    this.duration
  });
  
  Map<String, dynamic> toMap() {
    
    Map<String, dynamic> map = Map();
    map['enable'] = enable;
    map['useLRU'] = useLRU;
    map['ignoreOnce'] = ignoreOnce;
    if (duration != null) {
      map['duration'] = duration.inSeconds;
    }
    return map;
  }

  static APHttpRequestCache fromMap(Map<String, dynamic> map) {
  
    Duration duration;
    if (map['duration'] != null) {
      duration = Duration(seconds: map['duration']);
    }
    
    return APHttpRequestCache(
      enable: map['enable'],
      useLRU: map['useLRU'],
      ignoreOnce: map['ignoreOnce'],
      duration: duration
    );
  }
}

/// Promise能力
class APHttpRequestPromise {
  
  /// 保证开关
  ///
  /// 为true表示该请求会加入到promise流程控制中
  /// 确保其会一直反复进行请求，直到成功为止，及时用户kill app
  ///
  /// 注意，promise流程期间，业务层可以手动中断该流程
  final bool enable;
  
  /// 用于存储时的唯一识别码
  ///
  /// 由APNetworkManager控制生成
  String _key;
  String get key => _key;

  APHttpRequestPromise({this.enable});
  
  Map<String, dynamic> toMap() {
    Map<String, dynamic> map = Map();
    map['enable'] = enable;
    if (_key != null) {
      map['key'] = _key;
    }
    return map;
  }
  
  static APHttpRequestPromise fromMap(Map<String, dynamic> map) {
    
    return APHttpRequestPromise(
      enable: map['enable'],
    ).._key = map['key'];
  }
}

/// Mock能力，对Yapi的支持
class APHttpRequestMock {
  
  /// Mock开关
  ///
  /// True表明该接口会对Yapi发起请求，且请求地址使用Mock地址
  final bool enable;
  
  /// 该请求所属Yapi Project Id
  final int projectId;
  
  /// 原始请求地址
  final String originPath;
  
  /// Mock请求抵制
  String _path;
  String get path {
   if (_path == null) {
     _path = '/mock/$projectId' + originPath;
   }
   return _path;
  }
  
  APHttpRequestMock({this.enable, this.projectId, this.originPath});
  
  Map<String, dynamic> toMap() {
    Map<String, dynamic> map = Map();
    map['enable'] = enable;
    map['projectId'] = projectId;
    map['originPath'] = originPath;
    return map;
  }
  
  static APHttpRequestMock fromMap(Map<String, dynamic> map) {
    
    return APHttpRequestMock(
      enable: map['enable'],
      projectId: map['projectId'],
      originPath: map['originPath'],
    );
  }
}