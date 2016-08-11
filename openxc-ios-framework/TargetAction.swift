//
//  TargetAction.swift
//  openxc-ios-framework
//
//  Created by Tim Buick on 2016-08-10.
//  Copyright © 2016 Bug Labs. All rights reserved.
//

import Foundation




protocol TargetAction {
  func performAction(rsp:NSDictionary)
  func returnKey() -> NSString
}

struct TargetActionWrapper<T: AnyObject> : TargetAction {
  var key : NSString
  weak var target: T?
  let action: (T) -> (NSDictionary) -> ()
  
  func performAction(rsp:NSDictionary) -> () {
    if let t = target {
      action(t)(rsp)
    }
  }
  func returnKey() -> NSString {
    return key
  }
}


