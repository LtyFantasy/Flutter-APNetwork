
import 'ap_http_error.dart';
import 'ap_http_model.dart';

class APHttpResponse<T extends APHttpModel?> {
  
  /// 服务端返回的Header数据
  final Map<String, List<String>>? headers;
  
  /// 服务端返回的body数据
  final Map<String, dynamic>? data;
  
  /// 业务层Model，在[Parser]，中由[APHttpRequest]的[ModelConverter]生成
  final T? model;
  
  /// 业务层解析器生成的Erro
  final APHttpError? error;
  
  /// 请求是否成功
  bool get isSuccess => error == null;
  
  APHttpResponse({this.headers, this.data, this.model, this.error});
  
  @override
  String toString() {
    return '''
    APHttpResponse
    |header: $headers
    |data: $data
    |error: $error
    ''';
  }
  
  String toLogDBString() {
    
    if (isSuccess) {
      return '$data';
    }
    else {
      return '$error';
    }
  }
  
  Map<String, dynamic> toMap() {
  
    Map<String, dynamic> map = Map();
    map['headers'] = headers;
    map['data'] = data;
    map['error'] = error?.toMap();
    return map;
  }
}