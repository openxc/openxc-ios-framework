//
//  CAN.swift
//  openxc-ios-framework
//
//  Created by Kanishka, Vedi (V.) on 28/06/17.
//  Copyright © 2017 Ford Motor Company. All rights reserved.
//

import Foundation

open class VehicleCanResponse : VehicleBaseMessage {
    public override init() {
        super.init()
        type = .canResponse
    }
    open var bus : NSInteger = 0
    open var id : NSInteger = 0
    open var data : NSString = ""
    open var format : NSString = "standard"
}

open class VehicleCanRequest : VehicleBaseMessage {
    public override init() {
        super.init()
        type = .canRequest
    }
    open var bus : NSInteger = 0
    open var id : NSInteger = 0
    open var data : NSString = ""
    open var format : NSString = ""
}
