//
//  Diagnostic.swift
//  openxc-ios-framework
//
//  Created by Kanishka, Vedi (V.) on 28/06/17.
//  Copyright © 2017 Ford Motor Company. All rights reserved.
//

import Foundation


open class VehicleDiagnosticRequest : VehicleBaseMessage {
    public override init() {
        super.init()
        type = .diagnosticRequest
    }
    open var bus : NSInteger = 0
    open var message_id : NSInteger = 0
    open var mode : NSInteger = 0
    open var pid : NSInteger?
    open var payload : NSString = ""
    open var name : NSString = ""
    open var multiple_responses : Bool = false
    open var frequency : NSInteger = 0
    open var decoded_type : NSString = ""
    open var timeStamp: NSInteger = 0
}



open class VehicleDiagnosticResponse : VehicleBaseMessage {
    public override init() {
        super.init()
        type = .diagnosticResponse
    }
    open var bus : NSInteger = 0
    open var message_id : NSInteger = 0
    open var mode : NSInteger = 0
    open var pid : NSInteger?
    open var success : Bool = false
    open var negative_response_code : NSInteger = 0
    open var payload : NSString = ""
    open var value : NSInteger?
    open var timeStamp: NSInteger = 0
}
