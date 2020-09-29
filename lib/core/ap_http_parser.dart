
import 'package:dio/dio.dart';
import 'ap_http_request.dart';
import 'ap_http_response.dart';

/// 返回数据解析器
abstract class APHttpParser {
  
  /// 服务器返回数据处理
  Future<APHttpResponse> handleResponse(APHttpRequest request, Response response);

  /// 错误码处理
  ///
  /// @param: error，可能是DioError，可能是Exception，也可能是FlutterErrorDetails
  /// @param: stack，异常产生的函数调用栈信息
  Future<APHttpResponse> handleError(APHttpRequest request, Response dioResponse, dynamic error, StackTrace stack);
}