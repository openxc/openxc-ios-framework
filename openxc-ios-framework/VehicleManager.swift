//
//  VehicleManager.swift
//  openXCSwift
//
//  Created by Tim Buick on 2016-06-16.
//  Copyright (c) 2016 Ford Motor Company Licensed under the BSD license.
//  Vrsion 0.9.2
//

import Foundation
import CoreBluetooth
import ProtocolBuffers


// FIXME: comparison operators with optionals were removed from the Swift Standard Libary.
// Consider refactoring the code to use the non-optional operators.
fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

// FIXME: comparison operators with optionals were removed from the Swift Standard Libary.
// Consider refactoring the code to use the non-optional operators.
fileprivate func > <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l > r
  default:
    return rhs < lhs
  }
}

// public enum VehicleManagerStatusMessage
// values reported to managerCallback if defined
public enum VehicleManagerStatusMessage: Int {
  case c5DETECTED=1               // C5 VI was detected
  case c5CONNECTED=2              // C5 VI connection established
  case c5SERVICEFOUND=3           // C5 VI OpenXC service detected
  case c5NOTIFYON=4               // C5 VI notification enabled
  case c5DISCONNECTED=5           // C5 VI disconnected
  case trace_SOURCE_END=6         // configured trace input end of file reached
  case trace_SINK_WRITE_ERROR=7   // error in writing message to trace file
  case ble_RX_DATA_PARSE_ERROR=8  // error in parsing data received from VI
 
}
// This enum is outside of the main class for ease of use in the client app. It allows
// for referencing the enum without the class hierarchy in front of it. Ie. the enums
// can be accessed directly as .C5DETECTED for example


// public enum VehicleManagerConnectionState
// values reported in public variable connectionState
/*public enum VehicleManagerConnectionState: Int {
  case notConnected=0           // not connected to any C5 VI
  case scanning=1               // VM is allocation and scanning for nearby VIs
  case connectionInProgress=2   // connection in progress (connecting/searching for services)
  case connected=3              // connection established (but not ready to receive btle writes)
  case operational=4            // C5 VI operational (notify enabled and writes accepted)
}*/
// This enum is outside of the main class for ease of use in the client app. It allows
// for referencing the enum without the class hierarchy in front of it. Ie. the enums
// can be accessed directly as .C5DETECTED for example



open class VehicleManager: NSObject {


  // MARK: Singleton Init
  // This signleton init allows mutiple controllers to access the same instantiation
  // of the VehicleManager. There is only a single instantiation of the VehicleManager
  // for the entire client app
  static open let sharedInstance: VehicleManager = {
    let instance = VehicleManager()
    return instance
  }()
  fileprivate override init() {
  }

  // MARK: Class Vars
  // -----------------
 /*
  // CoreBluetooth variables
  fileprivate var centralManager: CBCentralManager!
  fileprivate var openXCPeripheral: CBPeripheral!
  fileprivate var openXCService: CBService!
  fileprivate var openXCNotifyChar: CBCharacteristic!
  fileprivate var openXCWriteChar: CBCharacteristic!
  */
  // dictionary of discovered openXC peripherals when scanning
 // fileprivate var foundOpenXCPeripherals: [String:CBPeripheral] = [String:CBPeripheral]()
  
  // config for auto connecting to first discovered VI
   //open var autoConnectPeripheral : Bool = true
   //fileprivate var autoConnectPeripheral : Bool = true
  // config for outputting debug messages to console
    fileprivate var managerDebug : Bool = false
    
  // config for protobuf vs json BLE mode, defaults to JSON
  public var jsonMode : Bool = true
  
  // optional variable holding callback for VehicleManager status updates
   var managerCallback: TargetAction?
  
  // data buffer for receiving raw BTLE data
  public var RxDataBuffer: NSMutableData! = NSMutableData()
  
  // data buffer for storing vehicle messages to send to BTLE
  //Ranjan changed fileprivate to public due to travis fail
  public var BLETxDataBuffer: NSMutableArray! = NSMutableArray()

  public var tempDataBuffer : NSMutableData! = NSMutableData()

  // BTLE transmit semaphore variable
  fileprivate var BLETxWriteCount: Int = 0
  // BTLE transmit token increment variable
  fileprivate var BLETxSendToken: Int = 0
  
  // ordered list for storing callbacks for in progress vehicle commands
  fileprivate var BLETxCommandCallback = [TargetAction]()
  // mirrored ordered list for storing command token for in progress vehicle commands
  fileprivate var BLETxCommandToken = [String]()
  // 'default' command callback. If this is defined, it takes priority over any other callback
  // defined above
  fileprivate var defaultCommandCallback : TargetAction?
  
  
  // dictionary for holding registered measurement message callbacks
  // pairing measurement String with callback action
  fileprivate var measurementCallbacks = [NSString:TargetAction]()
  // default callback action for measurement messages not registered above
  fileprivate var defaultMeasurementCallback : TargetAction?
  // dictionary holding last received measurement message for each measurement type
  fileprivate var latestVehicleMeasurements = [NSString:VehicleMeasurementResponse]()
  
  // dictionary for holding registered diagnostic message callbacks
  // pairing bus-id-mode(-pid) String with callback action
  fileprivate var diagCallbacks = [NSString:TargetAction]()
  // default callback action for diagnostic messages not registered above
  fileprivate var defaultDiagCallback : TargetAction?
  
  // dictionary for holding registered diagnostic message callbacks
  // pairing bus-id String with callback action
  fileprivate var canCallbacks = [NSString:TargetAction]()
  // default callback action for can messages not registered above
  fileprivate var defaultCanCallback : TargetAction?
  
  // config variable determining whether trace output is generated
  fileprivate var traceFilesinkEnabled: Bool = false
  // config variable holding trace output file name
  fileprivate var traceFilesinkName: NSString = ""
  
  // config variable determining whether trace input is used instead of BTLE data
  fileprivate var traceFilesourceEnabled: Bool = false
  // config variable holding trace input file name
  fileprivate var traceFilesourceName: NSString = ""
  // private timer for trace input message send rate
  fileprivate var traceFilesourceTimer: Timer = Timer()
  // private file handle to trace input file
  fileprivate var traceFilesourceHandle: FileHandle?
  // private variable holding timestamps when last message received
  fileprivate var traceFilesourceLastMsgTime: NSInteger = 0
  fileprivate var traceFilesourceLastActualTime: NSInteger = 0
  // this tells us we're tracking the time held in the trace file
  fileprivate var traceFilesourceTimeTracking: Bool = false
  
  // public variable holding VehicleManager connection state enum
 // open var connectionState: VehicleManagerConnectionState! = .notConnected
  // public variable holding number of messages received since last Connection established

 //open var messageCount: Int = 0
  //Connected to network simulator
  open var isNetworkConnected: Bool = false

 //Iphone device blutooth is on/fff status
  open var isDeviceBluetoothIsOn :Bool = false

  
  var callbackHandler: ((Bool) -> ())?  = nil
  

