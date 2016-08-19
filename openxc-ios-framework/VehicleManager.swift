//
//  VehicleManager.swift
//  openXCSwift
//
//  Created by Tim Buick on 2016-06-16.
//  Copyright © 2016 BugLabs. All rights reserved.
//

import Foundation
import CoreBluetooth


public enum VehicleManagerStatusMessage: Int {
  case C5DETECTED
  case C5CONNECTED
  case C5SERVICEFOUND
  case C5NOTIFYON
  case C5OPERATIONAL
  case C5DISCONNECTED
  case TRACE_SOURCE_END
}

public enum VehicleManagerConnectionState: Int {
  case NotConnected=0
  case ConnectionInProgress=1
  case Connected=2
  case Operational=3
}





public class VehicleManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {

  
  
  // MARK : Singleton Init
  
  static public let sharedInstance: VehicleManager = {
    let instance = VehicleManager()
    // TODO do we want to autoconnect?
    // probably not because the client app will need to 
    // setup delegates and such
    // instance.connect()
    //////////////////
    return instance
  }()
  private override init() {
  }
  
  
  
  // MARK : Class Vars

  private var centralManager: CBCentralManager!
  private var openXCPeripheral: CBPeripheral!
  private var openXCService: CBService!
  private var openXCNotifyChar: CBCharacteristic!
  private var openXCWriteChar: CBCharacteristic!

  private var managerDebug : Bool = false
  private var managerCallback: TargetAction?
  
  private var RxDataBuffer: NSMutableData! = NSMutableData()
  
  private var BLETxDataBuffer: NSMutableArray! = NSMutableArray()
  private var BLETxWriteCount: Int = 0
  private var BLETxSendToken: Int = 0
  
  private var BLETxCommandCallback = [TargetAction]()
  private var BLETxCommandToken = [String]()

  private var measurementCallbacks = [NSString:TargetAction]()
  private var defaultMeasurementCallback : TargetAction?

  private var diagCallbacks = [NSString:TargetAction]()
  private var defaultDiagCallback : TargetAction?
  
  private var canCallbacks = [NSString:TargetAction]()
  private var defaultCanCallback : TargetAction?
  
  private var traceFilesinkEnabled: Bool = false
  private var traceFilesinkName: NSString = ""

  private var traceFilesourceEnabled: Bool = false
  private var traceFilesourceName: NSString = ""
  private var traceFilesourceTimer: NSTimer = NSTimer()
  private var traceFilesourceHandle: NSFileHandle?
  
  

  public var connectionState: VehicleManagerConnectionState! = .NotConnected
  public var messageCount: Int = 0

  private var latestVehicleMeasurements: NSMutableDictionary! = NSMutableDictionary()
  
  private var registeredCallbacks: NSMutableDictionary! = NSMutableDictionary()
  
  
  
  
  // MARK : Class Defines
  
 
  
  
  
  
  // MARK : Class Functions
  
  public func setManagerCallbackTarget<T: AnyObject>(target: T, action: (T) -> (NSDictionary) -> ()) {
    managerCallback = TargetActionWrapper(key:"", target: target, action: action)
  }
  
  public func setManagerDebug(on:Bool) {
    managerDebug = on
  }
  
  private func vmlog(strings:Any...) {
    if managerDebug {
      for string in strings {
        print(string,terminator:"")
      }
      print("")
    }
  }
  
  
  public func connect() {
    // TODO allow VI to be chosen from a list
    // instead of auto connecting to first VI
    
    // TODO handle already connected!
    if connectionState != .NotConnected {
      vmlog("VehicleManager already connected! Sorry!")
      return
    }
    
    let cbqueue: dispatch_queue_t = dispatch_queue_create("CBQ", DISPATCH_QUEUE_SERIAL)

    
    vmlog("VehicleManager connect started")
    connectionState = .ConnectionInProgress
    messageCount = 0
    openXCPeripheral=nil
    centralManager = CBCentralManager(delegate: self, queue: cbqueue, options:nil)
    
  }
  
  
  
