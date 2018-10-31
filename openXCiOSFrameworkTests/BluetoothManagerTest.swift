//
//  BluetoothManagerTest.swift
//  openXCiOSFrameworkTests
//
//  Created by Ranjan, Kumar sahu (K.) on 29/10/18.
//  Copyright © 2018 Ford Motor Company. All rights reserved.
//

import XCTest
@testable import openXCiOSFramework
class BluetoothManagerTest: XCTestCase {
    
  var scanValueIs : Bool = false
  var sucessValueIs : Bool = true
  
  override func setUp() {
    super.setUp()
    // Put setup code here. This method is called before the invocation of each test method in the class.
  }
  
  override func tearDown() {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    super.tearDown()
  }
  func  testAutoConnect() {
    
    BluetoothManager.sharedInstance.setAutoconnect(true)
    let value = BluetoothManager.sharedInstance.autoConnectPeripheral
    XCTAssert(value)
  }
  
//  func testScanVi() {
//    
//    BluetoothManager.sharedInstance.scan { (success) in
//      if(!success){
//        self.scanValueIs = true
//      }else{
//        self.scanValueIs = true
//      }
//    }
//    XCTAssert(scanValueIs)
//  }
  
//  func testdiscoveredVI() {
//    let value = BluetoothManager.sharedInstance.discoveredVI()
//
//    XCTAssert(value == "OPENXC-VI-6C9B")
//
//  }
  func testExample() {
    // This is an example of a functional test case.
    // Use XCTAssert and related functions to verify your tests produce the correct results.
  }
  
}