    //Connected to Ble simulator
   // open var isBleConnected: Bool = false

    //Connected to tracefile simulator
    open var isTraceFileConnected: Bool = false

  // diag last req msg id
  open var lastReqMsg_id : NSInteger = 0
  
  // MARK: Class Functions
  
  // set the callback for VM status updates
  open func setManagerCallbackTarget<T: AnyObject>(_ target: T, action: @escaping (T) -> (NSDictionary) -> ()) {
    managerCallback = TargetActionWrapper(key:"", target: target, action: action)
  }
  
  // change the debug config for the VM
  open func setManagerDebug(_ on:Bool) {
    managerDebug = on
  }
  
  // private debug log function gated by the debug setting
  fileprivate func vmlog(_ strings:Any...){
    if managerDebug {
      let d = Date()
      let df = DateFormatter()
      df.dateFormat = "[H:m:ss.SSS]"
      print(df.string(from: d),terminator:"")
      print(" ",terminator:"")
      for string in strings {
        print(string,terminator:"")
      }
      print("")
    }
  }
  
  
  // change the auto connect config for the VM
  //open func setAutoconnect(_ on:Bool) {
    //autoConnectPeripheral = on
  //}
  
  
  // change the data format for the VM
  open func setProtobufMode(_ on:Bool) {

    if on{
    jsonMode = false
    }
    else{
    jsonMode = true
    }
  }

  
  // return the latest message received for a given measurement string name
//  open func getLatest(_ key:NSString) -> VehicleMeasurementResponse {
//    if let entry = latestVehicleMeasurements[key] {
//      return entry as! VehicleMeasurementResponse
//    }
//    return VehicleMeasurementResponse()
//  }

  open func getLatest(_ key:NSString) -> VehicleMeasurementResponse? {
    return latestVehicleMeasurements[key]
  }
  
  // add a callback for a given measurement string name
  open func addMeasurementTarget<T: AnyObject>(_ key: NSString, target: T, action: @escaping (T) -> (NSDictionary) -> ()) {
    measurementCallbacks[key] = TargetActionWrapper(key:key, target: target, action: action)
  }
  
  // clear the callback for a given measurement string name
  open func clearMeasurementTarget(_ key: NSString) {
    measurementCallbacks.removeValue(forKey: key)
  }
  
  // add a default callback for any measurement messages not include in specified callbacks
  open func setMeasurementDefaultTarget<T: AnyObject>(_ target: T, action: @escaping (T) -> (NSDictionary) -> ()) {
    defaultMeasurementCallback = TargetActionWrapper(key:"", target: target, action: action)
  }
  
  // clear default callback (by setting the default callback to a null method)
  open func clearMeasurementDefaultTarget() {
    defaultMeasurementCallback = TargetActionWrapper(key: "", target: VehicleManager.sharedInstance, action: VehicleManager.CallbackNull)
  }

  // send a command message with a callback for when the command response is received
  open func sendCommand<T: AnyObject>(_ cmd:VehicleCommandRequest, target: T, action: @escaping (T) -> (NSDictionary) -> ()) -> String {
    vmlog("in sendCommand:target")
    
    // if we have a trace input file, ignore this request!
    if (traceFilesourceEnabled) {return ""}
    
    // save the callback in order, so we know which to call when responses are received
    BLETxSendToken += 1
    let key : String = String(BLETxSendToken)
    let act : TargetAction = TargetActionWrapper(key:key as NSString, target: target, action: action)
    BLETxCommandCallback.append(act)
    BLETxCommandToken.append(key)
    
    // common command send method
    sendCommandCommon(cmd)
    
    return key
    
  }
  
  // send a command message with no callback specified
  open func sendCommand(_ cmd:VehicleCommandRequest) {
    vmlog("in sendCommand")
    
    // if we have a trace input file, ignore this request!
    if (traceFilesourceEnabled) {return}
    
    // we still need to keep a spot for the callback in the ordered list, so
    // nothing gets out of sync. Assign the callback to the null callback method.
    BLETxSendToken += 1
    let key : String = String(BLETxSendToken)
    let act : TargetAction = TargetActionWrapper(key: "", target: VehicleManager.sharedInstance, action: VehicleManager.CallbackNull)
    BLETxCommandCallback.append(act)
    BLETxCommandToken.append(key)
    
    // common command send method
    sendCommandCommon(cmd)
    
  }
  
  
  // add a default callback for any measurement messages not include in specified callbacks
  open func setCommandDefaultTarget<T: AnyObject>(_ target: T, action: @escaping (T) -> (NSDictionary) -> ()) {
    defaultCommandCallback = TargetActionWrapper(key:"", target: target, action: action)
  }
  
  // clear default callback (by setting the default callback to a null method)
  open func clearCommandDefaultTarget() {
    defaultCommandCallback = nil
  }

  // send a diagnostic message with a callback for when the diag command response is received
  open func sendDiagReq<T: AnyObject>(_ cmd:VehicleDiagnosticRequest, target: T, cmdaction: @escaping (T) -> (NSDictionary) -> ()) -> String {
    vmlog("in sendDiagReq:cmd")
    
    // if we have a trace input file, ignore this request!
    if (traceFilesourceEnabled) {return ""}
    
    // save the callback in order, so we know which to call when responses are received
    BLETxSendToken += 1
    let key : String = String(BLETxSendToken)
    let act : TargetAction = TargetActionWrapper(key:key as NSString, target: target, action: cmdaction)
    BLETxCommandCallback.append(act)
    BLETxCommandToken.append(key)
    
    // common diag send method
    sendDiagCommon(cmd)
    
    return key
    
  }
  
  // send a diagnostic message with no callback specified
  open func sendDiagReq(_ cmd:VehicleDiagnosticRequest) {
    vmlog("in sendDiagReq")
    
    // if we have a trace input file, ignore this request!
    if (traceFilesourceEnabled) {return}
    
    // we still need to keep a spot for the callback in the ordered list, so
    // nothing gets out of sync. Assign the callback to the null callback method.
    BLETxSendToken += 1
    let key : String = String(BLETxSendToken)
    let act : TargetAction = TargetActionWrapper(key: "", target: VehicleManager.sharedInstance, action: VehicleManager.CallbackNull)
    BLETxCommandCallback.append(act)
    BLETxCommandToken.append(key)
    
    // common diag send method
    vmlog("diag cmd..", cmd)
    sendDiagCommon(cmd)
    
  }
  
  
  // set a callback for any diagnostic messages received with a given set of keys.
  // The key is bus-id-mode-pid if there are 4 keys specified in the parameter.
  // The key becomes bus-id-mode-X if there are 3 keys specified, indicating that pid does not exist
  open func addDiagnosticTarget<T: AnyObject>(_ keys: [NSInteger], target: T, action: @escaping (T) -> (NSDictionary) -> ()) {
    let key : NSMutableString = ""
    var first : Bool = true
    for i in keys {
      if !first {
        key.append("-")
      }
      first=false
      key.append(String(i))
    }
    if keys.count == 3 {
      key.append("-X")
    }
    // key string has been created
    vmlog("add diag key=",key)
    // save the callback associated with the key
    diagCallbacks[key] = TargetActionWrapper(key:key, target: target, action: action)
  }
  
