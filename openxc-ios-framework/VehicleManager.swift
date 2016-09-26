//
//  VehicleManager.swift
//  openXCSwift
//
//  Created by Tim Buick on 2016-06-16.
//  Copyright (c) 2016 Ford Motor Company Licensed under the BSD license.
//  Version 0.9.2
//

import Foundation
import CoreBluetooth
import ProtocolBuffers



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
// This enum is outside of the main class for ease of use in the client app. It allows
// for referencing the enum without the class hierarchy in front of it. Ie. the enums
// can be accessed directly as .C5DETECTED for example


// public enum VehicleManagerConnectionState
// values reported in public variable connectionState
public enum VehicleManagerConnectionState: Int {
  case NotConnected=0           // not connected to any C5 VI
  case Scanning=1               // VM is allocation and scanning for nearby VIs
  case ConnectionInProgress=2   // connection in progress (connecting/searching for services)
  case Connected=3              // connection established (but not ready to receive btle writes)
  case Operational=4            // C5 VI operational (notify enabled and writes accepted)
}
// This enum is outside of the main class for ease of use in the client app. It allows
// for referencing the enum without the class hierarchy in front of it. Ie. the enums
// can be accessed directly as .C5DETECTED for example





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
  
  // dictionary of discovered openXC peripherals when scanning
  private var foundOpenXCPeripherals: [String:CBPeripheral] = [String:CBPeripheral]()
  
  // config for auto connecting to first discovered VI
  private var autoConnectPeripheral : Bool = true
  
  // config for outputting debug messages to console
  private var managerDebug : Bool = false
  
  // config for protobuf vs json BLE mode, defaults to JSON
  // TODO default to JSON
  private var jsonMode : Bool = false
  
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
  // 'default' command callback. If this is defined, it takes priority over any other callback
  // defined above
  private var defaultCommandCallback : TargetAction?

  
  // dictionary for holding registered measurement message callbacks
  // pairing measurement String with callback action
  private var measurementCallbacks = [NSString:TargetAction]()
  // default callback action for measurement messages not registered above
  private var defaultMeasurementCallback : TargetAction?
  // dictionary holding last received measurement message for each measurement type
  private var latestVehicleMeasurements: NSMutableDictionary! = NSMutableDictionary()
  
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
  // private variable holding timestamp of last message received
  private var traceFilesourceLastTime: NSInteger = 0
  
  
  // public variable holding VehicleManager connection state enum
  public var connectionState: VehicleManagerConnectionState! = .NotConnected
  // public variable holding number of messages received since last Connection established
  public var messageCount: Int = 0
  
  
  
  
  
  
  
  
  
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

  
  // change the auto connect config for the VM
  public func setAutoconnect(on:Bool) {
    autoConnectPeripheral = on
  }
  
  
  // return array of discovered peripherals
  public func discoveredVI() -> [String] {
    return Array(foundOpenXCPeripherals.keys)
  }
  
  
  // initialize the VM and scan for nearby VIs
  public func scan() {
    
    // if the VM is already connected, don't do anything
    if connectionState != .NotConnected {
      vmlog("VehicleManager already scanning or connected! Sorry!")
      return
    }

    // run the core bluetooth framework on a separate thread from main thread
    let cbqueue: dispatch_queue_t = dispatch_queue_create("CBQ", DISPATCH_QUEUE_SERIAL)

    // initialize the BLE manager process
    vmlog("VehicleManager scan started")
    connectionState = .Scanning
    messageCount = 0
    openXCPeripheral=nil
    centralManager = CBCentralManager(delegate: self, queue: cbqueue, options:nil)

  }
  
  
  // connect the VM to the first VI found
  public func connect() {
    
    // if the VM is not scanning, don't do anything
    if connectionState != .Scanning {
      vmlog("VehicleManager be scanning before a connect can occur!")
      return
    }
    
    // if the found VI list is empty, just return
    if foundOpenXCPeripherals.count == 0 {
      vmlog("VehicleManager has not found any VIs!")
      return
    }
    
    // for this method, just connect to first one found
    openXCPeripheral = foundOpenXCPeripherals.first?.1
    openXCPeripheral.delegate = self

    // start the connection process
    vmlog("VehicleManager connect started")
    centralManager.connectPeripheral(openXCPeripheral, options:nil)
    connectionState = .ConnectionInProgress
    
  }
  
  
  // connect the VM to a specific VI
  public func connect(name:String) {
    
    // if the VM is not scanning, don't do anything
    if connectionState != .Scanning {
      vmlog("VehicleManager be scanning before a connect can occur!")
      return
    }
    
    // if the found VI list is empty, just return
    if foundOpenXCPeripherals[name] == nil {
      vmlog("VehicleManager has not found this peripheral!")
      return
    }
    
    // for this method, just connect to first one found
    openXCPeripheral = foundOpenXCPeripherals[name]
    openXCPeripheral.delegate = self
    
    // start the connection process
    vmlog("VehicleManager connect started")
    centralManager.connectPeripheral(openXCPeripheral, options:nil)
    connectionState = .ConnectionInProgress
    
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
    
    // append date to filename
    let d = NSDate()
    let df = NSDateFormatter()
    df.dateFormat = "MMMd,yyyy-H:m:ss"
    let datedFilename = (filename as String) + "-" + df.stringFromDate(d)
    traceFilesinkName = datedFilename
    
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
  public func enableTraceFileSource(filename:NSString, speed:NSInteger?=nil) -> Bool {
    
    // only allow a reasonable range of values for speed, not too fast or slow
    if speed != nil {
      if speed < 50 || speed > 1000 {return false}
    }
    
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
        // if speed parameter exists
        if speed != nil {
          let spdf:Double = Double(speed!) / 1000.0
          traceFilesourceTimer = NSTimer.scheduledTimerWithTimeInterval(spdf, target: self, selector: #selector(traceFileReaderAuto), userInfo: nil, repeats: true)
        } else {
          traceFilesourceLastTime = 0
          traceFilesourceTimer = NSTimer.scheduledTimerWithTimeInterval(50, target: self, selector: #selector(traceFileReader), userInfo: nil, repeats: false)
        }
        
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
  
  
  // add a default callback for any measurement messages not include in specified callbacks
  public func setCommandDefaultTarget<T: AnyObject>(target: T, action: (T) -> (NSDictionary) -> ()) {
    defaultCommandCallback = TargetActionWrapper(key:"", target: target, action: action)
  }
  
  // clear default callback (by setting the default callback to a null method)
  public func clearCommandDefaultTarget() {
    defaultCommandCallback = nil
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
  
  
  // common function for sending a VehicleCommandRequest
  private func sendCommandCommon(cmd:VehicleCommandRequest) {
    vmlog("in sendCommandCommon")

    if !jsonMode {
      // in protobuf mode
      let cbuild = ControlCommand.Builder()
      if cmd.command == .version {cbuild.setTypes(.Version)}
      if cmd.command == .device_id {cbuild.setTypes(.DeviceId)}
      let mbuild = VehicleMessage.Builder()
      mbuild.setTypes(.ControlCommand)

      do {
        let cmsg = try cbuild.build()
        mbuild.setControlCommand(cmsg)
        let mmsg = try mbuild.build()
        print (mmsg)
        
        
        let cdata = mmsg.data()
        let cdata2 = NSMutableData()
        let prepend : [UInt8] = [UInt8(cdata.length)]
        cdata2.appendData(NSData(bytes: prepend, length:1))
        cdata2.appendData(cdata)
        print(cdata2)
        
        // append to tx buffer
        BLETxDataBuffer.addObject(cdata2)
        
        // trigger a BLE data send
        BLESendFunction()

      } catch {
        print("cmd msg build failed")
      }
      
      return
    }
    
    var cmdstr = ""
    // decode the command type and build the command depending on the command
    if cmd.command == .version || cmd.command == .device_id || cmd.command == .sd_mount_status {
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
      cmdstr = "{\"command\":\"\(cmd.command.rawValue)\",\"unix_time\":\"\(cmd.unix_time)\"}\0"
    } else {
      // unknown command!
      return
    }
    
    // append to tx buffer
    BLETxDataBuffer.addObject(cmdstr.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)!)
    
    // trigger a BLE data send
    BLESendFunction()
    
  }
  
  
  // common function for sending a VehicleDiagnosticRequest
  private func sendDiagCommon(cmd:VehicleDiagnosticRequest) {
    vmlog("in sendDiagCommon")
    
    // build the command json
    let cmdjson : NSMutableString = ""
    cmdjson.appendString("{\"command\":\"diagnostic_request\",\"action\":\"add\",\"request\":{\"bus\":\(cmd.bus),\"id\":\(cmd.message_id),\"mode\":\(cmd.mode)")
    if cmd.pid != nil {
      cmdjson.appendString(",\"pid\":\(cmd.pid!)")
    }
    if cmd.frequency > 0 {
      cmdjson.appendString(",\"frequency\":\(cmd.frequency)")
    }
    cmdjson.appendString("}}\0")
    
    
    vmlog("sending diag cmd:",cmdjson)
    // append to tx buffer
    BLETxDataBuffer.addObject(cmdjson.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)!)
    
    // trigger a BLE data send
    BLESendFunction()
    
  }
  
  
  // common function for sending a VehicleCanRequest
  private func sendCanCommon(cmd:VehicleCanRequest) {
    vmlog("in sendCanCommon")
    
    // build the command json
    let cmd = "{\"bus\":\(cmd.bus),\"id\":\(cmd.id),\"data\":\"\(cmd.data)\"}"
    // append to tx buffer
    BLETxDataBuffer.addObject(cmd.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)!)
    
    // trigger a BLE data send
    BLESendFunction()
    
  }
  
  
  // internal method used when a callback needs to be registered, but we don't
  // want it to actually do anything, for example a command request where we don't
  // want a callback for the command response. The command response is still received
  // but the callback registered comes here, and does nothing.
  private func CallbackNull(o:AnyObject) {
    vmlog("in CallbackNull")
  }
  
  
  // common function called whenever any messages need to be sent over BLE
  private func BLESendFunction() {
    
    
    var sendBytes: NSData
    
    // Check to see if the tx buffer is actually empty.
    // We need to do this because this function can be called as BLE notifications are
    // received because we may have queued up some messages to send.
    if BLETxDataBuffer.count == 0 {
      return
    }
    
    // Check to see if the tx write semaphore is >0.
    // This indicates that the last message are still being sent.
    // As the parts of the messsage are being queued up in CoreBluetooth 
    // (20B at a time), the tx write semaphore is incremented.
    // As the parts of the message are actually sent (20B at a time) and
    // acknowledged the tx write semaphore is decremented.
    // We can only start to send a new message when the semaphore is empty (=0).
    if BLETxWriteCount != 0 {
      return
    }
    
    // take the message to send from the head of the tx buffer queue
    var cmdToSend : NSMutableData = BLETxDataBuffer[0] as! NSMutableData
    
    // we can only send 20B at a time in BLE
    let rangedata = NSMakeRange(0, 20)
    // loop through and send 20B at a time, make sure to handle <20B in the last send.
    while cmdToSend.length > 0 {
      if (cmdToSend.length<=20) {
        sendBytes = cmdToSend
        cmdToSend = NSMutableData()
      } else {
        sendBytes = cmdToSend.subdataWithRange(rangedata)
        let leftdata = NSMakeRange(20,cmdToSend.length-20)
        cmdToSend = NSMutableData(data: cmdToSend.subdataWithRange(leftdata))
      }
      // write the byte chunk to the VI
      openXCPeripheral.writeValue(sendBytes, forCharacteristic: openXCWriteChar, type: CBCharacteristicWriteType.WithResponse)
      // increment the tx write semaphore
      BLETxWriteCount += 1
    }

    // remove the message from the tx buffer queue once all parts of it have been sent
    BLETxDataBuffer.removeObjectAtIndex(0)
    
  }
  
  
  
  // Common function for parsing any received data into openXC messages.
  // The separator parameter allows data to be parsed when each message is
  // separated by different things, for example messages are separated by \0
  // when coming via BLE, and separated by 0xa when coming via a trace file
  // RXDataParser returns the timestamp of the parsed message out of convenience.
  private func RxDataParser(separator:UInt8) -> NSInteger {
    
    // JSON decoding
    
    
    // TODO: protobuf support will be added later
    ////////////////
    
    if !jsonMode && RxDataBuffer.length > 0 {
      var packetlenbyte:UInt8 = 0
      RxDataBuffer.getBytes(&packetlenbyte, length:sizeof(UInt8))
      let packetlen = Int(packetlenbyte)
      
      if RxDataBuffer.length > packetlen+1 {
        vmlog("found \(packetlen)B protobuf frame")

//        var bytes = [UInt8](count: RxDataBuffer.length, repeatedValue: 0)
//        RxDataBuffer.getBytes(&bytes, length:RxDataBuffer.length * sizeof(UInt8))
//        vmlog(bytes)

        let data_chunk : NSMutableData = NSMutableData()
        data_chunk.appendData(RxDataBuffer.subdataWithRange(NSMakeRange(1,packetlen)))

        vmlog(data_chunk)
        
        var msg : VehicleMessage
        do {
          msg = try VehicleMessage.parseFromData(data_chunk)
          print(msg)
        } catch {
          print("protobuf parse error")
          return 0
        }
        
        let data_left : NSMutableData = NSMutableData()
        data_left.appendData(RxDataBuffer.subdataWithRange(NSMakeRange(packetlen+1, RxDataBuffer.length-packetlen-1)))
        RxDataBuffer = data_left

        
        
        // measurement messages (normal and evented)
        ///////////////////////////////////////////
        if msg.types == .Simple {
          
          let name = msg.simpleMessage.name
          
          // build measurement message
          let rsp : VehicleMeasurementResponse = VehicleMeasurementResponse()
          rsp.timestamp = Int(truncatingBitPattern:msg.timestamp)
          rsp.name = msg.simpleMessage.name
          if msg.simpleMessage.value.hasStringValue {rsp.value = msg.simpleMessage.value.stringValue}
          if msg.simpleMessage.value.hasBooleanValue {rsp.value = msg.simpleMessage.value.booleanValue}
          if msg.simpleMessage.value.hasNumericValue {rsp.value = msg.simpleMessage.value.numericValue}
          if msg.simpleMessage.hasEvent {
            rsp.isEvented = true
            if msg.simpleMessage.event.hasStringValue {rsp.value = msg.simpleMessage.event.stringValue}
            if msg.simpleMessage.event.hasBooleanValue {rsp.value = msg.simpleMessage.event.booleanValue}
            if msg.simpleMessage.event.hasNumericValue {rsp.value = msg.simpleMessage.event.numericValue}
          }
          
          // capture this message into the dictionary of latest messages
          latestVehicleMeasurements.setValue(rsp, forKey:name as String)
          
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
        
        
        // Command Response messages
        /////////////////////////////
        if msg.types == .CommandResponse {
          
          let name = msg.commandResponse.types.toString()
          
          
          // build command response message
          let rsp : VehicleCommandResponse = VehicleCommandResponse()
          rsp.timestamp = Int(truncatingBitPattern:msg.timestamp)
          rsp.command_response = name.lowercaseString
          rsp.message = msg.commandResponse.message_
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
 
        
        
        
        // Keep a count of how many messages were received in total
        // since connection. Can be used by the client app.
        messageCount += 1
        

        
      }

      return 0

    }
    
    
    
    

    // init timestamp to 0
    var timestamp : NSInteger = 0

    // see if we can find a separator in the buffered data
    let sepdata = NSData(bytes: [separator] as [UInt8], length: 1)
    let rangedata = NSMakeRange(0, RxDataBuffer.length)
    let foundRange = RxDataBuffer.rangeOfData(sepdata, options:[], range:rangedata)
    
    // data parsing variables
    let data_chunk : NSMutableData = NSMutableData()
    let data_left : NSMutableData = NSMutableData()
    
    // here we check to see if the separator exists, and therefore that we
    // have a complete message ready to be extracted
    if foundRange.location != NSNotFound {
      // extract the entire message from the rx data buffer
      data_chunk.appendData(RxDataBuffer.subdataWithRange(NSMakeRange(0,foundRange.location)))
      // if there is leftover data in the buffer, make sure to keep it otherwise
      // the parsing will not work for the next message that is partially complete now
      if RxDataBuffer.length-1 > foundRange.location {
        data_left.appendData(RxDataBuffer.subdataWithRange(NSMakeRange(foundRange.location+1,RxDataBuffer.length-foundRange.location-1)))
        RxDataBuffer = data_left
      } else {
        RxDataBuffer = NSMutableData()
      }
      // TODO: remove this, just for debug
      let str = String(data: data_chunk,encoding: NSUTF8StringEncoding)
      if str != nil {
  //             vmlog(str!)
      } else {
        vmlog("not UTF8")
      }
      /////////////////////////////////////
    }
    
    
    // do the actual parsing if we've managed to extract a full message
    if data_chunk.length > 0 {
      do {
        
        // decode json
        let json = try NSJSONSerialization.JSONObjectWithData(data_chunk, options: .MutableContainers)
        
        // every message will have a timestamp
        var timestamp : NSInteger = 0
        if json["timestamp"] != nil {
          timestamp = json["timestamp"] as! NSInteger
        }
        
        
        
        // evented measurement rsp
        ///////////////////
        // evented measuerment messages will have an "event" key
        if let event = json["event"] as? NSString {
          
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
          latestVehicleMeasurements.setValue(rsp, forKey:name as String)
          
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
        else if let name = json["name"] as? NSString {
          
          // extract other keys from message
          let value : AnyObject = json["value"] ?? NSNull()
          
          // build measurement message
          let rsp : VehicleMeasurementResponse = VehicleMeasurementResponse()
          rsp.value = value
          rsp.timestamp = timestamp
          rsp.name = name
          
          // capture this message into the dictionary of latest messages
          latestVehicleMeasurements.setValue(rsp, forKey:name as String)
          
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
        else if let cmd_rsp = json["command_response"] as? NSString {
          
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
        else if let id = json["id"] as? NSInteger {
          
          // only diagnostic response messages have "success"
          if let success = json["success"] as? Bool {
            
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
            
            // build the key that identifies this diagnostic response
            // bus-id-mode-[X or pid]
            let tupple : NSMutableString = ""
            tupple.appendString("\(String(bus))-\(String(id))-\(String(mode))-")
            if pid != nil {
              tupple.appendString(String(pid))
            } else {
              tupple.appendString("X")
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
              if act!.returnKey() == tupple {
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
              act.performAction(["status":VehicleManagerStatusMessage.BLE_RX_DATA_PARSE_ERROR.rawValue] as Dictionary)
            }
          }
          
          
        } else {
          // what the heck is it??
          if let act = managerCallback {
            act.performAction(["status":VehicleManagerStatusMessage.BLE_RX_DATA_PARSE_ERROR.rawValue] as Dictionary)
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
          let str = String(data: data_chunk,encoding: NSUTF8StringEncoding)
          traceFileWriter(str!)
        }
        
        
        // Keep a count of how many messages were received in total
        // since connection. Can be used by the client app.
        messageCount += 1
        
        
        
      } catch {
        // the json decode failed for some reason, usually data lost in connection
        vmlog("bad json")
        if let act = managerCallback {
          act.performAction(["status":VehicleManagerStatusMessage.BLE_RX_DATA_PARSE_ERROR.rawValue] as Dictionary)
        }
      }
      
      
    }
    
    return timestamp
    
  }
  
  
  // Write the incoming string to the configured trace output file.
  // Make sure that there are no LF/CR in the parameter string, because
  // this method adds a CR automatically
  private func traceFileWriter (string:String) {
    
    vmlog("trace:",string)
    
    var traceOut = string
    
    traceOut.appendContentsOf("\n");

    // search for the trace output file
    if let dir = NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory.DocumentDirectory,
                                                     NSSearchPathDomainMask.AllDomainsMask, true).first {
      let path = NSURL(fileURLWithPath: dir).URLByAppendingPathComponent(traceFilesinkName as String)
      
      // write the string to the trace output file
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
          // file handle open failed for some reason,
          // try writing to the file as a path url.
          // shouldn't reach this normally
          try data.writeToURL(path, options: .DataWritingAtomic)
        }
      }
      catch {
        // couldn't write to the trace output file
        if let act = managerCallback {
          act.performAction(["status":VehicleManagerStatusMessage.TRACE_SINK_WRITE_ERROR.rawValue] as Dictionary)
        }
      }
      
    } else {
      // couldn't find trace output file
      if let act = managerCallback {
        act.performAction(["status":VehicleManagerStatusMessage.TRACE_SINK_WRITE_ERROR.rawValue] as Dictionary)
      }
    }
    
    
  }
  
  // Read a chunk of data from the trace input file.
  // 20B is chosen as the chunk size to mirror the BLE data size.
  // Called by timer function when client app provides a speed value for
  // trace input file
  private dynamic func traceFileReaderAuto () {
    
    // if the trace file is enabled and open, read 20B
    if traceFilesourceEnabled && traceFilesourceHandle != nil {
      let rdData = traceFilesourceHandle!.readDataOfLength(20)
      
      // we have read some data, append it to the rx data buffer
      if rdData.length > 0 {
        RxDataBuffer.appendData(rdData)
        // Try parsing the data that was added to the buffer. Use
        // LF as the message delimiter because that's what's used
        // in trace files.
        RxDataParser(0x0a)
      } else {
        // There was no data read, so we're at the end of the
        // trace input file. Close the input file.
        vmlog("traceFilesource EOF")
        traceFilesourceHandle!.closeFile()
        traceFilesourceHandle = nil
        // notify the client app if the callback is enabled
        if let act = managerCallback {
          act.performAction(["status":VehicleManagerStatusMessage.TRACE_SOURCE_END.rawValue] as Dictionary)
        }
      }
      
    }
    
  }
  
  
  // Read a chunk of data from the trace input file.
  // 20B is chosen as the chunk size to mirror the BLE data size.
  // Called by timer function when client app provides a speed value for
  // trace input file
  private dynamic func traceFileReader () {
    
    // if the last timestamp is 0, read twice because this is the first message
    // we're reading
    if traceFilesourceLastTime == 0 && traceFilesourceEnabled && traceFilesourceHandle != nil {
      let rdData = traceFilesourceHandle!.readDataOfLength(20)
      // we have read some data, append it to the rx data buffer
      if rdData.length > 0 {
        RxDataBuffer.appendData(rdData)
        // Try parsing the data that was added to the buffer. Use
        // LF as the message delimiter because that's what's used
        // in trace files.
        traceFilesourceLastTime = RxDataParser(0x0a)
      } else {
        // There was no data read, so we're at the end of the
        // trace input file. Close the input file.
        vmlog("traceFilesource EOF")
        traceFilesourceHandle!.closeFile()
        traceFilesourceHandle = nil
        // notify the client app if the callback is enabled
        if let act = managerCallback {
          act.performAction(["status":VehicleManagerStatusMessage.TRACE_SOURCE_END.rawValue] as Dictionary)
        }
        return
      }
    }

    // if the trace file is enabled and open, read 20B
    if traceFilesourceEnabled && traceFilesourceHandle != nil {
      let rdData = traceFilesourceHandle!.readDataOfLength(20)
      
      // we have read some data, append it to the rx data buffer
      if rdData.length > 0 {
        RxDataBuffer.appendData(rdData)
        // Try parsing the data that was added to the buffer. Use
        // LF as the message delimiter because that's what's used
        // in trace files.
        RxDataParser(0x0a)
      } else {
        // There was no data read, so we're at the end of the
        // trace input file. Close the input file.
        vmlog("traceFilesource EOF")
        traceFilesourceHandle!.closeFile()
        traceFilesourceHandle = nil
        // notify the client app if the callback is enabled
        if let act = managerCallback {
          act.performAction(["status":VehicleManagerStatusMessage.TRACE_SOURCE_END.rawValue] as Dictionary)
        }
      }
      
    }
    
  }
  
  
  
  
  
  
  
  // MARK: Core Bluetooth Manager
  
  
  // watch for changes to the BLE state
  public func centralManagerDidUpdateState(central: CBCentralManager) {
    vmlog("in centralManagerDidUpdateState:")
    if central.state == .PoweredOff {
      vmlog(" PoweredOff")
    } else if central.state == .PoweredOn {
      vmlog(" PoweredOn")
    } else {
      vmlog(" Other")
    }
  
    if central.state == CBCentralManagerState.PoweredOn && connectionState == .Scanning {
      centralManager.scanForPeripheralsWithServices(nil, options: nil)
    }
    
    
  }
  
  
  // Core Bluetooth has discovered a BLE peripheral
  public func centralManager(central: CBCentralManager, didDiscoverPeripheral peripheral: CBPeripheral, advertisementData: [String : AnyObject], RSSI: NSNumber) {
    vmlog("in centralManager:didDiscover")
    
    if openXCPeripheral == nil {
      
      // only find the right kinds of the BLE devices (C5 VI)
      if let advNameCheck : String = advertisementData["kCBAdvDataLocalName"] as? String {
        let advName = advNameCheck.uppercaseString
        if advName.hasPrefix(OpenXCConstants.C5_VI_NAME_PREFIX) {
          // check to see if we already have this one
          // and save the discovered peripheral
          if foundOpenXCPeripherals[advName] == nil {
            vmlog("FOUND:")
            vmlog(peripheral.identifier.UUIDString)
            vmlog(advertisementData["kCBAdvDataLocalName"])
            
            foundOpenXCPeripherals[advName] = peripheral
            
            // if we're in auto connect mode, just connect right away
            if autoConnectPeripheral {
              connect()
            }
            
            // notify client if the callback is enabled
            if let act = managerCallback {
              act.performAction(["status":VehicleManagerStatusMessage.C5DETECTED.rawValue] as NSDictionary)
            }
            
          }
        }
        
      }
      
    }
  }
  
  // Core Bluetooth has connected to a BLE peripheral
  public func centralManager(central: CBCentralManager, didConnectPeripheral peripheral: CBPeripheral) {
    vmlog("in centralManager:didConnectPeripheral:")
    
    // update the connection state
    connectionState = .Connected
    
    // auto discover the services for this peripheral
    peripheral.discoverServices(nil)
    
    // notify client if the callback is enabled
    if let act = managerCallback {
      act.performAction(["status":VehicleManagerStatusMessage.C5CONNECTED.rawValue] as NSDictionary)
    }
  }
  
  
  public func centralManager(central: CBCentralManager, didFailToConnectPeripheral peripheral: CBPeripheral, error: NSError?) {
    vmlog("in centralManager:didFailToConnectPeripheral:")
  }
  
  
  public func centralManager(central: CBCentralManager, willRestoreState dict: [String : AnyObject]) {
    vmlog("in centralManager:willRestoreState")
  }
  
  
  // Core Bluetooth has disconnected from BLE peripheral
  public func centralManager(central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: NSError?) {
    vmlog("in centralManager:didDisconnectPeripheral:")
    vmlog(error)
    
    // just reconnect automatically to the same device for now
    if peripheral == openXCPeripheral {
      centralManager.connectPeripheral(openXCPeripheral, options:nil)

      // notify client if the callback is enabled
      if let act = managerCallback {
        act.performAction(["status":VehicleManagerStatusMessage.C5DISCONNECTED.rawValue] as NSDictionary)
      }

      // clear any saved context
      latestVehicleMeasurements = NSMutableDictionary()
      
      // update the connection state
      connectionState = .ConnectionInProgress
    }
    
  }
  
  
  
  // MARK: Peripheral Delgate Function
  
  // Core Bluetooth has discovered services for a peripheral
  public func peripheral(peripheral: CBPeripheral, didDiscoverServices error: NSError?) {
    vmlog("in peripheral:didDiscoverServices")
    
    // this isn't our captured openXC peripheral... should never happen
    if peripheral != openXCPeripheral {
      vmlog("peripheral error!")
      return
    }
    
    // scan through all of the available services
    // look for the open XC service
    for service in peripheral.services! {
      vmlog(" - Found service : ",service.UUID)
      
      // uuid matches, we found the service
      if service.UUID.UUIDString == OpenXCConstants.C5_OPENXC_BLE_SERVICE_UUID {
        vmlog("   OPENXC_MAIN_SERVICE DETECTED")
        // capture the service
        openXCService = service
        // automatically discover all charateristics for the openXC service
        openXCPeripheral.discoverCharacteristics(nil, forService:service)
        
        // notify client if the callback is enabled
        if let act = managerCallback {
          act.performAction(["status":VehicleManagerStatusMessage.C5SERVICEFOUND.rawValue] as NSDictionary)
        }
      }
      
    }
  }
  
  
  // Core Bluetooth has discovered characteristics for a service
  public func peripheral(peripheral: CBPeripheral, didDiscoverCharacteristicsForService service: CBService, error: NSError?) {
    vmlog("in peripheral:didDiscoverCharacteristicsForService")
    
    // check that we're getting info from the right peripheral and service
    if peripheral != openXCPeripheral {
      vmlog("peripheral error!")
      return
    }
    if service != openXCService {
      vmlog("service error!")
      return
    }
    
    // loop through all characteristics found
    for characteristic in service.characteristics! {
      vmlog(" - Found characteristic : ",characteristic.UUID)
      
      // uuid matched on openXC notify characteristic
      if characteristic.UUID.UUIDString == OpenXCConstants.C5_OPENXC_BLE_CHARACTERISTIC_NOTIFY_UUID {
        // capture the characteristic
        openXCNotifyChar = characteristic
        // turn on the notification characteristic
        peripheral.setNotifyValue(true, forCharacteristic:characteristic)
        // discover any descriptors for the characteristic
        openXCPeripheral.discoverDescriptorsForCharacteristic(characteristic)
        // notify client if the callback is enabled
        if let act = managerCallback {
          act.performAction(["status":VehicleManagerStatusMessage.C5NOTIFYON.rawValue] as NSDictionary)
        }
        // update connection state to indicate that we're fully operational and receiving data
        connectionState = .Operational
      }
      
      // uuid matched on openXC notify characteristic
      if characteristic.UUID.UUIDString == OpenXCConstants.C5_OPENXC_BLE_CHARACTERISTIC_WRITE_UUID {
        // capture the characteristic
        openXCWriteChar = characteristic
        // discover any descriptors for the characteristic
        openXCPeripheral.discoverDescriptorsForCharacteristic(characteristic)
      }
    }
    
  }
  
  
  // Core Bluetooth has data received from a characteristic
  public func peripheral(peripheral: CBPeripheral, didUpdateValueForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
    // vmlog("in peripheral:didUpdateValueForCharacteristic")
    
    // If we have a trace input file enabled, we need to mask any
    // data coming in from BLE. Just ignore the data by returning early.
    if traceFilesourceEnabled {return}
    
    // grab the data from the characteristic
    let data = characteristic.value!
    
    // if there is actually data, append it to the rx data buffer,
    // and try to parse any messages held in the buffer. The separator
    // in this case is nil because messages arriving from BLE is
    // delineated by null characters
    if data.length > 0 {
      RxDataBuffer.appendData(data)
      RxDataParser(0x00)
    }
    
  }
  
  
  // Core Bluetooth has discovered a description for a characteristic
  // don't need to save or use it in this case
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
  
  
  // Core Bluetooth has written a value to a characteristic
  public func peripheral(peripheral: CBPeripheral, didWriteValueForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
    vmlog("in peripheral:didWriteValueForCharacteristic")
    if error != nil {
      vmlog("error")
      vmlog(error!.localizedDescription)
    } else {

    }
    
    // Thread sleep for a small time interval, allowing some time to pass before we
    // call the BLESendFunction method again. This prevents deadlocks/issues with
    // the semaphore that is altered here and in that method. The Core Bluetooth 
    // methods are all running outside of the main thread, so this short sleep will
    // not affect any UI
    NSThread.sleepForTimeInterval(0.05)
    // Decrement the tx write semaphone, indicating that we have received acknowledgement
    // for sending one chunk of data
    BLETxWriteCount -= 1
    // Call the BLESendFunction again, in case this is the last chunk of data acknowledged for
    // a message, and we have another message queued up in the buffer. If this is not the last chunk
    // for this message (tx write semaphore>0) or there aren't any other messages queued
    // (tx buffer count==0), then the BLESendFunction returns immediately
    BLESendFunction()
  }
  
  
  public func peripheral(peripheral: CBPeripheral, didWriteValueForDescriptor descriptor: CBDescriptor, error: NSError?) {
    vmlog("in peripheral:didWriteValueForDescriptor")
  }
  
  
  public func peripheral(peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: NSError?) {
    vmlog("in peripheral:didReadRSSI")
  }
  
  
  
  
  
}
