//
//  OpenXCClasses.swift
//  openxc-ios-framework
//
//  Created by Tim Buick on 2016-08-10.
//  Copyright (c) 2016 Ford Motor Company Licensed under the BSD license.
//  Version 0.9.2
//

import Foundation


public struct OpenXCConstants {
  static let C5_VI_NAME_PREFIX = "OPENXC"
  static let C5_OPENXC_BLE_SERVICE_UUID = "6800D38B-423D-4BDB-BA05-C9276D8453E1"
  static let C5_OPENXC_BLE_CHARACTERISTIC_NOTIFY_UUID = "6800D38B-5262-11E5-885D-FEFF819CDCE3"
  static let C5_OPENXC_BLE_CHARACTERISTIC_WRITE_UUID = "6800D38B-5262-11E5-885D-FEFF819CDCE2"
}


public enum VehicleMessageType: NSString {
  case MeasurementResponse
  case CommandRequest
  case CommandResponse
  case DiagnosticRequest
  case DiagnosticResponse
  case CanResponse
  case CanRequest
}

public enum VehicleCommandType: NSString {
  case version
  case device_id
  case passthrough
  case af_bypass
  case payload_format
  case predefined_odb2
  case modem_configuration
  case sd_mount_status
  case rtc_configuration
}


public class VehicleBaseMessage {
  public init() {
    
  }
  public var timestamp: NSInteger = 0
  public var type: VehicleMessageType = .MeasurementResponse
  func traceOutput() -> NSString {
    return "{}"
  }
}


public class VehicleMeasurementResponse : VehicleBaseMessage {
  override init() {
    value = NSNull()
    event = NSNull()
    super.init()
    type = .MeasurementResponse
  }
  public var name : NSString = ""
  public var value : AnyObject
  public var isEvented : Bool = false
  public var event : AnyObject
  override func traceOutput() -> NSString {
    var out : String = ""
    if value is String {
      out = "{\"timestamp\":\(timestamp),\"name\":\"\(name)\",\"value\":\"\(value)\""
    } else {
      out = "{\"timestamp\":\(timestamp),\"name\":\"\(name)\",\"value\":\(value)"
    }
    if isEvented {
      if event is String {
        out.appendContentsOf(",\"event\":\"\(event)\"")
      } else {
        out.appendContentsOf(",\"event\":\(event)")
      }
    }
    out.appendContentsOf("}")
    return out
  }
  public func valueIsBool() -> Bool {
    if value is NSNumber {
      let nv = value as! NSNumber
      if nv.isEqualToValue(NSNumber(bool: true)) {
        return true
      } else if nv.isEqualToValue(NSNumber(bool:false)) {
        return true
      }
    }
    return false
  }
}


public class VehicleCommandRequest : VehicleBaseMessage {
  public override init() {
    super.init()
    type = .CommandResponse
  }
  public var command : VehicleCommandType = .version
  public var bus : NSInteger = 0
  public var enabled : Bool = false
  public var bypass : Bool = false
  public var format : NSString = ""
  public var server_host : NSString = ""
  public var server_port : NSInteger = 0
  public var unix_time : NSInteger = 0
}

public class VehicleCommandResponse : VehicleBaseMessage {
  public override init() {
    super.init()
    type = .CommandResponse
  }
  public var command_response : NSString = ""
  public var message : NSString = ""
  public var status : Bool = false
  override func traceOutput() -> NSString {
    return "{\"timestamp\":\(timestamp),\"command_response\":\"\(command_response)\",\"message\":\"\(message)\",\"status\":\(status)}"
  }
}



public class VehicleDiagnosticRequest : VehicleBaseMessage {
  public override init() {
    super.init()
    type = .DiagnosticRequest
  }
  public var bus : NSInteger = 0
  public var message_id : NSInteger = 0
  public var mode : NSInteger = 0
  public var pid : NSInteger?
  public var payload : NSString = ""
  public var name : NSString = ""
  public var multiple_responses : Bool = false
  public var frequency : NSInteger = 0
  public var decoded_type : NSString = ""
}



public class VehicleDiagnosticResponse : VehicleBaseMessage {
  public override init() {
    super.init()
    type = .DiagnosticResponse
  }
  public var bus : NSInteger = 0
  public var message_id : NSInteger = 0
  public var mode : NSInteger = 0
  public var pid : NSInteger?
  public var success : Bool = false
  public var negative_response_code : NSInteger = 0
  public var payload : NSString = ""
  public var value : NSInteger?
}


public class VehicleCanResponse : VehicleBaseMessage {
  public override init() {
    super.init()
    type = .CanResponse
  }
  public var bus : NSInteger = 0
  public var id : NSInteger = 0
  public var data : NSString = ""
  public var format : NSString = "standard"
}

public class VehicleCanRequest : VehicleBaseMessage {
  public override init() {
    super.init()
    type = .CanRequest
  }
  public var bus : NSInteger = 0
  public var id : NSInteger = 0
  public var data : NSString = ""
  public var format : NSString = ""
}