  // clear a callback for a given set of keys, defined as above.
  open func clearDiagnosticTarget(_ keys: [NSInteger]) {
    let key : NSMutableString = ""
    var first : Bool = true
    for i in keys {
      if !first {
        key.append("-")
      }
      first=false
      key.append(String(i))
    }
    if keys.count == 3 {
      key.append("-X")
    }
    // key string has been created
    vmlog("rm diag key=",key)
    // clear the callback associated with the key
    diagCallbacks.removeValue(forKey: key)
  }
  
  // set a default callback for any diagnostic messages with a key set not specified above
  open func setDiagnosticDefaultTarget<T: AnyObject>(_ target: T, action: @escaping (T) -> (NSDictionary) -> ()) {
    defaultDiagCallback = TargetActionWrapper(key:"", target: target, action: action)
  }
  
  // clear the default diag callback
  open func clearDiagnosticDefaultTarget() {
    defaultDiagCallback = TargetActionWrapper(key: "", target: VehicleManager.sharedInstance, action: VehicleManager.CallbackNull)
  }
  

  // set a callback for any can messages received with a given set of keys.
  // The key is bus-id and 2 keys must be specified always
  open func addCanTarget<T: AnyObject>(_ keys: [NSInteger], target: T, action: @escaping (T) -> (NSDictionary) -> ()) {
    let key : NSMutableString = ""
    var first : Bool = true
    for i in keys {
      if !first {
        key.append("-")
      }
      first=false
      key.append(String(i))
    }
    // key string has been created
    vmlog("add can key=",key)
    // save the callback associated with the key
    diagCallbacks[key] = TargetActionWrapper(key:key, target: target, action: action)
  }
  
  // clear a callback for a given set of keys, defined as above.
  open func clearCanTarget(_ keys: [NSInteger]) {
    let key : NSMutableString = ""
    var first : Bool = true
    for i in keys {
      if !first {
        key.append("-")
      }
      first=false
      key.append(String(i))
    }
    // key string has been created
    vmlog("rm can key=",key)
    // clear the callback associated with the key
    diagCallbacks.removeValue(forKey: key)
  }
  
  
  // set a default callback for any can messages with a key set not specified above
  open func setCanDefaultTarget<T: AnyObject>(_ target: T, action: @escaping (T) -> (NSDictionary) -> ()) {
    defaultCanCallback = TargetActionWrapper(key:"", target: target, action: action)
  }
  
  // clear the can diag callback
  open func clearCanDefaultTarget() {
    defaultCanCallback = TargetActionWrapper(key: "", target: VehicleManager.sharedInstance, action: VehicleManager.CallbackNull)
  }
  
  
  
