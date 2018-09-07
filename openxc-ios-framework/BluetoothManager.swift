//
//  BluetoothManager.swift
//  openxc-ios-framework
//  Created by Ranjan, Kumar sahu (K.) on 21/05/18.
//  Copyright © 2018 Ford Motor Company. All rights reserved.

import UIKit
import CoreBluetooth

// public enum VehicleManagerConnectionState
// values reported in public variable connectionState
public enum VehicleManagerConnectionState: Int {
  case notConnected=0           // not connected to any C5 VI
  case scanning=1               // VM is allocation and scanning for nearby VIs
  case connectionInProgress=2   // connection in progress (connecting/searching for services)
  case connected=3              // connection established (but not ready to receive btle writes)
  case operational=4            // C5 VI operational (notify enabled and writes accepted)
}

open class BluetoothManager: NSObject,CBCentralManagerDelegate,CBPeripheralDelegate {

  
  static let _sharedInstance = BluetoothManager()
  
  // MARK: Class Vars
  // -----------------
  
  // CoreBluetooth variables
  fileprivate var centralManager: CBCentralManager!
  open var openXCPeripheral: CBPeripheral!
  fileprivate var openXCService: CBService!
  fileprivate var openXCNotifyChar: CBCharacteristic!
  open var openXCWriteChar: CBCharacteristic!
  
  // dictionary of discovered openXC peripherals when scanning
  open var foundOpenXCPeripherals: [String:CBPeripheral] = [String:CBPeripheral]()
  
  // config for auto connecting to first discovered VI
  fileprivate var autoConnectPeripheral : Bool = true
  
  // config for outputting debug messages to console
  fileprivate var managerDebug : Bool = false
  
  // optional variable holding callback for VehicleManager status updates
  // fileprivate var managerCallback: TargetAction?
  // dictionary holding last received measurement message for each measurement type
  fileprivate var latestVehicleMeasurements: NSMutableDictionary! = NSMutableDictionary()
  public var tempDataBuffer : NSMutableData! = NSMutableData()
  // public variable holding VehicleManager connection state enum
  public var connectionState: VehicleManagerConnectionState! = .notConnected
  
  //Iphone device blutooth is on/fff status
  
  open var isDeviceBluetoothIsOn :Bool = false
  
  var callbackHandler: ((Bool) -> ())?  = nil
  
  //Connected to Ble simulator
  open var isBleConnected: Bool = false
  // BTLE transmit semaphore variable
  fileprivate var BLETxWriteCount: Int = 0
  
  //  variable holding number of messages received since last Connection established
  open var messageCount: Int = 0
  // Initialization
  static open let sharedInstance: BluetoothManager = {
    
    return BluetoothManager()
    
  }()
  fileprivate override init() {
    // connectionState = .notConnected
  }
  // change the auto connect config for the VM
  open func setAutoconnect(_ on:Bool) {
    autoConnectPeripheral = on
    
  }
  
  // connect the VM to a specific VI, or first if no name provided
  open func connect(_ name: String? = nil) {
   
    UserDefaults.standard.setValue(name, forKey: "LastConnectedBle")
    // if the VM is not scanning, don't do anything
    if connectionState != .scanning {
      vmlog("VehicleManager be scanning before a connect can occur!")
      return
    }
    
    //    // if the found VI list is empty, just return
    //    if foundOpenXCPeripherals.count == 0 {
    //      vmlog("VehicleManager has not found any VIs!")
    //
    //      return
    //    }
    //
    //    // for this method, just connect to first one found
    //    openXCPeripheral = foundOpenXCPeripherals.first?.1
    //    openXCPeripheral.delegate = self
    
    //    // start the connection process
    //    vmlog("VehicleManager connect started")
    //    centralManager.connect(openXCPeripheral, options:nil)
    //    connectionState = .connectionInProgress
    //
    //  }
    //
    //
    //  // connect the VM to a specific VI

    //
    //    // if the found VI list is empty, just return
    //    if foundOpenXCPeripherals[name] == nil {
    // if the name is given, look it up. Otherwise use any peripheral
    openXCPeripheral = (name != nil ? foundOpenXCPeripherals[name!] : foundOpenXCPeripherals.first?.1)
    
    if openXCPeripheral == nil {
      vmlog("VehicleManager has not found this peripheral!")
      return
    }
    
    // for this method, just connect to first one found
    // openXCPeripheral = foundOpenXCPeripherals[name]
    openXCPeripheral.delegate = self
    
    // start the connection process
    vmlog("VehicleManager connect started")
    centralManager.connect(openXCPeripheral, options:nil)
   connectionState = .connectionInProgress
    
  }