  public func enableTraceFileSink(filename:NSString) -> Bool {
    
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

    traceFilesinkEnabled = true
    traceFilesinkName = filename
  
    
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
  
  
  public func disableTraceFileSink() {
  
    traceFilesinkEnabled = false
    
  }
  
  
  
  
  public func enableTraceFileSource(filename:NSString, speed:NSInteger=500) -> Bool {

    if speed < 50 || speed > 1000 {return false}
    
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
    
    
    
    if let dir = NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory.DocumentDirectory,
                                                     NSSearchPathDomainMask.AllDomainsMask, true).first {
      
      let path = NSURL(fileURLWithPath: dir).URLByAppendingPathComponent(filename as String).path!
      
      vmlog("checking for file")
      if NSFileManager.defaultManager().fileExistsAtPath(path) {
        vmlog("file detected")
        traceFilesourceEnabled = true
        traceFilesourceName = filename

        traceFilesourceHandle = NSFileHandle(forReadingAtPath:path)
        if traceFilesourceHandle == nil {
          vmlog("can't open filehandle")
          return false
        }
        
        let spdf:Double = Double(speed) / 1000.0
        traceFilesourceTimer = NSTimer.scheduledTimerWithTimeInterval(spdf, target: self, selector: #selector(traceFileReader), userInfo: nil, repeats: true)

        return true
        
      }
    }
    
    return false
    
  }
  
  
  public func disableTraceFileSource() {

    traceFilesourceEnabled = false
  }
  
  
  public func getLatest(key:NSString) -> VehicleMeasurementResponse {
    if let entry = latestVehicleMeasurements[key] {
     return entry as! VehicleMeasurementResponse
    }
    return VehicleMeasurementResponse()
  }
  
  
  
  public func addMeasurementTarget<T: AnyObject>(key: NSString, target: T, action: (T) -> (NSDictionary) -> ()) {
    measurementCallbacks[key] = TargetActionWrapper(key:key, target: target, action: action)
  }
  
  public func clearMeasurementTarget(key: NSString) {
    measurementCallbacks.removeValueForKey(key)
  }
  
  public func setMeasurementDefaultTarget<T: AnyObject>(target: T, action: (T) -> (NSDictionary) -> ()) {
    defaultMeasurementCallback = TargetActionWrapper(key:"", target: target, action: action)
  }
  
  public func clearMeasurementDefaultTarget() {
    defaultMeasurementCallback = TargetActionWrapper(key: "", target: VehicleManager.sharedInstance, action: VehicleManager.CallbackNull)
  }
  
  
  
  
  public func sendCommand(cmd:VehicleCommandRequest) {
    vmlog("in sendCommand")

    if (traceFilesourceEnabled) {return}
    
    
    BLETxSendToken += 1
    let key : String = String(BLETxSendToken)
    let act : TargetAction = TargetActionWrapper(key: "", target: VehicleManager.sharedInstance, action: VehicleManager.CallbackNull)
    BLETxCommandCallback.append(act)
    BLETxCommandToken.append(key)
    
    sendCommandCommon(cmd)
    
  }
  
  public func sendCommand<T: AnyObject>(cmd:VehicleCommandRequest, target: T, action: (T) -> (NSDictionary) -> ()) -> String {
    vmlog("in sendCommand:target")
    
    if (traceFilesourceEnabled) {return ""}

    BLETxSendToken += 1
    let key : String = String(BLETxSendToken)
    let act : TargetAction = TargetActionWrapper(key:key, target: target, action: action)
    BLETxCommandCallback.append(act)
    BLETxCommandToken.append(key)

    sendCommandCommon(cmd)
    
    return key
    
  }
  
  
  
  public func sendDiagReq(cmd:VehicleDiagnosticRequest) {
    vmlog("in sendDiagReq")
    
    if (traceFilesourceEnabled) {return}

    BLETxSendToken += 1
    let key : String = String(BLETxSendToken)
    let act : TargetAction = TargetActionWrapper(key: "", target: VehicleManager.sharedInstance, action: VehicleManager.CallbackNull)
    BLETxCommandCallback.append(act)
    BLETxCommandToken.append(key)

    sendDiagCommon(cmd)
    
  }
  
  public func sendDiagReq<T: AnyObject>(cmd:VehicleDiagnosticRequest, target: T, cmdaction: (T) -> (NSDictionary) -> ()) -> String {
    vmlog("in sendDiagReq:cmd")
    
    if (traceFilesourceEnabled) {return ""}

    BLETxSendToken += 1
    let key : String = String(BLETxSendToken)
    let act : TargetAction = TargetActionWrapper(key:key, target: target, action: cmdaction)
    BLETxCommandCallback.append(act)
    BLETxCommandToken.append(key)
    
    sendDiagCommon(cmd)
    
    return key
    
  }
  

  
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
    vmlog("add diag key=",key)
    diagCallbacks[key] = TargetActionWrapper(key:key, target: target, action: action)
  }
  
