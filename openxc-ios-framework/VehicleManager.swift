//
//  VehicleManager.swift
//  openXCSwift
//
//  Created by Tim Buick on 2016-06-16.
//  Copyright © 2016 BugLabs. All rights reserved.
//

import Foundation
import CoreBluetooth


// public enum VehicleManagerStatusMessage
// values reported to managerCallback if defined
public enum VehicleManagerStatusMessage: Int {
  case C5DETECTED=1               // C5 VI was detected
  case C5CONNECTED=2              // C5 VI connection established
  case C5SERVICEFOUND=3           // C5 VI OpenXC service detected
  case C5NOTIFYON=4               // C5 VI notification enabled
  case C5DISCONNECTED=5           // C5 VI disconnected
  case TRACE_SOURCE_END=6         // configured trace input end of file reached
  case TRACE_SINK_WRITE_ERROR=7   // error in writing message to trace file
  case BLE_RX_DATA_PARSE_ERROR=8  // error in parsing data received from VI
}


// public enum VehicleManagerConnectionState
// values reported in public variable connectionState
public enum VehicleManagerConnectionState: Int {
  case NotConnected=0           // not connected to any C5 VI
  case ConnectionInProgress=1   // connection in progress (connecting/searching for services)
  case Connected=2              // connection established (but not ready to receive btle writes)
  case Operational=3            // C5 VI operational (notify enabled and writes accepted)
}





