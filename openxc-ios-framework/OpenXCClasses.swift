//
//  OpenXCClasses.swift
//  openxc-ios-framework
//
//  Created by Tim Buick on 2016-08-10.
//  Copyright © 2016 Bug Labs. All rights reserved.
//

import Foundation



public enum VehicleMessageType: NSString {
  case MeasurementResponse
  case CommandRequest
  case CommandResponse
  case DiagnosticRequest
  case DiagnosticResponse
  case CanResponse
}

public enum VehicleCommandType: NSString {
  case version
  case device_id
  case passthrough
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
  public var bus : NSString = ""
  public var enabled : Bool = false
  public var bypass : Bool = false
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
  override init() {
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
  override init() {
    super.init()
    type = .CanResponse
  }
  public var bus : NSInteger = 0
  public var id : NSInteger = 0
  public var data : NSString = ""
  public var format : NSString = "standard"
}


