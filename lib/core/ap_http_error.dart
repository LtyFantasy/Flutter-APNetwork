

/// 业务层错误码对象
class APHttpError {
  
  // 错误码
  final int? code;
  // 原始错误消息
  final String? originMessage;
  // 提供给业务层展示用的错误消息
  final String? message;
  // 原始返回数据
  final Map<String, dynamic>? data;
  // 原始错误对象
  final dynamic originError;

  APHttpError({
    this.code,
    this.originMessage,
    this.message,
    this.data,
    this.originError,
  });
  
  @override
  String toString() {
    return '''
    APHttpError code: $code | originMessage: $originMessage | message: $message | originError: $originError | data: $data
    ''';
  }
  
  Map<String, dynamic> toMap() {
  
    Map<String, dynamic> map = Map();
    map['code'] = code;
    map['originMessage'] = originMessage;
    map['message'] = message;
    map['data'] = data;
    map['originError'] = originError?.toString();
    return map;
  }
}