public class VehicleManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
  
  
  
  // MARK: Singleton Init
  
  // This signleton init allows mutiple controllers to access the same instantiation
  // of the VehicleManager. There is only a single instantiation of the VehicleManager
  // for the entire client app
  static public let sharedInstance: VehicleManager = {
    let instance = VehicleManager()
    return instance
  }()
  private override init() {
  }
  
  
  
  // MARK: Class Vars
  // -----------------
  
  // CoreBluetooth variables
  private var centralManager: CBCentralManager!
  private var openXCPeripheral: CBPeripheral!
  private var openXCService: CBService!
  private var openXCNotifyChar: CBCharacteristic!
  private var openXCWriteChar: CBCharacteristic!
  
  // config for outputting debug messages to console
  private var managerDebug : Bool = false
  
  // optional variable holding callback for VehicleManager status updates
  private var managerCallback: TargetAction?
  
  // data buffer for receiving raw BTLE data
  private var RxDataBuffer: NSMutableData! = NSMutableData()
  
  // data buffer for storing vehicle messages to send to BTLE
  private var BLETxDataBuffer: NSMutableArray! = NSMutableArray()
  // BTLE transmit semaphore variable
  private var BLETxWriteCount: Int = 0
  // BTLE transmit token increment variable
  private var BLETxSendToken: Int = 0
  
  // ordered list for storing callbacks for in progress vehicle commands
  private var BLETxCommandCallback = [TargetAction]()
  // mirrored ordered list for storing command token for in progress vehicle commands
  private var BLETxCommandToken = [String]()
  
  // dictionary for holding registered measurement message callbacks
  // pairing measurement String with callback action
  private var measurementCallbacks = [NSString:TargetAction]()
  // default callback action for measurement messages not registered above
  private var defaultMeasurementCallback : TargetAction?
  
  // dictionary for holding registered diagnostic message callbacks
  // pairing bus-id-mode(-pid) String with callback action
  private var diagCallbacks = [NSString:TargetAction]()
  // default callback action for diagnostic messages not registered above
  private var defaultDiagCallback : TargetAction?
  
  // dictionary for holding registered diagnostic message callbacks
  // pairing bus-id String with callback action
  private var canCallbacks = [NSString:TargetAction]()
  // default callback action for can messages not registered above
  private var defaultCanCallback : TargetAction?
  
  // config variable determining whether trace output is generated
  private var traceFilesinkEnabled: Bool = false
  // config variable holding trace output file name
  private var traceFilesinkName: NSString = ""
  
  // config variable determining whether trace input is used instead of BTLE data
  private var traceFilesourceEnabled: Bool = false
  // config variable holding trace input file name
  private var traceFilesourceName: NSString = ""
  // private timer for trace input message send rate
  private var traceFilesourceTimer: NSTimer = NSTimer()
  // private file handle to trace input file
  private var traceFilesourceHandle: NSFileHandle?
  
  
  // public variable holding VehicleManager connection state enum
  public var connectionState: VehicleManagerConnectionState! = .NotConnected
  // public variable holding number of messages received since last Connection established
  public var messageCount: Int = 0
  
  
  // dictionary holding last received measurement message for each measurement type
  private var latestVehicleMeasurements: NSMutableDictionary! = NSMutableDictionary()
  
  
  
  
  
  
  
  
  // MARK: Class Functions
  
  // set the callback for VM status updates
  public func setManagerCallbackTarget<T: AnyObject>(target: T, action: (T) -> (NSDictionary) -> ()) {
    managerCallback = TargetActionWrapper(key:"", target: target, action: action)
  }
  
  // change the debug config for the VM
  public func setManagerDebug(on:Bool) {
    managerDebug = on
  }
  
  // private debug log function gated by the debug setting
  private func vmlog(strings:Any...) {
    if managerDebug {
      let d = NSDate()
      let df = NSDateFormatter()
      df.dateFormat = "[H:m:ss.SSS]"
      print(df.stringFromDate(d),terminator:"")
      print(" ",terminator:"")
      for string in strings {
        print(string,terminator:"")
      }
      print("")
    }
  }
  
  
  // connect the VM to the VI
  public func connect() {
    
    // TODO: allow VI to be chosen from a list
    // instead of auto connecting to first VI
    
    // if the VM is already connected, don't do anything
    if connectionState != .NotConnected {
      vmlog("VehicleManager already connected! Sorry!")
      return
    }
    
    // run the core bluetooth framework on a separate thread from main thread
    let cbqueue: dispatch_queue_t = dispatch_queue_create("CBQ", DISPATCH_QUEUE_SERIAL)
    
    // start the connection process
    vmlog("VehicleManager connect started")
    connectionState = .ConnectionInProgress
    messageCount = 0
    openXCPeripheral=nil
    centralManager = CBCentralManager(delegate: self, queue: cbqueue, options:nil)
    
  }
  
  
  // tell the VM to enable output to trace file
  public func enableTraceFileSink(filename:NSString) -> Bool {
    
    // check that file sharing is enabled in the bundle
    if let fs : Bool? = NSBundle.mainBundle().infoDictionary?["UIFileSharingEnabled"] as? Bool {
      if fs == true {
        vmlog("file sharing ok!")
      } else {
        vmlog("file sharing false!")
        return false
      }
    } else {
      vmlog("no file sharing key!")
      return false
    }
    
    // save the trace file name
    traceFilesinkEnabled = true
    traceFilesinkName = filename
    
    // find the file, and overwrite it if it already exists
    if let dir = NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory.DocumentDirectory,
                                                     NSSearchPathDomainMask.AllDomainsMask, true).first {
      
      let path = NSURL(fileURLWithPath: dir).URLByAppendingPathComponent(traceFilesinkName as String).path!
      
      vmlog("checking for file")
      if NSFileManager.defaultManager().fileExistsAtPath(path) {
        vmlog("file detected")
        do {
          try NSFileManager.defaultManager().removeItemAtPath(path)
          vmlog("file deleted")
        } catch {
          vmlog("could not delete file")
          return false
        }
      } else {
        return false
      }
    } else {
      return false
    }
    
    
    
    return true
    
  }
  
  
  // turn off trace file output
  public func disableTraceFileSink() {
    
    traceFilesinkEnabled = false
    
  }
  
  
  
  // turn on trace file input instead of data from BTLE
  // specify a filename to read from, and a speed that lines
  // are read from the file in ms
  public func enableTraceFileSource(filename:NSString, speed:NSInteger=500) -> Bool {
    
    // only allow a reasonable range of values for speed, not too fast or slow
    if speed < 50 || speed > 1000 {return false}
    
    // check for file sharing in the bundle
    if let fs : Bool? = NSBundle.mainBundle().infoDictionary?["UIFileSharingEnabled"] as? Bool {
      if fs == true {
        vmlog("file sharing ok!")
      } else {
        vmlog("file sharing false!")
        return false
      }
    } else {
      vmlog("no file sharing key!")
      return false
    }
    
    
    // check that the file exists
    if let dir = NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory.DocumentDirectory,
                                                     NSSearchPathDomainMask.AllDomainsMask, true).first {
      
      let path = NSURL(fileURLWithPath: dir).URLByAppendingPathComponent(filename as String).path!
      
      vmlog("checking for file")
      if NSFileManager.defaultManager().fileExistsAtPath(path) {
        vmlog("file detected")
        
        // file exists, save file name for trace input
        traceFilesourceEnabled = true
        traceFilesourceName = filename
        
        // create a file handle for the trace input
        traceFilesourceHandle = NSFileHandle(forReadingAtPath:path)
        if traceFilesourceHandle == nil {
          vmlog("can't open filehandle")
          return false
        }
        
        // create a timer to handle reading from the trace input filehandle
        let spdf:Double = Double(speed) / 1000.0
        traceFilesourceTimer = NSTimer.scheduledTimerWithTimeInterval(spdf, target: self, selector: #selector(traceFileReader), userInfo: nil, repeats: true)
        
        return true
        
      }
    }
    
    return false
    
  }
  
  
  // turn off trace file input
  public func disableTraceFileSource() {
    
    traceFilesourceEnabled = false
  }
  
  
  
  // return the latest message received for a given measurement string name
  public func getLatest(key:NSString) -> VehicleMeasurementResponse {
    if let entry = latestVehicleMeasurements[key] {
      return entry as! VehicleMeasurementResponse
    }
    return VehicleMeasurementResponse()
  }
  
  
  // add a callback for a given measurement string name
  public func addMeasurementTarget<T: AnyObject>(key: NSString, target: T, action: (T) -> (NSDictionary) -> ()) {
    measurementCallbacks[key] = TargetActionWrapper(key:key, target: target, action: action)
  }
  
  // clear the callback for a given measurement string name
  public func clearMeasurementTarget(key: NSString) {
    measurementCallbacks.removeValueForKey(key)
  }
  
  // add a default callback for any measurement messages not include in specified callbacks
  public func setMeasurementDefaultTarget<T: AnyObject>(target: T, action: (T) -> (NSDictionary) -> ()) {
    defaultMeasurementCallback = TargetActionWrapper(key:"", target: target, action: action)
  }
  
  // clear default callback (by setting the default callback to a null method)
  public func clearMeasurementDefaultTarget() {
    defaultMeasurementCallback = TargetActionWrapper(key: "", target: VehicleManager.sharedInstance, action: VehicleManager.CallbackNull)
  }
  
  
  
  // send a command message with a callback for when the command response is received
  public func sendCommand<T: AnyObject>(cmd:VehicleCommandRequest, target: T, action: (T) -> (NSDictionary) -> ()) -> String {
    vmlog("in sendCommand:target")
    
    // if we have a trace input file, ignore this request!
    if (traceFilesourceEnabled) {return ""}
    
    // save the callback in order, so we know which to call when responses are received
    BLETxSendToken += 1
    let key : String = String(BLETxSendToken)
    let act : TargetAction = TargetActionWrapper(key:key, target: target, action: action)
    BLETxCommandCallback.append(act)
    BLETxCommandToken.append(key)
    
    // common command send method
    sendCommandCommon(cmd)
    
    return key
    
  }
  
  // send a command message with no callback specified
  public func sendCommand(cmd:VehicleCommandRequest) {
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
  
  
  
  // send a diagnostic message with a callback for when the diag command response is received
  public func sendDiagReq<T: AnyObject>(cmd:VehicleDiagnosticRequest, target: T, cmdaction: (T) -> (NSDictionary) -> ()) -> String {
    vmlog("in sendDiagReq:cmd")
    
    // if we have a trace input file, ignore this request!
    if (traceFilesourceEnabled) {return ""}
    
    // save the callback in order, so we know which to call when responses are received
    BLETxSendToken += 1
    let key : String = String(BLETxSendToken)
    let act : TargetAction = TargetActionWrapper(key:key, target: target, action: cmdaction)
    BLETxCommandCallback.append(act)
    BLETxCommandToken.append(key)
    
    // common diag send method
    sendDiagCommon(cmd)
    
    return key
    
  }
  
  // send a diagnostic message with no callback specified
  public func sendDiagReq(cmd:VehicleDiagnosticRequest) {
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
    sendDiagCommon(cmd)
    
  }
  
  
  // set a callback for any diagnostic messages received with a given set of keys.
  // The key is bus-id-mode-pid if there are 4 keys specified in the parameter.
  // The key becomes bus-id-mode-X if there are 3 keys specified, indicating that pid does not exist
  public func addDiagnosticTarget<T: AnyObject>(keys: [NSInteger], target: T, action: (T) -> (NSDictionary) -> ()) {
    let key : NSMutableString = ""
    var first : Bool = true
    for i in keys {
      if !first {
        key.appendString("-")
      }
      first=false
      key.appendString(String(i))
    }
    if keys.count == 3 {
      key.appendString("-X")
    }
    // key string has been created
    vmlog("add diag key=",key)
    // save the callback associated with the key
    diagCallbacks[key] = TargetActionWrapper(key:key, target: target, action: action)
  }
  
  // clear a callback for a given set of keys, defined as above.
  public func clearDiagnosticTarget(keys: [NSInteger]) {
    let key : NSMutableString = ""
    var first : Bool = true
    for i in keys {
      if !first {
        key.appendString("-")
      }
      first=false
      key.appendString(String(i))
    }
    if keys.count == 3 {
      key.appendString("-X")
    }
    // key string has been created
    vmlog("rm diag key=",key)
    // clear the callback associated with the key
    diagCallbacks.removeValueForKey(key)
  }
  
  // set a default callback for any diagnostic messages with a key set not specified above
  public func setDiagnosticDefaultTarget<T: AnyObject>(target: T, action: (T) -> (NSDictionary) -> ()) {
    defaultDiagCallback = TargetActionWrapper(key:"", target: target, action: action)
  }
  
  // clear the default diag callback
  public func clearDiagnosticDefaultTarget() {
    defaultDiagCallback = TargetActionWrapper(key: "", target: VehicleManager.sharedInstance, action: VehicleManager.CallbackNull)
  }
  
  
  
  
  
  // set a callback for any can messages received with a given set of keys.
  // The key is bus-id and 2 keys must be specified always
  public func addCanTarget<T: AnyObject>(keys: [NSInteger], target: T, action: (T) -> (NSDictionary) -> ()) {
    let key : NSMutableString = ""
    var first : Bool = true
    for i in keys {
      if !first {
        key.appendString("-")
      }
      first=false
      key.appendString(String(i))
    }
    // key string has been created
    vmlog("add can key=",key)
    // save the callback associated with the key
    diagCallbacks[key] = TargetActionWrapper(key:key, target: target, action: action)
  }
  
  // clear a callback for a given set of keys, defined as above.
  public func clearCanTarget(keys: [NSInteger]) {
    let key : NSMutableString = ""
    var first : Bool = true
    for i in keys {
      if !first {
        key.appendString("-")
      }
      first=false
      key.appendString(String(i))
    }
    // key string has been created
    vmlog("rm can key=",key)
    // clear the callback associated with the key
    diagCallbacks.removeValueForKey(key)
  }
  
  
  // set a default callback for any can messages with a key set not specified above
  public func setCanDefaultTarget<T: AnyObject>(target: T, action: (T) -> (NSDictionary) -> ()) {
    defaultCanCallback = TargetActionWrapper(key:"", target: target, action: action)
  }
  
  // clear the can diag callback
  public func clearCanDefaultTarget() {
    defaultCanCallback = TargetActionWrapper(key: "", target: VehicleManager.sharedInstance, action: VehicleManager.CallbackNull)
  }
  
  
  
  // send a can message   
  public func sendCanReq(cmd:VehicleCanRequest) {
    vmlog("in sendCanReq")
    
    // if we have a trace input file, ignore this request!
    if (traceFilesourceEnabled) {return}
    
    // common can send method
    sendCanCommon(cmd)
    
  }
  
  
  
  
  
  ////////////////
  // private functions
  
  
  private func sendCommandCommon(cmd:VehicleCommandRequest) {
    vmlog("in sendCommandCommon")
    
    if (cmd.command == .version || cmd.command == .device_id) {
      let cmd = "{\"command\":\"\(cmd.command.rawValue)\"}\0"
      BLETxDataBuffer.addObject(cmd.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)!)
    }
    
    BLESendFunction()
    
  }
  
  
  private func sendDiagCommon(cmd:VehicleDiagnosticRequest) {
    vmlog("in sendDiagCommon")
    
    let cmdjson : NSMutableString = ""
    cmdjson.appendString("{\"command\":\"diagnostic_request\",\"action\":\"add\",\"request\":{\"bus\":\(cmd.bus),\"id\":\(cmd.message_id),\"mode\":\(cmd.mode)")
    if cmd.pid != nil {
      cmdjson.appendString(",\"pid\":\(cmd.pid!)")
    }
    cmdjson.appendString("}}\0")
    
    // TODO: what about recurring diagnostic messages
    
    vmlog("sending diag cmd:",cmdjson)
    
    BLETxDataBuffer.addObject(cmdjson.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)!)
    
    BLESendFunction()
    
  }
  
  
  private func sendCanCommon(cmd:VehicleCanRequest) {
    vmlog("in sendCanCommon")
    
    let cmd = "{\"bus\":\(cmd.bus),\"id\":\(cmd.id),\"data\":\"\(cmd.data)\"}"
    BLETxDataBuffer.addObject(cmd.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)!)
    
    
    BLESendFunction()
    
  }
  
  
  
  private func CallbackNull(o:AnyObject) {
    //    vmlog("in CallbackNull")
  }
  
  
  private func BLESendFunction() {
    
    
    var sendBytes: NSData
    
//    vmlog("BLEsf: TxDataBuffer count = \(BLETxDataBuffer.count)")
    if BLETxDataBuffer.count == 0 {
//      vmlog("BLEsf: exit")
      return
    }
    
//    vmlog("BLEsf: b4 TxDataWriteCount count = \(BLETxWriteCount)")
    if BLETxWriteCount != 0 {
//      vmlog("BLEsf: exit")
      return
    }
    
    var cmdToSend : NSMutableData = BLETxDataBuffer[0] as! NSMutableData
    
    let rangedata = NSMakeRange(0, 20)
    while cmdToSend.length > 0 {
      if (cmdToSend.length<=20) {
        sendBytes = cmdToSend
        cmdToSend = NSMutableData()
      } else {
        sendBytes = cmdToSend.subdataWithRange(rangedata)
        
        let leftdata = NSMakeRange(20,cmdToSend.length-20)
        cmdToSend = NSMutableData(data: cmdToSend.subdataWithRange(leftdata))
      }
      openXCPeripheral.writeValue(sendBytes, forCharacteristic: openXCWriteChar, type: CBCharacteristicWriteType.WithResponse)
      BLETxWriteCount += 1
//      vmlog("BLEsf: ",String(data: sendBytes,encoding: NSUTF8StringEncoding))
    }
    
    BLETxDataBuffer.removeObjectAtIndex(0)

//    vmlog("BLEsf: af TxDataWriteCount count = \(BLETxWriteCount)")
//    vmlog("BLEsf: exit")
    
    
  }
  
  
  
  
  private func RxDataParser(separator:UInt8) {
    
    
    // JSON decoding
    // TODO: if protbuf?
    ////////////////
    
    let sepdata = NSData(bytes: [separator] as [UInt8], length: 1)
    let rangedata = NSMakeRange(0, RxDataBuffer.length)
    let foundRange = RxDataBuffer.rangeOfData(sepdata, options:[], range:rangedata)
    
    let data_chunk : NSMutableData = NSMutableData()
    let data_left : NSMutableData = NSMutableData()
    
    if foundRange.location != NSNotFound {
      data_chunk.appendData(RxDataBuffer.subdataWithRange(NSMakeRange(0,foundRange.location)))
      /*
       vmlog("buff",BLEDataBuffer)
       vmlog("chunk",data_chunk)
       vmlog("buf len:",BLEDataBuffer.length)
       vmlog("foundRange loc:",foundRange.location," len:",foundRange.length)
       let start = foundRange.location+1
       let len = BLEDataBuffer.length-foundRange.location
       vmlog("start:",start," len:",len)
       */
      if RxDataBuffer.length-1 > foundRange.location {
        data_left.appendData(RxDataBuffer.subdataWithRange(NSMakeRange(foundRange.location+1,RxDataBuffer.length-foundRange.location-1)))
        RxDataBuffer = data_left
      } else {
        RxDataBuffer = NSMutableData()
      }
      let str = String(data: data_chunk,encoding: NSUTF8StringEncoding)
      if str != nil {
  //             vmlog(str!)
      } else {
        vmlog("not UTF8")
      }
    }
    
    
    if data_chunk.length > 0 {
      do {
        let json = try NSJSONSerialization.JSONObjectWithData(data_chunk, options: .MutableContainers)
        let str = String(data: data_chunk,encoding: NSUTF8StringEncoding)
        
        
        var timestamp : NSInteger = 0
        if json["timestamp"] != nil {
          timestamp = json["timestamp"] as! NSInteger
        }
        
        
        
        // evented measurement rsp
        ///////////////////
        if let event = json["event"] as? NSString {
          let name = json["name"] as! NSString
          let value : AnyObject = json["value"] ?? NSNull()
          
          let rsp : VehicleMeasurementResponse = VehicleMeasurementResponse()
          rsp.timestamp = timestamp
          rsp.name = name
          rsp.value = value
          rsp.isEvented = true
          rsp.event = event
          
          var found=false
          for key in measurementCallbacks.keys {
            let act = measurementCallbacks[key]
            if act!.returnKey() == name {
              found=true
              act!.performAction(["vehiclemessage":rsp] as NSDictionary)
            }
          }
          if !found {
            if let act = defaultMeasurementCallback {
              act.performAction(["vehiclemessage":rsp] as NSDictionary)
            }
          }
        }
          ///////////////////////
          
          
          
          // measurement rsp
          ///////////////////
        else if let name = json["name"] as? NSString {
          let value : AnyObject = json["value"] ?? NSNull()
          
          let rsp : VehicleMeasurementResponse = VehicleMeasurementResponse()
          rsp.value = value
          rsp.timestamp = timestamp
          rsp.name = name
          
          // neat way to test for type of AnyObject
          /*
           if value is NSNumber {
           let nv = value as! NSNumber
           if nv.isEqualToValue(NSNumber(bool: true)) {
           vmlog("it's a bool and it's true")
           } else if nv.isEqualToValue(NSNumber(bool:false)) {
           vmlog("it's a bool and it's false")
           } else {
           vmlog("it's a number")
           }
           } else {
           vmlog("it's a string")
           }
           */
          
          
          latestVehicleMeasurements.setValue(rsp, forKey:name as String)
          
          var found=false
          for key in measurementCallbacks.keys {
            let act = measurementCallbacks[key]
            if act!.returnKey() == name {
              found=true
              act!.performAction(["vehiclemessage":rsp] as NSDictionary)
            }
          }
          if !found {
            if let act = defaultMeasurementCallback {
              act.performAction(["vehiclemessage":rsp] as NSDictionary)
            }
          }
        }
          ///////////////////////
          
          
          
          // command rsp
          ///////////////////
        else if let cmd_rsp = json["command_response"] as? NSString {
          
          var message : NSString = ""
          if let messageX = json["message"] as? NSString {
            message = messageX
          }
          
          var status : Bool = false
          if let statusX = json["status"] as? Bool {
            status = statusX
          }
          
          let rsp : VehicleCommandResponse = VehicleCommandResponse()
          rsp.timestamp = timestamp
          rsp.message = message
          rsp.command_response = cmd_rsp
          rsp.status = status
          
          if BLETxCommandCallback.count > 0 {
            let ta : TargetAction = BLETxCommandCallback.removeFirst()
            let s : String = BLETxCommandToken.removeFirst()
            ta.performAction(["vehiclemessage":rsp,"key":s] as NSDictionary)
          }
          
        }
          //////////////////////////
          
          
          
          
          
          // diag rsp or CAN message
          ///////////////////
        else if let id = json["id"] as? NSInteger {
          
          if let success = json["success"] as? Bool {
            // diag rsp
            
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
            }
            var value : NSInteger?
            if let valueX = json["value"] as? NSInteger {
              value = valueX
            }
            
            let rsp : VehicleDiagnosticResponse = VehicleDiagnosticResponse()
            rsp.timestamp = timestamp
            rsp.bus = bus
            rsp.message_id = id
            rsp.mode = mode
            rsp.pid = pid
            rsp.success = success
            rsp.payload = payload
            rsp.value = value
            
            let tupple : NSMutableString = ""
            tupple.appendString("\(String(bus))-\(String(id))-\(String(mode))-")
            if pid != nil {
              tupple.appendString(String(pid))
            } else {
              tupple.appendString("X")
            }

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
            
            var found=false
            for key in diagCallbacks.keys {
              let act = diagCallbacks[key]
              if act!.returnKey() == tupple {
                found=true
                act!.performAction(["vehiclemessage":rsp] as NSDictionary)
              }
            }
            if !found {
              if let act = defaultDiagCallback {
                act.performAction(["vehiclemessage":rsp] as NSDictionary)
              }
            }
            
            
            
            
          } else if let data = json["data"] as? NSString {
            // CAN msg
            
            var bus : NSInteger = 0
            if let busX = json["bus"] as? NSInteger {
              bus = busX
            }
            
            let rsp : VehicleCanResponse = VehicleCanResponse()
            rsp.timestamp = timestamp
            rsp.bus = bus
            rsp.id = id
            rsp.data = data
            
            vmlog("CAN bus:\(bus) status:\(id) payload:\(data)")
            
            
            let tupple = "\(String(bus))-\(String(id))"
            
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
            
          } else {
            // can't really get here!
            
          }
          
          
          
        } else {
          // what the heck is it??
          
        }
        
        
        
        ///////
        //// fake out a CAN msg on every msg received (for debug)!!
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
        
        
        
        if traceFilesinkEnabled {
          traceFileWriter(str!)
        }
        
        
        messageCount += 1
        
        
        
        
      } catch {
        vmlog("bad json")
        if let act = managerCallback {
          act.performAction(["status":VehicleManagerStatusMessage.BLE_RX_DATA_PARSE_ERROR.rawValue] as Dictionary)
        }
      }
      
      
    }
    
  }
  
  
  
  private func traceFileWriter (message:VehicleBaseMessage) {
    
    // TODO: if we want to be able to trace directly from a vehicleMessage,
    // this is where to do it
    // Each class of vehicle message has it's own trace output method
    vmlog(message.traceOutput())
    
  }
  
  private func traceFileWriter (string:String) {
    
    // this version of the method outputs a direct string
    // make sure there are no LFCR in the string, because they're added here automatically
    vmlog("trace:",string)
    
    var traceOut = string
    
    traceOut.appendContentsOf("\n");
    
    if let dir = NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory.DocumentDirectory,
                                                     NSSearchPathDomainMask.AllDomainsMask, true).first {
      let path = NSURL(fileURLWithPath: dir).URLByAppendingPathComponent(traceFilesinkName as String)
      
      //writing
      do {
        let data = traceOut.dataUsingEncoding(NSUTF8StringEncoding)!
        if let fileHandle = try? NSFileHandle(forWritingToURL: path) {
          defer {
            fileHandle.closeFile()
          }
          fileHandle.seekToEndOfFile()
          fileHandle.writeData(data)
        }
        else {
          try data.writeToURL(path, options: .DataWritingAtomic)
        }
      }
      catch {
        if let act = managerCallback {
          act.performAction(["status":VehicleManagerStatusMessage.TRACE_SINK_WRITE_ERROR.rawValue] as Dictionary)
        }
      }
      
    }
    
    
  }
  
  
  private dynamic func traceFileReader () {
    
    //    vmlog("in traceFileReader")
    
    if traceFilesourceEnabled && traceFilesourceHandle != nil {
      let rdData = traceFilesourceHandle!.readDataOfLength(20)
      
      
      if rdData.length > 0 {
        //        vmlog("rdData:",rdData)
        RxDataBuffer.appendData(rdData)
      } else {
        vmlog("traceFilesource EOF")
        traceFilesourceHandle!.closeFile()
        traceFilesourceHandle = nil
        if let act = managerCallback {
          act.performAction(["status":VehicleManagerStatusMessage.TRACE_SOURCE_END.rawValue] as Dictionary)
        }
      }
      
      RxDataParser(0x0a)
      
      
      
    }
    
    
  }
  
  
  
  
  
  
  // MARK: Core Bluetooth Manager
  
  public func centralManagerDidUpdateState(central: CBCentralManager) {
    vmlog("in centralManagerDidUpdateState:")
    if central.state == .PoweredOff {
      vmlog(" PoweredOff")
    } else if central.state == .PoweredOn {
      vmlog(" PoweredOn")
    } else {
      vmlog(" Other")
    }
    
    if central.state == CBCentralManagerState.PoweredOn && connectionState == .ConnectionInProgress {
      centralManager.scanForPeripheralsWithServices(nil, options: nil)
    }
    
    
  }
  
  
  public func centralManager(central: CBCentralManager, didDiscoverPeripheral peripheral: CBPeripheral, advertisementData: [String : AnyObject], RSSI: NSNumber) {
    vmlog("in centralManager:didDiscover")
    
    if openXCPeripheral == nil {
      vmlog("FOUND:")
      vmlog(peripheral.name)
      vmlog(advertisementData["kCBAdvDataLocalName"])
      // TODO: look at advData, or just either possible name, confirm with Ford
      if peripheral.name==OpenXCConstants.C5_VI_NAME || peripheral.name==OpenXCConstants.C5_VI_NAME_ALT {
        openXCPeripheral = peripheral
        openXCPeripheral.delegate = self
        centralManager.connectPeripheral(openXCPeripheral, options:nil)
        if let act = managerCallback {
          act.performAction(["status":VehicleManagerStatusMessage.C5DETECTED.rawValue] as NSDictionary)
        }
      }
      
    }
  }
  
  public func centralManager(central: CBCentralManager, didConnectPeripheral peripheral: CBPeripheral) {
    vmlog("in centralManager:didConnectPeripheral:")
    vmlog(peripheral.name!)
    connectionState = .Connected
    peripheral.discoverServices(nil)
    if let act = managerCallback {
      act.performAction(["status":VehicleManagerStatusMessage.C5CONNECTED.rawValue] as NSDictionary)
    }
  }
  
  
  public func centralManager(central: CBCentralManager, didFailToConnectPeripheral peripheral: CBPeripheral, error: NSError?) {
    vmlog("in centralManager:didFailToConnectPeripheral:")
    vmlog(peripheral.name!)
  }
  
  
  public func centralManager(central: CBCentralManager, willRestoreState dict: [String : AnyObject]) {
    vmlog("in centralManager:willRestoreState")
  }
  
  
  public func centralManager(central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: NSError?) {
    vmlog("in centralManager:didDisconnectPeripheral:")
    vmlog(peripheral.name!)
    vmlog(error)
    
    // just reconnect for now
    // TODO: allow configuration of auto-reconnect?
    if peripheral.name==OpenXCConstants.C5_VI_NAME {
      centralManager.connectPeripheral(openXCPeripheral, options:nil)
    }
    if peripheral.name==OpenXCConstants.C5_VI_NAME_ALT {
      centralManager.connectPeripheral(openXCPeripheral, options:nil)
    }
    if let act = managerCallback {
      act.performAction(["status":VehicleManagerStatusMessage.C5DISCONNECTED.rawValue] as NSDictionary)
    }
    connectionState = .ConnectionInProgress
    
  }
  
  
  
  // MARK: Peripheral Delgate Function
  
  public func peripheral(peripheral: CBPeripheral, didDiscoverServices error: NSError?) {
    vmlog("in peripheral:didDiscoverServices")
    if peripheral != openXCPeripheral {
      vmlog("peripheral error!")
      return
    }
    
    for service in peripheral.services! {
      vmlog(" - Found service : ",service.UUID)
      
      if service.UUID.UUIDString == OpenXCConstants.C5_OPENXC_BLE_SERVICE_UUID {
        vmlog("   OPENXC_MAIN_SERVICE DETECTED")
        openXCService = service
        openXCPeripheral.discoverCharacteristics(nil, forService:service)
        if let act = managerCallback {
          act.performAction(["status":VehicleManagerStatusMessage.C5SERVICEFOUND.rawValue] as NSDictionary)
        }
      }
      
    }
  }
  
  
  public func peripheral(peripheral: CBPeripheral, didDiscoverCharacteristicsForService service: CBService, error: NSError?) {
    vmlog("in peripheral:didDiscoverCharacteristicsForService")
    if peripheral != openXCPeripheral {
      vmlog("peripheral error!")
      return
    }
    if service != openXCService {
      vmlog("service error!")
      return
    }
    
    for characteristic in service.characteristics! {
      vmlog(" - Found characteristic : ",characteristic.UUID)
      if characteristic.UUID.UUIDString == OpenXCConstants.C5_OPENXC_BLE_CHARACTERISTIC_NOTIFY_UUID {
        openXCNotifyChar = characteristic
        peripheral.setNotifyValue(true, forCharacteristic:characteristic)
        openXCPeripheral.discoverDescriptorsForCharacteristic(characteristic)
        if let act = managerCallback {
          act.performAction(["status":VehicleManagerStatusMessage.C5NOTIFYON.rawValue] as NSDictionary)
        }
        connectionState = .Operational
      }
      if characteristic.UUID.UUIDString == OpenXCConstants.C5_OPENXC_BLE_CHARACTERISTIC_WRITE_UUID {
        openXCWriteChar = characteristic
        openXCPeripheral.discoverDescriptorsForCharacteristic(characteristic)
      }
    }
    
  }
  
  
  public func peripheral(peripheral: CBPeripheral, didUpdateValueForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
    // vmlog("in peripheral:didUpdateValueForCharacteristic")
    
    if traceFilesourceEnabled {return}
    
    let data = characteristic.value!
    
    if data.length > 0 {
      RxDataBuffer.appendData(data)
    }
    
    RxDataParser(0x00)
    
    
  }
  
  
  public func peripheral(peripheral: CBPeripheral, didDiscoverDescriptorsForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
    vmlog("in peripheral:didDiscoverDescriptorsForCharacteristic")
    vmlog(characteristic.descriptors)
  }
  
  
  public func peripheral(peripheral: CBPeripheral, didUpdateValueForDescriptor descriptor: CBDescriptor, error: NSError?) {
    vmlog("in peripheral:didUpdateValueForDescriptor")
  }
  
  
  public func peripheral(peripheral: CBPeripheral, didUpdateNotificationStateForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
    vmlog("in peripheral:didUpdateNotificationStateForCharacteristic")
  }
  
  
  public func peripheral(peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
    vmlog("in peripheral:didModifyServices")
  }
  
  
  public func peripheral(peripheral: CBPeripheral, didDiscoverIncludedServicesForService service: CBService, error: NSError?) {
    vmlog("in peripheral:didDiscoverIncludedServicesForService")
  }
  
  
  public func peripheral(peripheral: CBPeripheral, didWriteValueForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
    vmlog("in peripheral:didWriteValueForCharacteristic")
    if error != nil {
      vmlog("error")
      vmlog(error!.localizedDescription)
    } else {

    }
    NSThread.sleepForTimeInterval(0.05)
    //vmlog("pdwv: b4 BLETxWriteCount = \(BLETxWriteCount)")
    BLETxWriteCount -= 1
    BLESendFunction()
    //vmlog("pdwv: af BLETxWriteCount = \(BLETxWriteCount)")
    //vmlog("pdwv: exit")
  }
  
  
  public func peripheral(peripheral: CBPeripheral, didWriteValueForDescriptor descriptor: CBDescriptor, error: NSError?) {
    vmlog("in peripheral:didWriteValueForDescriptor")
  }
  
  
  public func peripheral(peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: NSError?) {
    vmlog("in peripheral:didReadRSSI")
  }
  
  
  
  
  
}