  // send a can message
  open func sendCanReq(_ cmd:VehicleCanRequest) {
    vmlog("in sendCanReq")
    
    // if we have a trace input file, ignore this request!
    if (traceFilesourceEnabled) {return}
    
    // common can send method
    sendCanCommon(cmd)
    
  }

  
  ////////////////
  // private functions
  
  
  // common function for sending a VehicleCommandRequest
  fileprivate func sendCommandCommon(_ cmd:VehicleCommandRequest) {
    vmlog("in sendCommandCommon")
    
    if !jsonMode {
      // in protobuf mode, build the command message
      let cbuild = ControlCommand.Builder()
      if cmd.command == .version {_ = cbuild.setType(.version)}
      if cmd.command == .device_id {_ = cbuild.setType(.deviceId)}
      if cmd.command == .platform {_ = cbuild.setType(.platform)}
      if cmd.command == .passthrough {
        let cbuild2 = PassthroughModeControlCommand.Builder()
        _ = cbuild2.setBus(Int32(cmd.bus))
        _ = cbuild2.setEnabled(cmd.enabled)
        _ = cbuild.setPassthroughModeRequest(cbuild2.buildPartial())
        _ = cbuild.setType(.passthrough)
      }
      if cmd.command == .af_bypass {
        let cbuild2 = AcceptanceFilterBypassCommand.Builder()
        _ = cbuild2.setBus(Int32(cmd.bus))
        _ = cbuild2.setBypass(cmd.bypass)
        _ = cbuild.setAcceptanceFilterBypassCommand(cbuild2.buildPartial())
        _ = cbuild.setType(.acceptanceFilterBypass)
      }
      if cmd.command == .payload_format {
        let cbuild2 = PayloadFormatCommand.Builder()
        if cmd.format == "json" {_ = cbuild2.setFormat(.json)}
        if cmd.format == "protobuf" {_ = cbuild2.setFormat(.protobuf)}
        _ = cbuild.setPayloadFormatCommand(cbuild2.buildPartial())
        _ = cbuild.setType(.payloadFormat)
      }
      if cmd.command == .predefined_odb2 {
        let cbuild2 = PredefinedObd2RequestsCommand.Builder()
        _ = cbuild2.setEnabled(cmd.enabled)
        _ = cbuild.setPredefinedObd2RequestsCommand(cbuild2.buildPartial())
        _ = cbuild.setType(.predefinedObd2Requests)
      }
      if cmd.command == .modem_configuration {
        _ = cbuild.setType(.modemConfiguration)
        let cbuild2 = ModemConfigurationCommand.Builder()
        let srv = ServerConnectSettings.Builder()
        _ = srv.setHost(cmd.server_host as String)
        _ = srv.setPort(UInt32(cmd.server_port))
        _ = cbuild2.setServerConnectSettings(srv.buildPartial())
        _ = cbuild.setModemConfigurationCommand(cbuild2.buildPartial())
      }
      if cmd.command == .rtc_configuration {
        let cbuild2 = RtcconfigurationCommand.Builder()
        _ = cbuild2.setUnixTime(UInt32(cmd.unix_time))
        _ = cbuild.setRtcConfigurationCommand(cbuild2.buildPartial())
        _ = cbuild.setType(.rtcConfiguration)
      }
      if cmd.command == .sd_mount_status {_ = cbuild.setType(.sdMountStatus)}
      
      let mbuild = VehicleMessage.Builder()
      _ = mbuild.setType(.controlCommand)
      
      do {
        let cmsg = try cbuild.build()
        _ = mbuild.setControlCommand(cmsg)
        let mmsg = try mbuild.build()
        //print (mmsg)
        
        
        let cdata = mmsg.data()
        let cdata2 = NSMutableData()
        let prepend : [UInt8] = [UInt8(cdata.count)]
        cdata2.append(Data(bytes: UnsafePointer<UInt8>(prepend), count:1))
        cdata2.append(cdata)
        //print(cdata2)
        
        // append to tx buffer
        BLETxDataBuffer.add(cdata2)
        
        // trigger a BLE data send
        BluetoothManager.sharedInstance.BLESendFunction()

      } catch {
        print("cmd msg build failed")
      }
      
      return
    }
    
    // we're in json mode
    var cmdstr = ""
    // decode the command type and build the command depending on the command

    if cmd.command == .version || cmd.command == .device_id || cmd.command == .sd_mount_status || cmd.command == .platform {
      // build the command json
      cmdstr = "{\"command\":\"\(cmd.command.rawValue)\"}\0"
    }
    else if cmd.command == .passthrough {
      // build the command json
      cmdstr = "{\"command\":\"\(cmd.command.rawValue)\",\"bus\":\(cmd.bus),\"enabled\":\(cmd.enabled)}\0"
    }
    else if cmd.command == .af_bypass {
      // build the command json
      cmdstr = "{\"command\":\"\(cmd.command.rawValue)\",\"bus\":\(cmd.bus),\"bypass\":\(cmd.bypass)}\0"
    }
    else if cmd.command == .payload_format {
      // build the command json
      cmdstr = "{\"command\":\"\(cmd.command.rawValue)\",\"format\":\"\(cmd.format)\"}\0"
    }
    else if cmd.command == .predefined_odb2 {
      // build the command json
      cmdstr = "{\"command\":\"\(cmd.command.rawValue)\",\"enabled\":\(cmd.enabled)}\0"
    }
    else if cmd.command == .modem_configuration {
      // build the command json
      cmdstr = "{\"command\":\"\(cmd.command.rawValue)\",\"server\":{\"host\":\"\(cmd.server_host)\",\"port\":\(cmd.server_port)}}\0"
    }
    else if cmd.command == .rtc_configuration {
      // build the command json
      let timeInterval = Date().timeIntervalSince1970
      cmd.unix_time = NSInteger(timeInterval);
      print("timestamp is..",cmd.unix_time)
      cmdstr = "{\"command\":\"\(cmd.command.rawValue)\",\"unix_time\":\"\(cmd.unix_time)\"}\0"
    } else {
      // unknown command!
      return
      
    }
    
    // append to tx buffer
    BLETxDataBuffer.add(cmdstr.data(using: String.Encoding.utf8, allowLossyConversion: false)!)
    
    // trigger a BLE data send
    BluetoothManager.sharedInstance.BLESendFunction()
    
  }
  
  
  // common function for sending a VehicleDiagnosticRequest
  fileprivate func sendDiagCommon(_ cmd:VehicleDiagnosticRequest) {
    vmlog("in sendDiagCommon")
    
    if !jsonMode {
      // in protobuf mode, build diag message
      let cbuild = ControlCommand.Builder()
      _ = cbuild.setType(.diagnostic)
      let c2build = DiagnosticControlCommand.Builder()
      _ = c2build.setAction(.add)
      let dbuild = DiagnosticRequest.Builder()
      _ = dbuild.setBus(Int32(cmd.bus))
      _ = dbuild.setMessageId(UInt32(cmd.message_id))
      _ = dbuild.setMode(UInt32(cmd.mode))
      if cmd.pid != nil {
        _ = dbuild.setPid(UInt32(cmd.pid!))
      }
      if cmd.frequency>0 {
        _ =  dbuild.setFrequency(Double(cmd.frequency))
      }
      let mbuild = VehicleMessage.Builder()
      _ = mbuild.setType(.controlCommand)
      
      do {
        let dmsg = try dbuild.build()
        _ = c2build.setRequest(dmsg)
        let c2msg = try c2build.build()
        _ = cbuild.setDiagnosticRequest(c2msg)
        let cmsg = try cbuild.build()
        _ = mbuild.setControlCommand(cmsg)
        let mmsg = try mbuild.build()
        //print (mmsg)
        
        
        let cdata = mmsg.data()
        let cdata2 = NSMutableData()
        let prepend : [UInt8] = [UInt8(cdata.count)]
        cdata2.append(Data(bytes: UnsafePointer<UInt8>(prepend), count:1))
        cdata2.append(cdata)
        //print(cdata2)
        
        // append to tx buffer
        BLETxDataBuffer.add(cdata2)
        
        // trigger a BLE data send
        BluetoothManager.sharedInstance.BLESendFunction()
        
      } catch {
        print("cmd msg build failed")
      }
      
      return
    }
    self.lastReqMsg_id = cmd.message_id

    // build the command json
    let cmdjson : NSMutableString = ""
    cmdjson.append("{\"command\":\"diagnostic_request\",\"action\":\"add\",\"request\":{\"bus\":\(cmd.bus),\"id\":\(cmd.message_id),\"mode\":\(cmd.mode)")
    
    if cmd.pid != nil {
      cmdjson.append(",\"pid\":\(cmd.pid!)")
    }
    if cmd.frequency > 0 {
      cmdjson.append(",\"frequency\":\(cmd.frequency)")
    }
    
    print("payload : \(cmd.payload)")
    
    if !cmd.payload.isEqual(to: "") {
      
      let payloadStr = String(cmd.payload)
      cmdjson.append(",\"payload\":")
      
      let char = "\""
      
      cmdjson.append(char)
      cmdjson.append(payloadStr)
      cmdjson.append(char)
    }
    
    cmdjson.append("}}\0")
    
    vmlog("sending diag cmd:",cmdjson)
    // append to tx buffer
    BLETxDataBuffer.add(cmdjson.data(using: String.Encoding.utf8.rawValue, allowLossyConversion: false)!)
    
    // trigger a BLE data send
    BluetoothManager.sharedInstance.BLESendFunction()
    
  }
  
  
  // common function for sending a VehicleCanRequest
  fileprivate func sendCanCommon(_ cmd:VehicleCanRequest) {
    vmlog("in sendCanCommon")
    
    
    
    if !jsonMode {
      // in protobuf mode, build the CAN message
      let cbuild = CanMessage.Builder()
      _ = cbuild.setBus(Int32(cmd.bus))
      _ = cbuild.setId(UInt32(cmd.id))
      let data = NSMutableData()
      var str : NSString = cmd.data
      while str.length>0 {
        let substr = str.substring(to: 1)
        var num = UInt8(substr, radix: 16)
        data.append(&num, length:1)
        str = str.substring(from: 2) as NSString
      }
      _ = cbuild.setData(data as Data)
      
      let mbuild = VehicleMessage.Builder()
      _ = mbuild.setType(.can)
      
      do {
        let cmsg = try cbuild.build()
        _ = mbuild.setCanMessage(cmsg)
        let mmsg = try mbuild.build()
        //print (mmsg)
        
        
        let cdata = mmsg.data()
        let cdata2 = NSMutableData()
        let prepend : [UInt8] = [UInt8(cdata.count)]
        cdata2.append(Data(bytes: UnsafePointer<UInt8>(prepend), count:1))
        cdata2.append(cdata)
        //print(cdata2)
        
        // append to tx buffer
        BLETxDataBuffer.add(cdata2)
        
        // trigger a BLE data send
        BluetoothManager.sharedInstance.BLESendFunction()
        
      } catch {
        print("cmd msg build failed")
      }
      
      return
    }
    
    
    
    
    // build the command json
    let cmd = "{\"bus\":\(cmd.bus),\"id\":\(cmd.id),\"data\":\"\(cmd.data)\"}"
    // append to tx buffer
    BLETxDataBuffer.add(cmd.data(using: String.Encoding.utf8, allowLossyConversion: false)!)
    
    // trigger a BLE data send
    BluetoothManager.sharedInstance.BLESendFunction()
    
  }
  
  
  // internal method used when a callback needs to be registered, but we don't
  // want it to actually do anything, for example a command request where we don't
  // want a callback for the command response. The command response is still received
  // but the callback registered comes here, and does nothing.
  //Ranjan changed fileprivate to public due to travis build fail
  public func CallbackNull(_ o:AnyObject) {
    vmlog("in CallbackNull")
  }
  

  
  //Methods For parssing diffrent messages ................
  
