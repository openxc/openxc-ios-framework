//
//  Command.swift
//  openxc-ios-framework
//
//  Created by Kanishka, Vedi (V.) on 28/06/17.
//  Copyright © 2017 Ford Motor Company. All rights reserved.
//

import Foundation
import ProtocolBuffers

public enum VehicleCommandType: NSString {
    case version
    case device_id
    case platform
    case passthrough
    case af_bypass
    case payload_format
    case predefined_odb2
    case modem_configuration
    case sd_mount_status
    case rtc_configuration
}


open class VehicleCommandRequest : VehicleBaseMessage {
    public override init() {
        super.init()
        type = .commandResponse
    }
    open var command : VehicleCommandType = .version
    open var bus : NSInteger = 0
    open var enabled : Bool = false
    open var bypass : Bool = false
    open var format : NSString = ""
    open var server_host : NSString = ""
    open var server_port : NSInteger = 0
    open var unix_time : NSInteger = 0
}

open class VehicleCommandResponse : VehicleBaseMessage {
    public override init() {
        super.init()
        type = .commandResponse
    }
    open var command_response : NSString = ""
    open var message : NSString = ""
    open var status : Bool = false
    override func traceOutput() -> NSString {
        return "{\"timestamp\":\(timestamp),\"command_response\":\"\(command_response)\",\"message\":\"\(message)\",\"status\":\(status)}" as NSString
    }
}


open class Command: NSObject {
    
    
    // MARK: Singleton Init
    
    // This signleton init allows mutiple controllers to access the same instantiation
    // of the VehicleManager. There is only a single instantiation of the VehicleManager
    // for the entire client app
    static open let sharedInstance: Command = {
        let instance = Command()
        return instance
    }()
    fileprivate override init() {
    }
    
    // config variable determining whether trace input is used instead of BTLE data
    fileprivate var traceFilesourceEnabled: Bool = false
    
    // BTLE transmit token increment variable
    fileprivate var BLETxSendToken: Int = 0
    
    // ordered list for storing callbacks for in progress vehicle commands
    fileprivate var BLETxCommandCallback = [TargetAction]()
    
    // mirrored ordered list for storing command token for in progress vehicle commands
    fileprivate var BLETxCommandToken = [String]()
    
    // config for protobuf vs json BLE mode, defaults to JSON
    fileprivate var jsonMode : Bool = true
    
    // config for outputting debug messages to console
    fileprivate var managerDebug : Bool = false
    
    // data buffer for storing vehicle messages to send to BTLE
    fileprivate var BLETxDataBuffer: NSMutableArray! = NSMutableArray()
    
    var vm = VehicleManager.sharedInstance
    var bm = BluetoothManager.sharedInstance
    // 'default' command callback. If this is defined, it takes priority over any other callback
    fileprivate var defaultCommandCallback : TargetAction?
    // optional variable holding callback for VehicleManager status updates
    fileprivate var managerCallback: TargetAction?
    
    // private debug log function gated by the debug setting
    fileprivate func vmlog(_ strings:Any...) {
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
    
    // MARK: Class Functions
    
    // set the callback for VM status updates
    open func setManagerCallbackTarget<T: AnyObject>(_ target: T, action: @escaping (T) -> (NSDictionary) -> ()) {
        managerCallback = TargetActionWrapper(key:"", target: target, action: action)
    }
    // add a default callback for any measurement messages not include in specified callbacks
    open func setCommandDefaultTarget<T: AnyObject>(_ target: T, action: @escaping (T) -> (NSDictionary) -> ()) {
        defaultCommandCallback = TargetActionWrapper(key:"", target: target, action: action)
    }
    
    // clear default callback (by setting the default callback to a null method)
    open func clearCommandDefaultTarget() {
        defaultCommandCallback = nil
    }
    
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
                print (mmsg)
                
                
                let cdata = mmsg.data()
                let cdata2 = NSMutableData()
                let prepend : [UInt8] = [UInt8(cdata.count)]
                cdata2.append(Data(bytes: UnsafePointer<UInt8>(prepend), count:1))
                cdata2.append(cdata)
                print(cdata2)
                
                // append to tx buffer
                BLETxDataBuffer.add(cdata2)
                
                // trigger a BLE data send
                bm.BLESendFunction()
                
            } catch {
                print("cmd msg build failed")
            }
            
            return
        }
        
        // we're in json mode
        var cmdstr = ""
        // decode the command type and build the command depending on the command
        print("cmd command...",cmd.command)
        
        if cmd.command == .version || cmd.command == .device_id || cmd.command == .sd_mount_status || cmd.command == .platform {
            // build the command json
            cmdstr = "{\"command\":\"\(cmd.command.rawValue)\"}\0"
            print("cmdStr..",cmdstr)
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
        
        print("BLETxDataBuffer.count...",BLETxDataBuffer.count)
        print("BLETxDataBuffer...",BLETxDataBuffer)
        
        self.vm.BLETxDataBuffer = BLETxDataBuffer
        
        // trigger a BLE data send
        bm.BLESendFunction()
        //BLESendFunction()
        
    }
}