  public func clearDiagnosticTarget(keys: [NSString]) {
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
    vmlog("rm diag key=",key)
    diagCallbacks.removeValueForKey(key)
  }
  
  
  public func setDiagnosticDefaultTarget<T: AnyObject>(target: T, action: (T) -> (NSDictionary) -> ()) {
    defaultDiagCallback = TargetActionWrapper(key:"", target: target, action: action)
  }
  
  public func clearDiagnosticDefaultTarget() {
    defaultDiagCallback = TargetActionWrapper(key: "", target: VehicleManager.sharedInstance, action: VehicleManager.CallbackNull)
  }
  
  
  
  
  
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
    vmlog("add can key=",key)
    diagCallbacks[key] = TargetActionWrapper(key:key, target: target, action: action)
  }
  
  public func clearCanTarget(keys: [NSString]) {
    let key : NSMutableString = ""
    var first : Bool = true
    for i in keys {
      if !first {
        key.appendString("-")
      }
      first=false
      key.appendString(String(i))
    }
    vmlog("rm can key=",key)
    diagCallbacks.removeValueForKey(key)
  }
  
  
  public func setCanDefaultTarget<T: AnyObject>(target: T, action: (T) -> (NSDictionary) -> ()) {
    defaultCanCallback = TargetActionWrapper(key:"", target: target, action: action)
  }
  
  public func clearCanDefaultTarget() {
    defaultCanCallback = TargetActionWrapper(key: "", target: VehicleManager.sharedInstance, action: VehicleManager.CallbackNull)
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
    
    // wait for BLE acknowledgement
    // TODO need a timeout!
    while (BLETxWriteCount>0) {
      NSThread.sleepForTimeInterval(0.05)
    }
  }
  
  
  private func sendDiagCommon(cmd:VehicleDiagnosticRequest) {
    vmlog("in sendDiagCommon")
 
    let cmdjson : NSMutableString = ""
    cmdjson.appendString("{\"command\":\"diagnostic_request\",\"action\":\"add\",\"request\":{\"bus\":\(cmd.bus),\"id\":\(cmd.message_id),\"mode\":\(cmd.mode)")
    if cmd.pid != nil {
      cmdjson.appendString(",\"pid\":\(cmd.pid!)")
    }
    cmdjson.appendString("}}\0")

    // TODO what about recurring diagnostic messages
    
    vmlog("sending diag cmd:",cmdjson)
    
    BLETxDataBuffer.addObject(cmdjson.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)!)
    
    BLESendFunction()
    
    // wait for BLE acknowledgement
    // TODO need timeout here!
    while (BLETxWriteCount>0) {
      NSThread.sleepForTimeInterval(0.05)
    }
  
  }
  
  
  
  private func CallbackNull(o:AnyObject) {
//    vmlog("in CallbackNull")
  }
  
  
  private func BLESendFunction() {
    
    vmlog("in BLESendFunction")
    
    var sendBytes: NSData
    
//    vmlog (BLETxDataBuffer)
    
    if BLETxDataBuffer.count == 0 {
      return
    }
    
    var cmdToSend : NSMutableData = BLETxDataBuffer[0] as! NSMutableData
    BLETxDataBuffer.removeObjectAtIndex(0)
    
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
//      vmlog("sent:",sendBytes)
    }
    
    

  }
  
  
  
  
  private func RxDataParser(separator:UInt8) {
    
    
    // JSON decoding
    // TODO if protbuf?
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
 //       vmlog(str!)
      } else {
        vmlog("not UTF8")
      }
    }
    
    
    // TODO error handling!
    if data_chunk.length > 0 {
      do {
        let json = try NSJSONSerialization.JSONObjectWithData(data_chunk, options: .MutableContainers)
        let str = String(data: data_chunk,encoding: NSUTF8StringEncoding)
        
        // TODO this isn't really working...?
        var decodedMessage : VehicleBaseMessage = VehicleBaseMessage()
        
        
        var timestamp : NSInteger = 0
        if json["timestamp"] != nil {
          timestamp = json["timestamp"] as! NSInteger
          decodedMessage.timestamp = timestamp
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
          decodedMessage = rsp
          
          
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
          decodedMessage = rsp
          
          // bool test
          // TODO maybe keep track of what type each rsp is?
          /*
          if value is NSNumber {
            let nv = value as! NSNumber
            if nv.isEqualToValue(NSNumber(bool: true)) {
              vmlog("it's a bool and it's true")
            } else if nv.isEqualToValue(NSNumber(bool:false)) {
              vmlog("it's a bool and it's true")
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
          decodedMessage = rsp
          
          let ta : TargetAction = BLETxCommandCallback.removeFirst()
          let s : String = BLETxCommandToken.removeFirst()
          ta.performAction(["vehiclemessage":rsp,"key":s] as NSDictionary)
          
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
            decodedMessage = rsp
            
            
            let tupple : NSMutableString = ""
            tupple.appendString("\(String(bus))-\(String(id))-\(String(mode))-")
            
            if pid != nil {
              tupple.appendString(String(pid))
              vmlog("diag rsp msg:\(bus) id:\(id) mode:\(mode) pid:\(pid) success:\(success) value:\(value)")
            } else {
              tupple.appendString("X")
              vmlog("diag rsp msg:\(bus) id:\(id) mode:\(mode) success:\(success) value:\(value)")
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
            decodedMessage = rsp
            
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
            // what the heck is it??
            
          }
          
          
         
          
        }
          
          
          
        
        
        
        if traceFilesinkEnabled {
          traceFileWriter(str!)
        }
        
        
        messageCount += 1
        
        
        
        
      } catch {
        vmlog("bad json")
        // bad json!
      }
      
      
    }
    
  }
  
  
  
  private func traceFileWriter (message:VehicleBaseMessage) {
    
    // TODO if we want to be able to trace directly from a vehicleMessage,
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
        // TODO error handling here
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
  
  
  

  
  
  // MARK : Core Bluetooth Manager
  
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
      // TODO look at advData, or just either possible name, confirm with Ford
      if peripheral.name=="OpenXC_C5_BTLE" || peripheral.name=="CrossChasm" {
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
    // TODO allow configuration of auto-reconnect?
    if peripheral.name=="OpenXC_C5_BTLE" {
      centralManager.connectPeripheral(openXCPeripheral, options:nil)
    }
    if peripheral.name=="CrossChasm" {
      centralManager.connectPeripheral(openXCPeripheral, options:nil)
    }
    if let act = managerCallback {
      act.performAction(["status":VehicleManagerStatusMessage.C5DISCONNECTED.rawValue] as NSDictionary)
    }
    connectionState = .ConnectionInProgress

  }
  
  
  
  // MARK : Peripheral Delgate Function
  
  public func peripheral(peripheral: CBPeripheral, didDiscoverServices error: NSError?) {
    vmlog("in peripheral:didDiscoverServices")
    if peripheral != openXCPeripheral {
      vmlog("peripheral error!")
      return
    }
    
    for service in peripheral.services! {
      vmlog(" - Found service : ",service.UUID)
      
      if service.UUID.UUIDString == "6800D38B-423D-4BDB-BA05-C9276D8453E1" {
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
      if characteristic.UUID.UUIDString == "6800D38B-5262-11E5-885D-FEFF819CDCE3" {
        openXCNotifyChar = characteristic
        peripheral.setNotifyValue(true, forCharacteristic:characteristic)
        openXCPeripheral.discoverDescriptorsForCharacteristic(characteristic)
        if let act = managerCallback {
          act.performAction(["status":VehicleManagerStatusMessage.C5NOTIFYON.rawValue] as NSDictionary)
        }
        connectionState = .Operational
      }
      if characteristic.UUID.UUIDString == "6800D38B-5262-11E5-885D-FEFF819CDCE2" {
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
      BLETxWriteCount -= 1
    }
  }
  
  
  public func peripheral(peripheral: CBPeripheral, didWriteValueForDescriptor descriptor: CBDescriptor, error: NSError?) {
    vmlog("in peripheral:didWriteValueForDescriptor")
  }
  
  
  public func peripheral(peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: NSError?) {
    vmlog("in peripheral:didReadRSSI")
  }
  

  
  

}