  // connect the VM to the first VI found
  open func connect() {
    

    print("connect:-\(foundOpenXCPeripherals.count)")
    // if the VM is not scanning, don't do anything
    if connectionState != .scanning {
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
    print(foundOpenXCPeripherals.first!.key)
    UserDefaults.standard.setValue(foundOpenXCPeripherals.first?.key, forKey: "LastConnectedBle")
    openXCPeripheral.delegate = self
    
    // start the connection process
    vmlog("VehicleManager connect started")
    centralManager.connect(openXCPeripheral, options:nil)
    connectionState = .connectionInProgress
    
  }
  
  // initialize the VM and scan for nearby VIs
  open func scan(completionHandler: @escaping (_ success: Bool) -> ()) {
    self.callbackHandler = completionHandler
    // if the VM is already connected, don't do anything
    if connectionState != .notConnected{
      vmlog("VehicleManager already scanning or connected! Sorry!")
      return
    }
    
    // run the core bluetooth framework on a separate thread from main thread
    let cbqueue: DispatchQueue = DispatchQueue(label: "CBQ", attributes: [])
    
    // initialize the BLE manager process
    vmlog("VehicleManager scan started")
    connectionState = .scanning
    messageCount = 0
    openXCPeripheral=nil
    centralManager = CBCentralManager(delegate: self, queue: cbqueue, options: nil)
  }
  
  
  // return array of discovered peripherals
  open func discoveredVI() -> [String] {
    return Array(foundOpenXCPeripherals.keys)
  }
  
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
  // change the debug config for the VM
  open func setManagerDebug(_ on:Bool) {
    managerDebug = on
  }
  
  // MARK: Core Bluetooth Manager
  // watch for changes to the BLE state
  open func centralManagerDidUpdateState(_ central: CBCentralManager) {
    vmlog("in centralManagerDidUpdateState:")
    if central.state == .poweredOff {
      
      self.callbackHandler!(false)
      vmlog(" PoweredOff")
    } else if central.state == .poweredOn {
      vmlog(" PoweredOn")
      self.callbackHandler!(true)
      
    } else {
      vmlog(" Other")
    }
    
    if central.state == .poweredOn && connectionState == .scanning {
      centralManager.scanForPeripherals(withServices: nil, options: nil)
    }
    
  }
  
  //Bluetooth Delegate metods........
  
  
  // Core Bluetooth has discovered a BLE peripheral
  open func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
  
    if openXCPeripheral == nil {
      
      // only find the right kinds of the BLE devices (C5 VI)
      if let advName : String = advertisementData["kCBAdvDataLocalName"] as? String {
        
        if advName.uppercased().hasPrefix(OpenXCConstants.C5_VI_NAME_PREFIX) {
          // check to see if we already have this one
          // and save the discovered peripheral
          if foundOpenXCPeripherals[advName] == nil {
            vmlog("FOUND:")
            vmlog(peripheral.identifier.uuidString)
            vmlog(advertisementData["kCBAdvDataLocalName"] as Any)
            
            foundOpenXCPeripherals[advName] = peripheral
            
            // notify client if the callback is enabled
            if let act = VehicleManager.sharedInstance.managerCallback {
              act.performAction(["status":VehicleManagerStatusMessage.c5DETECTED.rawValue] as NSDictionary)
            }
            
          }
          
        }
        else{
          if(foundOpenXCPeripherals.count > 0) && autoConnectPeripheral{
            if isDeviceKey(){
              connect(UserDefaults.standard.string(forKey:"LastConnectedBle"))
              return
            }else{
              connect()
              return
            }
          }
        }
      }
     
    }
  
  }

