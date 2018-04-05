//
//  NetworkData.swift
//  openxc-ios-framework
//
//  Created by Ranjan, Kumar sahu (K.) on 08/01/18.
//  Copyright © 2018 Ford Motor Company. All rights reserved.
//

import UIKit
import ExternalAccessory

open class NetworkData: NSObject ,StreamDelegate {
    
    
    static let sharedNetwork = NetworkData()
    private var inputstream:  InputStream?
    private var outputstream: OutputStream?
    private var connecting:Bool
    var host: String?
    var port: Int?
    var theData : UInt8!
    var callbackHandler: ((Bool) -> ())?  = nil
    
    // Initialization
    static open let sharedInstance: NetworkData = {
        let instance = NetworkData()
        return instance
    }()
    fileprivate override init() {
        connecting = false
    }
    open func connect(ip:String, portvalue:Int, completionHandler: @escaping (_ success: Bool) -> ()) {
        host = ip
        port = portvalue
        self.callbackHandler = completionHandler
        Stream.getStreamsToHost(withName: host!, port: port!,inputStream: &inputstream, outputStream: &outputstream)
        
        //here we are going to calling a delegate function
        inputstream?.delegate = self
        outputstream?.delegate = self
        
        inputstream?.schedule(in: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
        outputstream?.schedule(in: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
        
        inputstream?.open()
        
        if ((outputstream?.open()) != nil){
            // print("connected")
            
        }else{
            //print("not connected")
            VehicleManager.sharedInstance.isNetworkConnected = false
        }
    }
    
    open func disconnectConnection(){
        inputstream?.close()
        outputstream?.close()
    }
    
    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        
        switch (eventCode)
        {
        case Stream.Event.openCompleted:
            
            if(aStream == outputstream)
            {
                print("output:OutPutStream opened")
            }
            print("Input = openCompleted")
            break
        case Stream.Event.errorOccurred:
            if(aStream == outputstream)
            {
                self.callbackHandler!(false)
                print("output:Error Occurred\n")
                VehicleManager.sharedInstance.isNetworkConnected = false
            }
            print("Input : Error Occurred\n")
            break
            
        case Stream.Event.endEncountered:
            if(aStream == outputstream)
            {
                print("output:endEncountered\n")
            }
            print("Input = endEncountered\n")
            break
            
        case Stream.Event.hasSpaceAvailable:
            if(aStream == outputstream)
            {
                print("output:hasSpaceAvailable\n")
                //self.callbackHandler!(false)
            }
            print("Input = hasSpaceAvailable\n")
            break
            
        case Stream.Event.hasBytesAvailable:
            
            
            VehicleManager.sharedInstance.isNetworkConnected = true
            self.callbackHandler!(true)
            
            if(aStream == outputstream)
            {
                print("output:hasBytesAvailable\n")
            }
            if aStream == inputstream
            {
                var buffer = [UInt8](repeating:0, count:20)
                while (self.inputstream!.hasBytesAvailable)
                {
                    let len = inputstream!.read(&buffer, maxLength: buffer.count)
                    
                    // If read bytes are less than 0 -> error
                    if len < 0
                    {
                        let error = self.inputstream!.streamError
                        print("Input stream has less than 0 bytes\(error!)")
                        //closeNetworkCommunication()
                    }
                        
                        // If read bytes equal 0 -> close connection
                    else if len == 0
                    {
                        print("Input stream has 0 bytes")
                        // closeNetworkCommunication()
                    }
                    
                    if(len > 0)
                        //here it will check it out for the data sending from the server if it is greater than 0 means if there is a data means it will write
                    {
                        let messageFromServer = NSString(bytes: &buffer, length: buffer.count, encoding: String.Encoding.utf8.rawValue)
                        let  msgdata = Data(bytes:buffer)
                        
                        print("\(msgdata)")
                        if msgdata.count > 0 {
                            VehicleManager.sharedInstance.RxDataBuffer.append(msgdata)
                            VehicleManager.sharedInstance.RxDataParser(0x00)
                        }
                        
                        if messageFromServer == nil
                        {
                            print("Network hasbeen closed")
                        }
                        else
                        {
                            print("MessageFromServer = \(String(describing: messageFromServer))")
                            
                        }
                    }
                }
            }
            
            break
            
        default:
            print("default block")
            
        }
        
    }
}
