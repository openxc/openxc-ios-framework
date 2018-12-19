//
//  TargetAction.swift
//  openxc-ios-framework
//
//  Created by Tim Buick on 2016-08-10.
//  Copyright (c) 2016 Ford Motor Company Licensed under the BSD license.
//  Version 0.9.2
//

import Foundation


// This TargetAction protocol allows for Swift to have callback methods.
// The TargetActionWrapper keeps a 'key' that can be used to identify
// a specific TargetAction object if more than one is present. It keeps
// a 'target', which is a pointer to an existing class object, for example, to
// the ViewController that contains the callback. The variable 'action' is the
// actual callback method that always must have an NSDictionary as a parameter.
// The NSDictionary parameter can hold anything required for the callback
// method.


protocol TargetAction {
  func performAction(_ rsp:NSDictionary)
  func returnKey() -> NSString
}

struct TargetActionWrapper<T: AnyObject> : TargetAction {
  var key : NSString
  weak var target: T?
  let action: (T) -> (NSDictionary) -> ()
  
  func performAction(_ rsp:NSDictionary) -> () {
    if let t = target {
      action(t)(rsp)
    }
  }
  func returnKey() -> NSString {
    return key
  }
}