  ////////////////
  // Protobuf decoding
  /////////////////
  
  
  fileprivate func protobufDecoding(data_chunk:NSMutableData,packetlen:Int){
    var msg : VehicleMessage
    do {
      msg = try VehicleMessage.parseFrom(data: data_chunk as Data)
      //print(msg)
      
      
      let data_left : NSMutableData = NSMutableData()
      data_left.append(RxDataBuffer.subdata(with: NSMakeRange(packetlen+1, RxDataBuffer.length-packetlen-1)))
      RxDataBuffer = data_left
      
      var decoded = false
      
      // measurement messages (normal and evented)
      ///////////////////////////////////////////
      if msg.type == .simple {
        
        decoded = true
        self.protobufMeasurementMessage(msg : msg)
      }
      
      // Command Response messages
      /////////////////////////////
      if msg.type == .commandResponse {
        let nameValue = msg.commandResponse.type
        if nameValue != .diagnostic{
          decoded = true
          self.protobufCommandResponse(msg : msg)
        }
        
      }
      
      // Diagnostic messages
      /////////////////////////////
      if msg.type == .diagnostic {
        decoded = true
        print("Response Diagnostic>>>>\(msg)")
        self.protobufDignosticMessage(msg: msg)
      }
      
      // CAN messages
      /////////////////////////////
      if msg.type == .can {
        decoded = true
        self.protobufCanMessage(msg: msg)
        
      }
      
      if (!decoded) {
        // should never get here!
        if let act = managerCallback {
          act.performAction(["status":VehicleManagerStatusMessage.ble_RX_DATA_PARSE_ERROR.rawValue] as NSMutableDictionary)
        }
      }
    } catch {
      //self.jsonMode = true
      print("protobuf parse error")
      return
    }

  }
  
  fileprivate func protobufMeasurementMessage(msg : VehicleMessage){
    //let name = msg.simpleMessage.name
    let name = msg.simpleMessage.name as NSString
    
    // build measurement message
    let rsp : VehicleMeasurementResponse = VehicleMeasurementResponse()
    rsp.timestamp = Int(truncatingBitPattern:msg.timestamp)
    //rsp.name = msg.simpleMessage.name as NSString
    
    rsp.name = name
    
    if msg.simpleMessage.value.hasStringValue {rsp.value = msg.simpleMessage.value.stringValue as AnyObject}
    if msg.simpleMessage.value.hasBooleanValue {rsp.value = msg.simpleMessage.value.booleanValue as AnyObject}
    if msg.simpleMessage.value.hasNumericValue {rsp.value = msg.simpleMessage.value.numericValue as AnyObject}
    if msg.simpleMessage.hasEvent {
      rsp.isEvented = true
      if msg.simpleMessage.event.hasStringValue {rsp.event = msg.simpleMessage.event.stringValue as AnyObject}
      if msg.simpleMessage.event.hasBooleanValue {rsp.event = msg.simpleMessage.event.booleanValue as AnyObject}
      if msg.simpleMessage.event.hasNumericValue {rsp.event = msg.simpleMessage.event.numericValue as AnyObject}
    }
    
    // capture this message into the dictionary of latest messages
    // latestVehicleMeasurements.setValue(rsp, forKey:name as String)
    latestVehicleMeasurements[name] = rsp
    
    // look for a specific callback for this measurement name
    var found=false
    for key in measurementCallbacks.keys {
      let act = measurementCallbacks[key]
      // if act!.returnKey() as String == name {
      if act!.returnKey() == name {
        found=true
        act!.performAction(["vehiclemessage":rsp] as NSDictionary)
      }
    }
    // otherwise use the default callback if it exists
    if !found {
      if let act = defaultMeasurementCallback {
        act.performAction(["vehiclemessage":rsp] as NSDictionary)
      }
    }
    
  }
  

   fileprivate func protobufCommandResponse(msg : VehicleMessage){

    
    //          let name = msg.commandResponse.type.toString()
    let name = msg.commandResponse.type.description
    
    
    // build command response message
    let rsp : VehicleCommandResponse = VehicleCommandResponse()
    rsp.timestamp = Int(truncatingBitPattern:msg.timestamp)
    rsp.command_response = name.lowercased() as NSString
    rsp.message = msg.commandResponse.message as NSString
    rsp.status = msg.commandResponse.status
    

    // First see if the default command callback is defined. If it is
    // then that takes priority. This will be the most likely use case,
    // with a single command response handler.
    if let act = defaultCommandCallback {
      act.performAction(["vehiclemessage":rsp] as NSDictionary)
    }
      // Otherwise, grab the first callback message in the list of command callbacks.
      // They will be in order relative to when the commands are sent (VI guarantees
      // to response order). We need to check that the list of command callbacks
      // actually has something in it here (check for count>0) because if we're
      // receiving command responses via a trace file, then there was never an
      // actual command request message sent to the VI.
    else if BLETxCommandCallback.count > 0 {
      let ta : TargetAction = BLETxCommandCallback.removeFirst()
      let s : String = BLETxCommandToken.removeFirst()
      ta.performAction(["vehiclemessage":rsp,"key":s] as NSDictionary)
    }
  }
  
