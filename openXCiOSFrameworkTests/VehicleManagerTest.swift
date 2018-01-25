//
//  VehicleManagerTest.swift
//  openXCiOSFrameworkTests
//
//  Created by Ranjan, Kumar sahu (K.) on 22/01/18.
//  Copyright © 2018 Ford Motor Company. All rights reserved.
//

import XCTest
@testable import openXCiOSFramework

class VehicleManagerTest: XCTestCase {
    
    
    var scanValueIs : Bool = false
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
    //Vehicle manager Trace file sink test method
    func testEnableTraceFileSink(){
        let value = VehicleManager.sharedInstance.enableTraceFileSink("user/path/.Aiims.txt")
        XCTAssert(value)
    }
    //Vehicle manager trace filr source  test method
    func testEnableTraceFileSource(){
        let value = VehicleManager.sharedInstance.enableTraceFileSource("user/path/.Aiims.txt", speed: 60)
        XCTAssert(value)
    }
    //Vehicle manager Measurement  test method
    func testgetLatestMeasurement(){
        let value = VehicleManager.sharedInstance.getLatest("Version")
        XCTAssertNil(value)
    }
    //Vehicle manager Command Request test method
    func testSendCommand(){
        
        // let value = VehicleManager.sharedInstance.sendCommand(<#T##cmd: VehicleCommandRequest##VehicleCommandRequest#>, target: <#T##T#>, action: <#T##(T) -> (NSDictionary) -> ()#>)
        //XCTAssert(value == "")
    }
    //Vehicle manager Diagnostic Request test method
    func testSendDiagReq(){
        //let value = VehicleManager.sharedInstance.sendDiagReq(<#T##cmd: VehicleDiagnosticRequest##VehicleDiagnosticRequest#>, target: <#T##T#>, cmdaction: <#T##(T) -> (NSDictionary) -> ()#>)
         //XCTAssert(value == "")
    }
    
    func  testManagerCallBack () {
        //VehicleManager.sharedInstance.setManagerCallbackTarget(<#T##target: T##T#>, action: <#T##(T) -> (NSDictionary) -> ()#>)
       // VehicleManager.managerCallback
       // XCTAssert()
    }
    
    func testsetManagerDebug (){
        //VehicleManager.sharedInstance.setManagerDebug(true)
       // XCTAssert(VehicleManager.sharedInstance.managerDebug)
    }
    
    func  testAutoConnect() {
        VehicleManager.sharedInstance.setAutoconnect(true)
        XCTAssert(VehicleManager.sharedInstance.autoConnectPeripheral)
    }
    
    func testdiscoveredVI(){
       // let value =VehicleManager.sharedInstance.discoveredVI()
       // XCTAssert(value == "")
    }
    func testScanVi{
        VehicleManager.sharedInstance.scan { (success) in
            scanValueIs = success
        }
        XCTAssert(scanValueIs)
    }
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
}
