
import 'package:dio/dio.dart';
import 'ap_http_request.dart';
import 'ap_http_response.dart';

/// 过程监听器
///
/// [Notice]初始化流程执行完毕之前，所有的request都会被阻塞
abstract class APNetworkInterceptor {
  
  /// ----------------- 初始化流程 -------------------
  
  /// 初始化回调
  /// 
  /// 可以在这里，做异步的数据初始化任务，确保后续的网络通信正常运转
  Future<void> initialData();
  
  /// Dio初始化设置回调
  ///
  /// 业务层可以在这里追加设置dio的参数
  /// @param dio dio对象
  /// @param isYapi true-表明是yapi专用dio false-表明是正常网络业务的dio
  void setupDio(Dio? dio, bool isYapi);

  /// ----------------- 请求生命周期 -------------------
  
  /// 请求暂停时通行特权咨询
  ///
  /// 当业务线被暂停时，可以根据业务需要，允许某些请求破例通行
  /// 增加了控制的灵活性
  bool allowRequestPassWhenSuspend(APHttpRequest request);
  
  /// 请求前回调
  /// 
  /// 可以在这里注入业务层公共参数
  void onRequest(APHttpRequest request);
  
  /// 请求添加到了Promise
  void onAddToPromise(APHttpRequest request);
  
  /// 请求读取到了缓存数据
  void onLoadCache(APHttpRequest request, Map<String, dynamic> cacheData);
  
  /// 请求完毕后回调
  void onResponse(APHttpRequest request, APHttpResponse response);
  
  /// 接口是否需要重试
  ///
  /// 某些业务层错误，某些网络层错误，需要重试
  /// 
  /// 返回true，网络框架会重走request逻辑
  /// 返回false，进入complete流程
  bool needRetry(APHttpRequest request, APHttpResponse response);

  /// 请求保存了缓存数据
  void onSaveCache(APHttpRequest request, Map<String, dynamic>? cacheData);
  
  /// 请求从Promise中移除
  void onRemoveFromPromise(APHttpRequest request);

  /// 回调拦截监听
  ///
  /// 该回调，是指是否要拦截回复业务层的await request.response这个completer
  /// 有个别业务可能需要拦截返回数据，执行对应的额外逻辑，最后手动完成闭环
  /// 可能的情况：
  /// 1，token失效，它不属于正常的重试逻辑，需要执行刷新Token相关流程后，再去续接原请求
  /// 2，未来其他业务，比如要对某一类型的数据执行统一的耗时操作后，再返回给具体的业务场景
  /// 
  /// 返回false，表示不拦截该结果，网络框架会把response丢给request的completer
  /// 返回true，表示业务层要拦截该结果，request的completer何时完成，交由业务层自己控制
  bool interceptComplete(APHttpRequest request, APHttpResponse response);

  /// ----------------- 数据清理、释放 -------------------
  
  /// 清理数据回调
  ///
  /// 当准备清理全局缓存数据的时候，会通知业务线，看是否也要释放相关数据
  Future<void> onCleanData();
}