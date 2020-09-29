
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

class APNetworkIsolate {
  
  /// 子Isolate对象
  Isolate _isolate;
  
  /// 主Isolate接收端口
  ReceivePort _receivePort;
  
  /// 主Isolate发送端口
  SendPort _sendPort;
  
  /// 待处理消息队列
  Map<int, APNetworkIsolateMesssage> _messageMap;
  
  /// ---------------- 初始化，数据设置 ------------------
  
  /// 创建Isolate
  Future<void> create() async {
    
    _messageMap = Map();
    
    // 主进程设置接收池
    _receivePort = ReceivePort();
    // 把主进程的传输通道[receivePort.sendPort]丢给子线程
    _isolate = await Isolate.spawn(
        _SubIsolate.main,
        _receivePort.sendPort,
        debugName: 'APNetworkIsolate'
    );
    
    Completer completer = Completer();
    _receivePort.listen((data) {
      
      if (data is SendPort) {
        _sendPort = data;
        completer.complete();
      }
      else if (data is List) {
        _handleReceiveData(data);
      }
    });
    await completer.future;
  }
  
  void close() {
    
    _sendPort.send(APNetworkIsolateMesssage(
      type: APNetworkIsolateMesssageType.Closed
    ).toMap());
    
    _receivePort.close();
    _isolate.kill(priority: Isolate.immediate);
    _isolate = null;
    _receivePort = null;
    _sendPort = null;
  }

  /// ---------------- 消息操作 ------------------

  /// 发送事件消息
  APNetworkIsolateMesssage sendMessage(APNetworkIsolateMesssage messsage) {
    
    if (messsage == null || messsage is! APNetworkIsolateMesssage) {
      return null;
    }

    // 为消息生成唯一码，且临时保存
    messsage._eventId = messsage.hashCode;
    _messageMap[messsage._eventId] = messsage;
    // 处理消息
    _handleSendMessage(messsage);
    
    return messsage;
  }
  
  /// 消息发送处理
  void _handleSendMessage(APNetworkIsolateMesssage messsage) {
    
    /// Json解析任务 特殊处理
    /// 把原始String当成一个参数分开传，避免被encode decode浪费时间
    if (messsage.type == APNetworkIsolateMesssageType.ParseJson) {
      String jsonString = messsage.data;
      messsage.data = null;
      _sendPort.send([messsage.toMap(), jsonString]);
    }
    else {
      _sendPort.send([messsage.toMap()]);
    }
  }

  /// 消息接收处理
  void _handleReceiveData(List data) {
  
    APNetworkIsolateMesssage messsage = APNetworkIsolateMesssage.fromMap(data[0]);
    /// Json解析任务的数据是当做额外参数传递过来的，避免被encode decode浪费时间
    if (messsage.type == APNetworkIsolateMesssageType.ParseJson) {
      messsage.data = data[1];
    }

    // 给对应的发送方消息设置response
    APNetworkIsolateMesssage sendMessage = _messageMap[messsage._eventId];
    if (sendMessage != null) {
      sendMessage.responseComplete(messsage);
    }
  }
}

/// 消息类型
enum APNetworkIsolateMesssageType {
  /// 关闭Isolate
  Closed,
  /// 解析Json
  ParseJson,
}

/// 消息方向
enum APNetworkIsolateMesssageDirection {
  /// 来自主线程
  FromMainIsolate,
  /// 来自子线程
  FromSubIsolate,
}

/// Isolate交互消息体
class APNetworkIsolateMesssage {
  
  /// 消息事件唯一码
  ///
  /// 表征Send、Receive是否是应对同一个事件
  int _eventId;

  /// 消息类型
  final APNetworkIsolateMesssageType type;
  
  /// 数据
  dynamic data;
  
  /// 响应消息
  final Completer<APNetworkIsolateMesssage> _completer;
  Future<APNetworkIsolateMesssage> get response => _completer.future;

  APNetworkIsolateMesssage({
    this.type,
    this.data,
  }) : _completer = Completer();
  
  void responseComplete(APNetworkIsolateMesssage messsage) {
    if (_completer.isCompleted == false) {
      _completer.complete(messsage);
    }
  }
  
  Map<String, dynamic> toMap() {
    Map<String, dynamic> map = Map();
    map['eventId'] = _eventId;
    map['type'] = type.index;
    map['data'] = json.encode(data);
    return map;
  }
  
  static APNetworkIsolateMesssage fromMap(Map<String, dynamic> map) {
    return APNetworkIsolateMesssage(
      type: APNetworkIsolateMesssageType.values[map['type']],
      data: json.decode(map['data'])
    ).._eventId = map['eventId'];
  }
}

/// APNetworkIsolate开辟的子线程处理类
class _SubIsolate {
  
  /// 入口函数
  static main(SendPort sendPort) async {
    
    // 把子Isolate的接收通道丢给主Isolate
    ReceivePort receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);
    
    // 事件循环
    Completer closedCompleter = Completer();
    receivePort.listen((data) {
      
      if (data is! List) {
        return;
      }
      
      APNetworkIsolateMesssage messsage = APNetworkIsolateMesssage.fromMap(data[0]);
      // 关闭命令
      if (messsage.type == APNetworkIsolateMesssageType.Closed) {
        closedCompleter.complete();
        return;
      }
      
      // 解析任务
      if (messsage.type == APNetworkIsolateMesssageType.ParseJson) {
        parseJson(sendPort, messsage, data[1]);
      }
    });
    
    await closedCompleter.future;
    receivePort.close();
  }
  
  /// Json解析方法
  static void parseJson(SendPort sendPort, APNetworkIsolateMesssage messsage, String jsonString) {
  
    Map<String, dynamic> map = json.decode(jsonString);
    APNetworkIsolateMesssage sendMsg = APNetworkIsolateMesssage(
        type: APNetworkIsolateMesssageType.ParseJson,
    );
    sendMsg._eventId = messsage._eventId;
    sendPort.send([sendMsg.toMap(), map]);
  }
}