  func isDeviceKey() -> Bool {
    for (theKey,_) in foundOpenXCPeripherals{
      if theKey == UserDefaults.standard.string(forKey:"LastConnectedBle") {
        return true
      }
    }
    return false
  }
  
  // Core Bluetooth has connected to a BLE peripheral
  open func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    vmlog("in centralManager:didConnectPeripheral:")
    
    // update the connection state
    connectionState = .connected
    // auto discover the services for this peripheral
    peripheral.discoverServices(nil)
    
    // notify client if the callback is enabled
    if let act = VehicleManager.sharedInstance.managerCallback {
      act.performAction(["status":VehicleManagerStatusMessage.c5CONNECTED.rawValue] as NSDictionary)
      isBleConnected = true
      
    }
  }
  
  
  open func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    vmlog("in centralManager:didFailToConnectPeripheral:")
  }
  
  
  /*  open func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
   vmlog("in centralManager:willRestoreState")
   }
   */
  
  // Core Bluetooth has disconnected from BLE peripheral
  open func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    vmlog("in centralManager:didDisconnectPeripheral:")
    //vmlog(error!)
    let autoOn = UserDefaults.standard.bool(forKey: "autoConnectOn")
    // just reconnect automatically to the same device for now
    if peripheral == openXCPeripheral && autoOn{
      centralManager.connect(openXCPeripheral, options:nil)
      
      // notify client if the callback is enabled
      //      if let act = managerCallback {
      //        act.performAction(["status":VehicleManagerStatusMessage.c5DISCONNECTED.rawValue] as NSDictionary)
      //      }
      
      // clear any saved context
      latestVehicleMeasurements = NSMutableDictionary()
      //latestVehicleMeasurements.removeAll()
      
      // update the connection state
      connectionState  = .connectionInProgress
    }else{
     connectionState = .notConnected
    }
    if let act = VehicleManager.sharedInstance.managerCallback {
      act.performAction(["status":VehicleManagerStatusMessage.c5DISCONNECTED.rawValue] as NSDictionary)
    }
  }
  
  
  // MARK: Peripheral Delgate Function
  
  // Core Bluetooth has discovered services for a peripheral
  open func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    vmlog("in peripheral:didDiscoverServices")
    
    // this isn't our captured openXC peripheral... should never happen
    if peripheral != openXCPeripheral {
      vmlog("peripheral error!")
      return
    }
    
    // scan through all of the available services
    // look for the open XC service
    for service in peripheral.services! {
      vmlog(" - Found service : ",service.uuid)
      
      // uuid matches, we found the service
      if service.uuid.uuidString == OpenXCConstants.C5_OPENXC_BLE_SERVICE_UUID {
        vmlog("   OPENXC_MAIN_SERVICE DETECTED")
        // capture the service
        openXCService = service
        // automatically discover all charateristics for the openXC service
        openXCPeripheral.discoverCharacteristics(nil, for:service)
        
        // notify client if the callback is enabled
        if let act = VehicleManager.sharedInstance.managerCallback {
          act.performAction(["status":VehicleManagerStatusMessage.c5SERVICEFOUND.rawValue] as NSDictionary)
        }
      }
      
    }
  }
  
  
  // Core Bluetooth has discovered characteristics for a service
  open func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
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
      vmlog(" - Found characteristic : ",characteristic.uuid)
      
      // uuid matched on openXC notify characteristic
      if characteristic.uuid.uuidString == OpenXCConstants.C5_OPENXC_BLE_CHARACTERISTIC_NOTIFY_UUID {
        // capture the characteristic
        openXCNotifyChar = characteristic
        // turn on the notification characteristic
        peripheral.setNotifyValue(true, for:characteristic)
        // discover any descriptors for the characteristic
        openXCPeripheral.discoverDescriptors(for: characteristic)
        // notify client if the callback is enabled
        if let act = VehicleManager.sharedInstance.managerCallback {
          act.performAction(["status":VehicleManagerStatusMessage.c5NOTIFYON.rawValue] as NSDictionary)
        }
        // update connection state to indicate that we're fully operational and receiving data
        connectionState = .operational
      }
      
      // uuid matched on openXC notify characteristic
      if characteristic.uuid.uuidString == OpenXCConstants.C5_OPENXC_BLE_CHARACTERISTIC_WRITE_UUID {
        // capture the characteristic
        openXCWriteChar = characteristic
        // discover any descriptors for the characteristic
        openXCPeripheral.discoverDescriptors(for: characteristic)
      }
    }
    
  }
   // Core Bluetooth has cancel peripheral
  open func disconnect() {
    vmlog("VehicleManager disconnecting...")
    centralManager.cancelPeripheralConnection(openXCPeripheral)
    connectionState = .notConnected
    isBleConnected = false
    tempDataBuffer = NSMutableData()
    VehicleManager.sharedInstance.RxDataBuffer = NSMutableData()
    foundOpenXCPeripherals = [String:CBPeripheral]()
    
  }
  
  // Core Bluetooth has data received from a characteristic
  open func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    // vmlog("in peripheral:didUpdateValueForCharacteristic")
    
    // If we have a trace input file enabled, we need to mask any
    // data coming in from BLE. Just ignore the data by returning early.
    if TraceFileManager.sharedInstance.traceFilesourceEnabled {return}
    
    // grab the data from the characteristic
    let data = characteristic.value!
    let returnData = String(data: data, encoding: .utf8)
    print(returnData as Any)
    // if there is actually data, append it to the rx data buffer,
    // and try to parse any messages held in the buffer. The separator
    // in this case is nil because messages arriving from BLE is
    // delineated by null characters
    
   
    if data.count > 0 {
      connectionState = .operational
      if !VehicleManager.sharedInstance.jsonMode{
        VehicleManager.sharedInstance.RxDataBuffer.append(data)
        VehicleManager.sharedInstance.RxDataParser(0x00)
        return
      }
      
      tempDataBuffer.append(data)
      let sepdata = Data(bytes: UnsafePointer<UInt8>([0x00] as [UInt8]), count: 1)
      let rangedata = NSMakeRange(0, tempDataBuffer.length)
      let foundRange = tempDataBuffer.range(of: sepdata, options:[], in:rangedata)
      if foundRange.location != NSNotFound {
        // extract the entire message from the rx data buffer
        VehicleManager.sharedInstance.RxDataBuffer.append(tempDataBuffer.subdata(with: NSMakeRange(0,foundRange.location+1)))
        VehicleManager.sharedInstance.RxDataParser(0x00)
        // tempDataBuffer.resetBytes(in:NSMakeRange(0,foundRange.location))
        // if there is leftover data in the buffer, make sure to keep it otherwise
        // the parsing will not work for the next message that is partially complete now
        if tempDataBuffer.length-1 > foundRange.location {
          tempDataBuffer.resetBytes(in:NSMakeRange(0,foundRange.location+1))
          let data_left : NSMutableData = NSMutableData()
          data_left.append(tempDataBuffer.subdata(with: NSMakeRange(foundRange.location+1,tempDataBuffer.length-foundRange.location-1)))
          tempDataBuffer = data_left
        } else {
          tempDataBuffer = NSMutableData()
        }
      }
      //if data.count > 0 {
      //RxDataBuffer.append(data)
      // RxDataParser(0x00)
    }
    
  }
  
  
  // Core Bluetooth has discovered a description for a characteristic
  // don't need to save or use it in this case
  open func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
    vmlog("in peripheral:didDiscoverDescriptorsForCharacteristic")
    vmlog(characteristic.descriptors as Any)
  }
  
  
  open func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
    vmlog("in peripheral:didUpdateValueForDescriptor")
  }
  
  
  open func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    vmlog("in peripheral:didUpdateNotificationStateForCharacteristic")
  }
  
  
  open func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
    vmlog("in peripheral:didModifyServices")
  }
  
  
  open func peripheral(_ peripheral: CBPeripheral, didDiscoverIncludedServicesFor service: CBService, error: Error?) {
    vmlog("in peripheral:didDiscoverIncludedServicesForService")
  }
  
  // Core Bluetooth has written a value to a characteristic
  open func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
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
    Thread.sleep(forTimeInterval: 0.05)
    // Decrement the tx write semaphone, indicating that we have received acknowledgement
    // for sending one chunk of data
    BLETxWriteCount -= 1
    // Call the BLESendFunction again, in case this is the last chunk of data acknowledged for
    // a message, and we have another message queued up in the buffer. If this is not the last chunk
    // for this message (tx write semaphore>0) or there aren't any other messages queued
    // (tx buffer count==0), then the BLESendFunction returns immediately
    BLESendFunction()
  }
  
  
  // common function called whenever any messages need to be sent over BLE
  //ranjan changed fileprivate to public due to travis fail
  public func BLESendFunction() {
    
    
    var sendBytes: Data
    
    // Check to see if the tx buffer is actually empty.
    // We need to do this because this function can be called as BLE notifications are
    // received because we may have queued up some messages to send.
    if VehicleManager.sharedInstance.BLETxDataBuffer.count == 0 {
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
    
    if(isBleConnected){
      // take the message to send from the head of the tx buffer queue
      var cmdToSend : NSData = VehicleManager.sharedInstance.BLETxDataBuffer[0] as! NSData
      vmlog("cmdToSend:",cmdToSend)
      let datastring = NSString(data: (cmdToSend as NSData) as Data, encoding:String.Encoding.utf8.rawValue)
      vmlog("datastring:",datastring as Any)
      
      // we can only send 20B at a time in BLE
      let rangedata = NSMakeRange(0, 20)
      // loop through and send 20B at a time, make sure to handle <20B in the last send.
      while cmdToSend.length > 0 {
        if (cmdToSend.length<=20) {
          vmlog("cmdToSend if length < 20:",cmdToSend)
          sendBytes = cmdToSend as Data
          vmlog("sendBytes if length < 20:",sendBytes)
          
          let try2Str = NSString(data: (sendBytes as NSData) as Data, encoding:String.Encoding.utf8.rawValue)
          vmlog("try2Str....:",try2Str as Any)
          
          
          cmdToSend = NSMutableData()
        } else {
          sendBytes = cmdToSend.subdata(with: rangedata)
          vmlog("20B chunks....:",sendBytes)
          
          let try1Str = NSString(data: (sendBytes as NSData) as Data, encoding:String.Encoding.utf8.rawValue)
          vmlog("try1Str....:",try1Str as Any)
          
          let leftdata = NSMakeRange(20,cmdToSend.length-20)
          cmdToSend = NSData(data: cmdToSend.subdata(with: leftdata))
          
        }
        // write the byte chunk to the VI
        openXCPeripheral.writeValue(sendBytes, for: openXCWriteChar, type: CBCharacteristicWriteType.withResponse)
        // increment the tx write semaphore
        BLETxWriteCount += 1
        
        
      }
    }
    
    // remove the message from the tx buffer queue once all parts of it have been sent
    VehicleManager.sharedInstance.BLETxDataBuffer.removeObject(at: 0)
    
  }
  open func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?) {
    vmlog("in peripheral:didWriteValueForDescriptor")
  }
  
  
  open func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
    vmlog("in peripheral:didReadRSSI")
  }
  
  
  
}
