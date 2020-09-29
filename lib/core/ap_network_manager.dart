import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'ap_http_error.dart';
import 'ap_http_request.dart';
import 'ap_http_response.dart';
import 'ap_network_business.dart';
import 'ap_network_cache.dart';
import 'ap_network_promise.dart';

/// APNetworkManager
///
/// 本框架依赖第三方网络请求库，[Dio]
///
/// 注意，该网络框架与具体的项目业务无关，仅仅面向公司团队特性提供网络支持
/// 其目的，是为了可以服务于所有项目，且可以随时方便维护更新
/// !! 因此永远不要尝试去关联任何业务层代码 !!
///
/// @author: Loki
/// @date: 2020/07/15

/// 网络通信管理类
///
/// 维护整个通信流程，接口发起、回应处理、过程监控、请求重试
class APNetworkManager {
  /// [Test]单元测试专用
  static Dio _mockDio;

  /// 初始化完成标记
  Completer<void> _initOk;

  /// 业务线
  Map<String, APNetworkBusiness> _businessMap;

  /// 业务线其他信息
  Map<String, _APNetworkBusinessInfo> _businessInfoMap;

  /// 请求缓存
  APNetworkCache _cache;

  /// Promise，请求保证机制
  APNetworkPromise _promise;

  /// 单例模式
  factory APNetworkManager({Dio mockDio}) {
    _mockDio = mockDio;
    return _getInstance();
  }

  static APNetworkManager get instance => _getInstance();
  static APNetworkManager _instance;

  static APNetworkManager _getInstance() {
    if (_instance == null) {
      _instance = APNetworkManager._init();
    }
    return _instance;
  }

  static void release() {
    _instance = null;
  }

  /// ----------------- 设置 --------------------

  /// 单例初始化设置
  APNetworkManager._init() {
    _businessMap = Map();
    _businessInfoMap = Map();
    _cache = APNetworkCache.instance;
    _promise = APNetworkPromise.instance;
    _initOk = Completer();
    _setupData();
  }

  /// 数据初始化
  Future<void> _setupData() async {
    // 加载Cache本地缓存
    await _cache.initSetup();
    await _promise.initSetup();
    _initOk.complete();
  }

  /// 添加业务线
  Future<void> addBusiness(APNetworkBusiness business) async {
    if (business == null) return;
    if (_businessMap[business.identifier] != null) return;
    
    // 先添加业务线
    _APNetworkBusinessInfo info = _APNetworkBusinessInfo(
      identifier: business.identifier,
      initOk: Completer(),
    );
    _businessMap[business.identifier] = business;
    _businessInfoMap[business.identifier] = info;

    // 业务线后续的初始化，必须要等框架层初始化完毕后再执行
    if (_initOk.isCompleted == false) await _initOk.future;
    // 业务线初始化，可能会有一些异步初始化操作
    await business.interceptor.initialData();
    // 为其创建Dio
    if (_mockDio == null) {
      info.dio = Dio(BaseOptions(
        baseUrl: business.baseURL,
        connectTimeout: business.connectTimeoutMS,
        sendTimeout: business.sendTimeoutMS,
        receiveTimeout: business.recvTimeoutMS,
      ));
    } else {
      info.dio = _mockDio;
    }
    // 传递给业务层，看看它是否还要设置一些什么
    business.interceptor.setupDio(info.dio);

    // Debug模式下，才会生成yapiDio
    assert(() {
      if (business.yapiBaseURL != null) {
        if (_mockDio == null) {
          info.yapiDio = Dio(BaseOptions(
            baseUrl: business.yapiBaseURL,
            connectTimeout: business.connectTimeoutMS,
            sendTimeout: business.sendTimeoutMS,
            receiveTimeout: business.recvTimeoutMS,
          ));
        } else {
          info.yapiDio = _mockDio;
        }
      }
      return true;
    }());

    // 业务线，初始化完成
    info.initOk.complete();
  }

  /// 清空各缓存数据
  Future<void> cleanData() async {
    await _cache.cleanCache();
    await _promise.cleanAll();
    for (APNetworkBusiness business in _businessMap.values) {
      await business.interceptor.onCleanData();
    }
  }

  /// ----------------- 控制命令 --------------------

  /// 暂停指定的业务线请求
  ///
  /// 为其设置suspend标记
  void suspend({List<String> identifiers, bool all = false}) {
    
    if (all == true) {
      for (String id in _businessMap.keys) {
        _APNetworkBusinessInfo info = _businessInfoMap[id];
        if (info != null && info.suspend == null) {
          info.suspend = Completer();
        }
      }
    }
    else {
      if (identifiers == null) return;
      for (String id in identifiers) {
        _APNetworkBusinessInfo info = _businessInfoMap[id];
        if (info != null && info.suspend == null) {
          info.suspend = Completer();
        }
      }
    }
  }

