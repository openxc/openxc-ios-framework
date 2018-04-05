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
    
    var traceFileSinkPath : NSString = "1.json"
    var traceFileSourcePath : NSString = "2.json"
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
    
  
    //Vehicle manager Trace file sink test method
    func testEnableTraceFileSink(){
        let value = VehicleManager.sharedInstance.enableTraceFileSink( self.traceFileSinkPath)
        if let fs : Bool? = Bundle.main.infoDictionary?["UIFileSharingEnabled"] as? Bool{
        XCTAssert(!value)
        }else{
            XCTAssert(value)
        }
    }
    //Vehicle manager trace filr source  test method
    func testEnableTraceFileSource(){
        let value = VehicleManager.sharedInstance.enableTraceFileSource( self.traceFileSourcePath, speedOrNil:60)
        if let fs : Bool? = Bundle.main.infoDictionary?["UIFileSharingEnabled"] as? Bool{
        XCTAssert(!value )
        }else{
            XCTAssert(value )
        }
  }
 
    
    func  testAutoConnect() {
        VehicleManager.sharedInstance.setAutoconnect(true)
        XCTAssert(VehicleManager.sharedInstance.autoConnectPeripheral)
    }
    
//    func testScanVi{
//        VehicleManager.sharedInstance.scan { (success) in
//            if(!success){
//            self.scanValueIs = sucessValueIs
//            }else{
//                self.scanValueIs = success
//            }
//        }
//        XCTAssert(scanValueIs)
//    }
    //    func testdiscoveredVI(){
    //        let value =VehicleManager.sharedInstance.discoveredVI()
    //
    //        XCTAssert(value == "OPENXC-VI-6C9B")
    //    }

    //Vehicle manager Command Request test method
//    func testSendCommand(){
//
//     let value = VehicleManager.sharedInstance.sendCommand(<#T##cmd: VehicleCommandRequest##VehicleCommandRequest#>, target: <#T##T#>, action: <#T##(T) -> (NSDictionary) -> ()#>)
//    XCTAssert(value == "")
//     }
    //Vehicle manager Diagnostic Request test method
//    func testSendDiagReq(){
//    let value = VehicleManager.sharedInstance.sendDiagReq(<#T##cmd: VehicleDiagnosticRequest##VehicleDiagnosticRequest#>, target: <#T##T#>, cmdaction: <#T##(T) -> (NSDictionary) -> ()#>)
//    XCTAssert(value == "")
//     }
}