  fileprivate func protobufDignosticMessage(msg : VehicleMessage){

    // build diag response message
    let rsp : VehicleDiagnosticResponse = VehicleDiagnosticResponse()
    rsp.timestamp = Int(truncatingBitPattern:msg.timestamp)
    rsp.bus = Int(msg.diagnosticResponse.bus)
    rsp.message_id = Int(msg.diagnosticResponse.messageId)
    rsp.mode = Int(msg.diagnosticResponse.mode)
    if msg.diagnosticResponse.hasPid {rsp.pid = Int(msg.diagnosticResponse.pid)}
    rsp.success = msg.diagnosticResponse.success
    //   if msg.diagnosticResponse.hasPayload {rsp.payload = String(data:msg.diagnosticResponse.payload as Data,encoding: String.Encoding.utf8)! as NSString}
    //   if msg.diagnosticResponse.hasPayload {rsp.payload = (String(data:msg.diagnosticResponse.payload as Data,encoding: String.Encoding.utf8)! as NSString) as String}
    if msg.diagnosticResponse.hasValue {rsp.value = Int(msg.diagnosticResponse.value)}
    
    if rsp.value != nil {
       rsp.success = true//msg.diagnosticResponse.success
    }
    // build the key that identifies this diagnostic response
    // bus-id-mode-[X or pid]
    let tupple : NSMutableString = ""
    tupple.append("\(String(rsp.bus))-\(String(rsp.message_id))-\(String(rsp.mode))-")
    if rsp.pid != nil {
      tupple.append(String(describing: rsp.pid))
    } else {
      tupple.append("X")
    }
    
    // TODO: debug printouts, maybe remove
    if rsp.value != nil {
      if rsp.pid != nil {
        vmlog("diag rsp msg:\(rsp.bus) id:\(rsp.message_id) mode:\(rsp.mode) pid:\(rsp.pid) success:\(rsp.success) value:\(rsp.value)")
      } else {
        vmlog("diag rsp msg:\(rsp.bus) id:\(rsp.message_id) mode:\(rsp.mode) success:\(rsp.success) value:\(rsp.value)")
      }
    } else {
      if rsp.pid != nil {
        vmlog("diag rsp msg:\(rsp.bus) id:\(rsp.message_id) mode:\(rsp.mode) pid:\(rsp.pid) success:\(rsp.success) payload:\(rsp.payload)")
      } else {
        vmlog("diag rsp msg:\(rsp.bus) id:\(rsp.message_id) mode:\(rsp.mode) success:\(rsp.success) value:\(rsp.payload)")
      }
    }
    ////////////////////////////
    
    // look for a specific callback for this diag response based on tupple created above
    var found=false
    for key in diagCallbacks.keys {
      let act = diagCallbacks[key]
      if act!.returnKey() == tupple {
        found=true
        act!.performAction(["vehiclemessage":rsp] as NSDictionary)
      }
    }
    // otherwise use the default callback if it exists
    if !found {
      if let act = defaultDiagCallback {
        act.performAction(["vehiclemessage":rsp] as NSDictionary)
      }
    }
  }
  
  fileprivate func protobufCanMessage(msg : VehicleMessage){
    // build CAN response message
    let rsp : VehicleCanResponse = VehicleCanResponse()
    rsp.timestamp = Int(truncatingBitPattern:msg.timestamp)
    rsp.bus = Int(msg.canMessage.bus)
    rsp.id = Int(msg.canMessage.id)
    rsp.data = String(data:msg.canMessage.data as Data,encoding: String.Encoding.utf8)! as NSString
    
    // TODO: remove debug statement?
    vmlog("CAN bus:\(rsp.bus) status:\(rsp.id) payload:\(rsp.data)")
    /////////////////////////////////
    
    
    // build the key that identifies this CAN response
    // bus-id
    let tupple = "\(String(rsp.bus))-\(String(rsp.id))"
    
    // look for a specific callback for this CAN response based on tupple created above
    var found=false
    for key in canCallbacks.keys {
      let act = canCallbacks[key]
      if act!.returnKey() as String == tupple {
        found=true
        act!.performAction(["vehiclemessage":rsp] as NSDictionary)
      }
    }
    // otherwise use the default callback if it exists
    if !found {
      if let act = defaultCanCallback {
        act.performAction(["vehiclemessage":rsp] as NSDictionary)
      }
    }
  }
  

  ////////////////
  // JSON decoding
  /////////////////
  fileprivate func jsonDecoding(data_chunk:NSMutableData){
    do {
      
      // decode json
      let json = try JSONSerialization.jsonObject(with: data_chunk as Data, options: .mutableContainers) as! [String:AnyObject]
      //print(json)
      // every message will have a timestamp
      
      //Ranjan:  Added NSNumber in timestamp to parse as it is in number format then convert nsnumber to integer as per requirment.
      var timestamp : NSInteger = 0
      var timestamp1 : NSNumber = 0
      if json["timestamp"] != nil {
        timestamp1 = json["timestamp"]  as! NSNumber
        timestamp = NSInteger(timestamp1.int64Value)
        // NSLog("%d",timestamp)
      }
      
      
      // insert a delay if we're reading from a tracefile
      // and we're tracking the timestamps in the file to
      // decide when to send the next message
      if traceFilesourceTimeTracking {
        let msTimeNow = Int(Date.timeIntervalSinceReferenceDate*1000)
        if traceFilesourceLastMsgTime == 0 {
          // first time
          traceFilesourceLastMsgTime = timestamp
          traceFilesourceLastActualTime = msTimeNow

        }
        let msgDelta = timestamp - traceFilesourceLastMsgTime
        let actualDelta = msTimeNow - traceFilesourceLastActualTime
        let deltaDelta : Double = (Double(msgDelta) - Double(actualDelta))/1000.0
        if deltaDelta > 0 {
          Thread.sleep(forTimeInterval: deltaDelta)
        }

        traceFilesourceLastMsgTime = timestamp
        traceFilesourceLastActualTime = msTimeNow

      }
      
      
      // evented measurement rsp
      ///////////////////
      // evented measuerment messages will have an "event" key
      if let event = json["event"] as? NSString {
        
        self.Measurementrsp(json:json as [String:AnyObject],timestamp:timestamp)
      }
        

        
        // measurement rsp
        ///////////////////
        // normal measuerment messages will have an "name" key (but no "event" key)
      else if let name = json["name"] as? NSString {
        
        //vmlog(<#T##strings: Any...##Any#>)
        self.Measurementrsp(json:json as [String:AnyObject],timestamp:timestamp)
      }

        
        
        // command rsp
        ///////////////////
        // command response messages will have a "command_response" key
      else if let cmd_rsp = json["command_response"] as? NSString {
        let myValue = json["command_response"] as? NSString
        print(myValue as Any)
        if (myValue != "diagnostic_request") {
        self.commandResponse(timestamp: timestamp,cmd_rsp:cmd_rsp,json: json as [String:AnyObject])
      }
        
      }
        
        
        // diag rsp or CAN message
        ///////////////////
        // both diagnostic response and CAN response messages have an "id" key
      else if let id = json["id"] as? NSInteger {
        
        self.canMessagersp(json: json as [String:AnyObject],timestamp: timestamp,id:id)
        
      } else {
        // what the heck is it??
        if let act = managerCallback {
          act.performAction(["status":VehicleManagerStatusMessage.ble_RX_DATA_PARSE_ERROR.rawValue] as NSMutableDictionary)
        }
        
      }

      ///////
      // TODO: for debug, remove later
      //// fake out a CAN msg on every msg received!!
      /*
       if false {
       let rsp : VehicleCanResponse = VehicleCanResponse()
       rsp.timestamp = timestamp
       rsp.bus = Int(arc4random_uniform(2) + 1)
       rsp.id = Int(arc4random_uniform(20) + 2015)
       rsp.data = String(format:"%x",Int(arc4random_uniform(100000)+1))
       
       vmlog("CAN bus:\(rsp.bus) id:\(rsp.id) payload:\(rsp.data)")
       
       
       let tupple = "\(String(rsp.bus))-\(String(rsp.id))"
       
       var found=false
       for key in canCallbacks.keys {
       let act = canCallbacks[key]
       if act!.returnKey() == tupple {
       found=true
       act!.performAction(["vehiclemessage":rsp] as NSDictionary)
       }
       }
       if !found {
       if let act = defaultCanCallback {
       act.performAction(["vehiclemessage":rsp] as NSDictionary)
       }
       }
       
       }
       */
      //////////////////////////////////////////////
      
      
      
      // if trace file output is enabled, create a string from the message
      // and send it to the trace file writer
      if traceFilesinkEnabled {
        let str = String(data: data_chunk as Data,encoding: String.Encoding.utf8)
        TraceFileManager.sharedInstance.traceFileWriter(str!)
      }
      
      
      
      // Keep a count of how many messages were received in total
      // since connection. Can be used by the client app.
      BluetoothManager.sharedInstance.messageCount += 1
      
      
      
    } catch {
      // the json decode failed for some reason, usually data lost in connection
      vmlog("bad json")
      //self.jsonMode = false
      if let act = managerCallback {
        act.performAction(["status":VehicleManagerStatusMessage.ble_RX_DATA_PARSE_ERROR.rawValue] as NSMutableDictionary)
      }
    }
  }
  