  /// 恢复指定的业务线请求
  ///
  /// 完成suspend标记，并设置为null
  void resume({List<String> identifiers, bool all = false}) {
    if (all == true) {
      for (String id in _businessMap.keys) {
        _APNetworkBusinessInfo info = _businessInfoMap[id];
        if (info != null && info.suspend != null) {
          if (info.suspend.isCompleted == false) {
            info.suspend.complete();
          }
          info.suspend = null;
        }
      }
    }
    else {
      if (identifiers == null) return;
      for (String id in identifiers) {
        _APNetworkBusinessInfo info = _businessInfoMap[id];
        if (info != null && info.suspend != null) {
          if (info.suspend.isCompleted == false) {
            info.suspend.complete();
          }
          info.suspend = null;
        }
      }
    }
  }

  /// ----------------- 网络请求 --------------------

  /// 发起请求
  ///
  /// 这层包裹只是为了方便外面await 链式调用
  APHttpRequest sendRequest(APHttpRequest request) {
    _sendRequest(request);
    return request;
  }

  /// 发起HTTP请求
  Future<void> _sendRequest(APHttpRequest request) async {
    
    if (request == null) return;
    APNetworkBusiness business = _businessMap[request.businessIdentifier];
    _APNetworkBusinessInfo businessInfo =
        _businessInfoMap[request.businessIdentifier];

    // 找不到业务线，直接报错返回
    // 这个仅仅只是作为开发期间的业务警示，理论上不会影响任何业务
    // 确保测试环境下，所有接口一定关联了存在的业务线
    if (business == null || businessInfo == null) {
      assert(false,
          'Please confirm business(${request.businessIdentifier}) is fucking exsits');
      request.responseComplete(APHttpResponse(
          error: APHttpError(
        code: -999999,
        message:
            'Please confirm business(${request.businessIdentifier}) is fucking exsits',
      )));
      return;
    }

    // 临时变量，用来catch的时候传递dio返回值，如果有response的话，就可以协助定位问题
    Response _dioResponse;
    
    try {
      // 等待业务线初始化完毕
      if (businessInfo.initOk.isCompleted == false) {
        await businessInfo.initOk.future;
      }

      // 是否有暂停控制
      if (businessInfo.suspend != null &&
          businessInfo.suspend.isCompleted == false) {
        // 咨询业务层，请求是否可以破例通行
        if (business.interceptor.allowRequestPassWhenSuspend(request) ==
            false) {
          await businessInfo.suspend.future;
        }
      }

      // 设置请求开始时间
      request.requestStartTime = DateTime.now();
      // 业务层通知，请求前
      business.interceptor.onRequest(request);
      // 检查，是否有promise需求
      _checkIfNeedPromise(business, request);
      // 检查，是否需要读缓存
      _checkIfNeedLoadCache(business, request);

      // 正常情况下
      Dio dio = businessInfo.dio;
      String path = request.path;

      /// 确保仅仅只有Debug模式下，才会有Mock逻辑
      /// Release模式下，一定不会发起mock请求
      assert(() {
        if (businessInfo.yapiDio != null && request.mock.enable == true) {
          dio = businessInfo.yapiDio;
          path = request.mock.path;
        }
        return true;
      }());
      
      Response response = await dio.request(path,
          data: request.data,
          queryParameters: request.queryParams,
          cancelToken: request.cancelToken,
          options: request.dioOptions,
          onSendProgress: request.onSendProgress,
          onReceiveProgress: request.onRecvProgress);
      _dioResponse = response;
      
      APHttpResponse httpResponse = await business.parser.handleResponse(request, response);
      await _complete(business, request, httpResponse);
    }
    catch (error, stack) {
    
      assert(() {
        if (error is! DioError) {
          debugPrintStack(stackTrace: stack);
        }
        return true;
      }());

      APHttpResponse response = await business.parser.handleError(request, _dioResponse, error, stack);
      await _complete(business, request, response);
    }
  }

  /// 请求完成处理
  Future<void> _complete(APNetworkBusiness business, APHttpRequest request,
      APHttpResponse response) async {
    // 业务层监听回调
    business.interceptor.onResponse(request, response);

    // 检查结果，是否需要重试
    if (_needRetry(business, request, response)) {
      request.retry.count++;
      // 重试间隔时间，如果Request没有指定，就用业务线的配置
      int delayTime = request.retry.retryIntervalMS ?? business.retryIntervalMS;
      Future.delayed(Duration(milliseconds: delayTime), () {
        sendRequest(request);
      });
    }
    // 不重试，通知接口completer，完成数据闭环
    else {
      // 检查，是否需要保存缓存
      await _checkIfNeedSaveCache(business, request, response);
      // 检查，Promise是否完成
      await _checkIfNeedCompletePromise(business, request, response);
      // 询问业务层，是否要拦截该请求
      // 如果拦截，那么网络框架就不管complete，业务层自己去完成请求闭环
      if (business.interceptor.interceptComplete(request, response) == false) {
        request.responseComplete(response);
      }
    }
  }

