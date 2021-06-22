
import 'ap_http_parser.dart';
import 'ap_network_interceptor.dart';

/// 网络通信业务线
///
/// 同一个客户端内，可能存在多条业务线的网络请求
/// 比如WooPlus目前存在new、old两套后台业务
///
/// 未来，也可能接入第三方的网络通信，新增其他网络通信业务
///
/// 每条业务线，都有独立的interceptor、parser
class APNetworkBusiness {
  
  /// 唯一识别码
  final String? identifier;
  
  /// 业务线，请求基地址
  final String? baseURL;
  
  /// 业务线，对应的Yapi Mock基地址
  final String? yapiBaseURL;
  
  /// 拦截器
  final APNetworkInterceptor interceptor;
  
  /// 解析器
  final APHttpParser parser;
  
  /// 连接超时时间(ms)
  final int? connectTimeoutMS;

  /// 发送超时时间(ms)
  final int? sendTimeoutMS;

  /// 接收超时时间(ms)
  final int? recvTimeoutMS;

  /// 重试间隔时间(ms)
  final int? retryIntervalMS;
  
  APNetworkBusiness({
    this.identifier,
    this.baseURL,
    this.yapiBaseURL,
    required this.interceptor,
    required this.parser,
    this.connectTimeoutMS,
    this.sendTimeoutMS,
    this.recvTimeoutMS,
    this.retryIntervalMS
  }) :
    assert(identifier != null && identifier.length > 0, 'identifer can not be empty'),
    assert(baseURL != null && baseURL.length > 0, 'baseURL can not be empty'),
    assert(interceptor != null, 'interceptor can not be null'),
    assert(parser != null, 'parser can not be null'),
    assert(connectTimeoutMS != null && connectTimeoutMS > 0, 'connectTimeoutMS must > 0'),
    assert(sendTimeoutMS != null && sendTimeoutMS > 0, 'sendTimeoutMS must > 0'),
    assert(recvTimeoutMS != null && recvTimeoutMS > 0, 'recvTimeoutMS must > 0'),
    assert(retryIntervalMS != null && retryIntervalMS >= 0, 'retryIntervalMS must >= 0');
}