  // evented measurement rsp
  ///////////////////
  // evented measuerment messages will have an "event" key
  fileprivate func eventedMeasurementrsp(json:[String:AnyObject],event:NSString,timestamp:NSInteger){
    
    
    // extract other keys from message
    let name = json["name"] as! NSString
    let value : AnyObject = json["value"] ?? NSNull()
    
    // build measurement message
    let rsp : VehicleMeasurementResponse = VehicleMeasurementResponse()
    rsp.timestamp = timestamp
    rsp.name = name
    rsp.value = value
    rsp.isEvented = true
    rsp.event = event
    
    // capture this message into the dictionary of latest messages
    //latestVehicleMeasurements.setValue(rsp, forKey:name as String)
    latestVehicleMeasurements[name] = rsp
    
    // look for a specific callback for this measurement name
    var found=false
    for key in measurementCallbacks.keys {
      let act = measurementCallbacks[key]
      if act!.returnKey() == name {
        found=true
        act!.performAction(["vehiclemessage":rsp] as NSDictionary)
      }
    }
    // otherwise use the default callback if it exists
    if !found {
      if let act = defaultMeasurementCallback {
        act.performAction(["vehiclemessage":rsp] as NSDictionary)
      }
    }
  }
  

  // measurement rsp
  ///////////////////
  // normal measuerment messages will have an "name" key (but no "event" key)
  fileprivate func Measurementrsp(json:[String:AnyObject],timestamp:NSInteger){
    
    // extract other keys from message
    let name = json["name"] as! NSString
    let value : AnyObject = json["value"] ?? NSNull()
    
    // build measurement message
    let rsp : VehicleMeasurementResponse = VehicleMeasurementResponse()
    rsp.value = value
    rsp.timestamp = timestamp
    rsp.name = name
    
    // capture this message into the dictionary of latest messages
    //latestVehicleMeasurements.setValue(rsp, forKey:name as String)
    latestVehicleMeasurements[name] = rsp
    
    // look for a specific callback for this measurement name
    var found=false
    for key in measurementCallbacks.keys {
      let act = measurementCallbacks[key]
      if act!.returnKey() == name {
        found=true
        act!.performAction(["vehiclemessage":rsp] as NSDictionary)
      }
    }
    // otherwise use the default callback if it exists
    if !found {
      if let act = defaultMeasurementCallback {
        act.performAction(["vehiclemessage":rsp] as NSDictionary)
      }
    }
  }
  
  // command rsp
  ///////////////////
  // command response messages will have a "command_response" key
  fileprivate func commandResponse(timestamp:NSInteger,cmd_rsp:NSString,json:[String:AnyObject]){
  
  
    // extract other keys from message
    var message : NSString = ""
    if let messageX = json["message"] as? NSString {
      message = messageX
    }
    var status : Bool = false
    if let statusX = json["status"] as? Bool {
      status = statusX
    }
    
    // build command response message
    let rsp : VehicleCommandResponse = VehicleCommandResponse()
    rsp.timestamp = timestamp
    rsp.message = message
    rsp.command_response = cmd_rsp
    rsp.status = status
    
    // First see if the default command callback is defined. If it is
    // then that takes priority. This will be the most likely use case,
    // with a single command response handler.
    if let act = defaultCommandCallback {
      act.performAction(["vehiclemessage":rsp] as NSDictionary)
    }
      // Otherwise, grab the first callback message in the list of command callbacks.
      // They will be in order relative to when the commands are sent (VI guarantees
      // to response order). We need to check that the list of command callbacks
      // actually has something in it here (check for count>0) because if we're
      // receiving command responses via a trace file, then there was never an
      // actual command request message sent to the VI.
    else if BLETxCommandCallback.count > 0 {
      let ta : TargetAction = BLETxCommandCallback.removeFirst()
      let s : String = BLETxCommandToken.removeFirst()
      ta.performAction(["vehiclemessage":rsp,"key":s] as NSDictionary)
    }
  }
  
  // diag rsp or CAN message
  ///////////////////
  // both diagnostic response and CAN response messages have an "id" key
  fileprivate func canMessagersp(json:[String:AnyObject],timestamp:NSInteger,id:NSInteger){

    
    // only diagnostic response messages have "success"
    if let success = json["success"] as? Bool {
      
  
       self.canMessageWithId(json: json, timestamp: timestamp, id: id, success: success)
      
      
      // CAN messages have "data"
    } else if let data = json["data"] as? NSString {
      
      // extract other keys from message
      var bus : NSInteger = 0
      if let busX = json["bus"] as? NSInteger {
        bus = busX
      }
      
      // build CAN response message
      let rsp : VehicleCanResponse = VehicleCanResponse()
      rsp.timestamp = timestamp
      rsp.bus = bus
      rsp.id = id
      rsp.data = data
      
      // TODO: remove debug statement?
      vmlog("CAN bus:\(bus) status:\(id) payload:\(data)")
      /////////////////////////////////
      
      
      // build the key that identifies this CAN response
      // bus-id
      let tupple = "\(String(bus))-\(String(id))"
      
      // look for a specific callback for this CAN response based on tupple created above
      var found=false
      for key in canCallbacks.keys {
        let act = canCallbacks[key]
        if act!.returnKey() as String == tupple {
          found=true
          act!.performAction(["vehiclemessage":rsp] as NSDictionary)
        }
      }
      // otherwise use the default callback if it exists
      if !found {
        if let act = defaultCanCallback {
          act.performAction(["vehiclemessage":rsp] as NSDictionary)

        }
      }
      
    } else {
      // should never get here!
      if let act = managerCallback {
        act.performAction(["status":VehicleManagerStatusMessage.ble_RX_DATA_PARSE_ERROR.rawValue] as NSMutableDictionary)
      }
    }
  }
  