  /// 检查本次请求，是否需要重试
  bool _needRetry(APNetworkBusiness business, APHttpRequest request,
      APHttpResponse response) {
    // 不允许重试
    if (request.retry.type == APHTTPRequestRetryType.Never) {
      return false;
    }

    // 如果允许有限次重试，但是重试次数已经超过
    if (request.retry.type == APHTTPRequestRetryType.Limit &&
        request.retry.count >= request.retry.max) {
      return false;
    }

    // 走到这里，要么是Forever类型，要么是Limit但是次数没超过
    // 再咨询业务层，是否需要重试，业务层可能有自己的判断
    return business.interceptor.needRetry(request, response);
  }

  /// ----------------- 缓存操作 --------------------

  /// 检查是否可以读取缓存
  void _checkIfNeedLoadCache(
      APNetworkBusiness business, APHttpRequest request) {
    // 开启了缓存功能，且本次request不忽略缓存
    if (request.cache.enable == true && request.cache.ignoreOnce == false) {
      request.generateMD5Key();
      Map<String, dynamic> cacheData = _cache.loadCache(request.cache.md5Key);
      // 成功读取到缓存，则给request设置cacheResponse
      // 这样业务层发起请求后，立刻就可以判断是否有缓存可以使用
      if (cacheData != null) {
        business.interceptor.onLoadCache(request, cacheData);
        request.cache.response = APHttpResponse(
            data: cacheData,
            model: request.converter == null
                ? null
                : request.converter(cacheData));
      }
    }
  }

  /// 检查是否可以保存缓存
  Future<void> _checkIfNeedSaveCache(APNetworkBusiness business,
      APHttpRequest request, APHttpResponse response) async {
    // 开启缓存功能，且解析器没有返回错误信息，则存储请求缓存
    if (request.cache.enable == true &&
        request.cache.md5Key != null &&
        response.error == null &&
        response.data != null) {
      business.interceptor.onSaveCache(request, response.data);
      await _cache.saveCache(request.cache.md5Key, response.data,
          duration: request.cache.duration);
    }
  }

  /// ----------------- Promise 操作 --------------------

  /// 获取Promise中的请求
  ///
  /// 获取指定业务线、指定请求path的请求
  ///
  /// @param: businessIdentifier 必传，业务线识别码
  /// @param: paths 可选，如果为null，表示获取业务线下所有请求
  Future<List<APHttpRequest>> getPromiseRequests(String businessIdentifier,
      {List<String> paths}) async {
    
    if (_initOk.isCompleted == false) {
      await _initOk.future;
    }
    return _promise.loadBusinessRequests(businessIdentifier, paths: paths);
  }

  /// 检查是否需要加入Promise
  void _checkIfNeedPromise(APNetworkBusiness business, APHttpRequest request) {
    if (request.promise.enable != true) return;
    // 如果有PromiseKey，证明已经加入Promise流程了
    if (request.promise.key != null) return;

    request.generatePromiseKey();
    _promise.saveRequest(request);
    // 拦截器监听
    business.interceptor.onAddToPromise(request);
  }

  /// 检查请求的Promise是否可以完成
  Future<void> _checkIfNeedCompletePromise(APNetworkBusiness business,
      APHttpRequest request, APHttpResponse response) async {
    // 正常来说，请求如果返回Success，那么就是完成了Proimse
    // 目前还没有例外的情况，如果有，Promise就需要挪动到业务层去做，而不是在网络框架做
    if (request.promise.enable == true && response.error == null) {
      await _promise.deleteRequestWithKey(
          request.businessIdentifier, request.promise.key);
      business.interceptor.onRemoveFromPromise(request);
    }
  }
}

/// 业务线的其他信息
///
/// 具体的业务层代码无需关心这些
/// 仅仅由网络框架自己维护
class _APNetworkBusinessInfo {
  /// 业务识别码
  final String identifier;

  /// 初始化完成标记
  final Completer<void> initOk;

  /// 底层请求库
  Dio dio;

  /// 为Yapi准备的Mock Dio
  Dio yapiDio;

  /// 暂停标记
  Completer<void> suspend;

  _APNetworkBusinessInfo({
    this.identifier,
    this.initOk,
  });
}
