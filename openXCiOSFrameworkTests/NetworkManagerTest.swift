//
//  NetworkManagerTest.swift
//  openXCiOSFrameworkTests
//
//  Created by Ranjan, Kumar sahu (K.) on 31/10/18.
//  Copyright © 2018 Ford Motor Company. All rights reserved.
//

import XCTest
@testable import openXCiOSFramework

class NetworkManagerTest: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }
  /*
   //Test the Socket network connection
   func testSocketConnection() {
   NetworkData.sharedInstance.connect(ip:"0.0.0.0", portvalue: 50001, completionHandler: { (success) in
   
   self.valueIs = success
   })
   
   XCTAssert(valueIs)
   }*/
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
}