  fileprivate func canMessageWithId(json:[String:AnyObject],timestamp:NSInteger,id:NSInteger,success:Bool){
    // extract other keys from message
    var bus : NSInteger = 0
    if let busX = json["bus"] as? NSInteger {
      bus = busX
    }
    var mode : NSInteger = 0
    if let modeX = json["mode"] as? NSInteger {
      mode = modeX
    }
    var pid : NSInteger?
    if let pidX = json["pid"] as? NSInteger {
      pid = pidX
    }
    

    var payload : NSString = ""
    if let payloadX = json["payload"] as? NSString {
      payload = payloadX
      print("payload : \(payload)")
      //
      //            var payload : Data?
      //            if let payloadX = json["payload"] as? NSString {
      //
      //                payload = payloadX.data(using: String.Encoding.utf8.rawValue, allowLossyConversion: false)
      //                print("payload : \(payload)")
      
      //            var payload : [UInt8] = []
      //            if let payloadX = json["payload"] as? String {
      //                payload = Array(payloadX.utf8)
      //                print("payload : \(payload)")
      
    }
    var value : NSInteger?
    if let valueX = json["value"] as? NSInteger {
      value = valueX
    }
    
    // build diag response message
    let rsp : VehicleDiagnosticResponse = VehicleDiagnosticResponse()
    rsp.timestamp = timestamp
    rsp.bus = bus
    rsp.message_id = id
    rsp.mode = mode
    rsp.pid = pid
    rsp.success = success
    rsp.payload = payload
    rsp.value = value
    
     //Adde for NRC fix
    if(!success){
      //success false, parse negative response code. For DID commands.
      if let nrcX = json["negative_response_code"] as? NSInteger{
        rsp.negative_response_code = nrcX
      }
    }
    
    // build the key that identifies this diagnostic response
    // bus-id-mode-[X or pid]
    let tupple : NSMutableString = ""
    var newid = 0
    if(self.lastReqMsg_id == 2015) { //exception for 7df
      newid = self.lastReqMsg_id
    } else {
      newid=id-8
    }
    tupple.append("\(String(bus))-\(String(newid))-\(String(mode))-")
    if pid != nil {
      tupple.append(String(describing: pid))
    } else {
      tupple.append("X")
    }
    
    // TODO: debug printouts, maybe remove
    if value != nil {
      if pid != nil {
        vmlog("diag rsp msg:\(bus) id:\(id) mode:\(mode) pid:\(pid) success:\(success) value:\(value)")
      } else {
        vmlog("diag rsp msg:\(bus) id:\(id) mode:\(mode) success:\(success) value:\(value)")
      }
    } else {
      if pid != nil {
        vmlog("diag rsp msg:\(bus) id:\(id) mode:\(mode) pid:\(pid) success:\(success) payload:\(payload)")
      } else {
        vmlog("diag rsp msg:\(bus) id:\(id) mode:\(mode) success:\(success) value:\(payload)")
      }
    }
    ////////////////////////////
    
    // look for a specific callback for this diag response based on tupple created above
    var found=false
    for key in diagCallbacks.keys {
      let act = diagCallbacks[key]
      if act!.returnKey() == tupple {
        found=true
        act!.performAction(["vehiclemessage":rsp] as NSDictionary)
      }
    }
    // otherwise use the default callback if it exists
    if !found {
      if let act = defaultDiagCallback {
        act.performAction(["vehiclemessage":rsp] as NSDictionary)
      }

    }
  }
  
  // Common function for parsing any received data into openXC messages.
  // The separator parameter allows data to be parsed when each message is
  // separated by different things, for example messages are separated by \0
  // when coming via BLE, and separated by 0xa when coming via a trace file
  // RXDataParser returns the timestamp of the parsed message out of convenience.
  
  //fileprivate to open
  open func RxDataParser(_ separator:UInt8) {
    
    
    ////////////////
    // Protobuf decoding
    /////////////////
    
    
    if !jsonMode && RxDataBuffer.length > 0 {
      var packetlenbyte:UInt8 = 0
      RxDataBuffer.getBytes(&packetlenbyte, length:MemoryLayout<UInt8>.size)
      let packetlen = Int(packetlenbyte)
      
      if RxDataBuffer.length > packetlen {
       // vmlog("found \(packetlen)B protobuf frame")
        let data_chunk : NSMutableData = NSMutableData()
        data_chunk.append(RxDataBuffer.subdata(with: NSMakeRange(1,packetlen)))
        
       // vmlog(data_chunk)
        
        self.protobufDecoding(data_chunk: data_chunk,packetlen:packetlen)
        
        // Keep a count of how many messages were received in total
        // since connection. Can be used by the client app.
        BluetoothManager.sharedInstance.messageCount += 1
        
      }
      return
    }
    
    
    ////////////////
    // JSON decoding
    /////////////////
    
    
    // see if we can find a separator in the buffered data
    let sepdata = Data(bytes: UnsafePointer<UInt8>([separator] as [UInt8]), count: 1)
    let rangedata = NSMakeRange(0, RxDataBuffer.length)
    let foundRange = RxDataBuffer.range(of: sepdata, options:[], in:rangedata)
    
    // data parsing variables
    let data_chunk : NSMutableData = NSMutableData()
    let data_left : NSMutableData = NSMutableData()
    
    // here we check to see if the separator exists, and therefore that we
    // have a complete message ready to be extracted
    if foundRange.location != NSNotFound {
      // extract the entire message from the rx data buffer
      data_chunk.append(RxDataBuffer.subdata(with: NSMakeRange(0,foundRange.location)))
      // if there is leftover data in the buffer, make sure to keep it otherwise
      // the parsing will not work for the next message that is partially complete now
      if RxDataBuffer.length-1 > foundRange.location {
        data_left.append(RxDataBuffer.subdata(with: NSMakeRange(foundRange.location+1,RxDataBuffer.length-foundRange.location-1)))
        RxDataBuffer = data_left
      } else {
        RxDataBuffer = NSMutableData()
      }
      // TODO: remove this, just for debug
      let str = String(data: data_chunk as Data,encoding: String.Encoding.utf8)
      if str != nil {
        //          vmlog(str!)
      } else {
        vmlog("not UTF8")
      }
      /////////////////////////////////////
    }
    
    // do the actual parsing if we've managed to extract a full message
    if data_chunk.length > 0 {

      self.jsonDecoding(data_chunk:data_chunk)
      
      // Keep a count of how many messages were received in total
      // since connection. Can be used by the client app.
      
       BluetoothManager.sharedInstance.messageCount += 1
    }

  }
  
 
}
