//
//  NetworkDataTest.swift
//  openXCiOSFrameworkTests
//
//  Created by Ranjan, Kumar sahu (K.) on 22/01/18.
//  Copyright © 2018 Ford Motor Company. All rights reserved.
//

import XCTest
@testable import openXCiOSFramework

class NetworkDataTest: XCTestCase {
    
    var valueIs : Bool = false
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    /*
    //Test the Socket network connection
    func testSocketConnection() {
        NetworkData.sharedInstance.connect(ip:"0.0.0.0", portvalue: 50001, completionHandler: { (success) in
            
            self.valueIs = success
        })
        
        XCTAssert(valueIs)
    }*/
    
}
