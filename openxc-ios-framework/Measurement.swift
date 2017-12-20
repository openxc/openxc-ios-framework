//
//  Measurement.swift
//  openxc-ios-framework
//
//  Created by Kanishka, Vedi (V.) on 28/06/17.
//  Copyright © 2017 Ford Motor Company. All rights reserved.
//

import Foundation


open class VehicleMeasurementResponse : VehicleBaseMessage {
    override init() {
        value = NSNull()
        event = NSNull()
        super.init()
        type = .measurementResponse
    }
    open var name : NSString = ""
    open var value : AnyObject
    open var isEvented : Bool = false
    open var event : AnyObject
    override func traceOutput() -> NSString {
        var out : String = ""
        if value is String {
            out = "{\"timestamp\":\(timestamp),\"name\":\"\(name)\",\"value\":\"\(value)\""
        } else {
            out = "{\"timestamp\":\(timestamp),\"name\":\"\(name)\",\"value\":\(value)"
        }
        if isEvented {
            if event is String {
                out.append(",\"event\":\"\(event)\"")
            } else {
                out.append(",\"event\":\(event)")
            }
        }
        out.append("}")
        return out as NSString
    }
    open func valueIsBool() -> Bool {
        if value is NSNumber {
            let nv = value as! NSNumber
            if nv.isEqual(to: NSNumber(value: true as Bool)) {
                return true
            } else if nv.isEqual(to: NSNumber(value: false as Bool)) {
                return true
            }
        }
        return false
    }
}
