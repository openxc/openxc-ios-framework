//
//  TraceFileManagerTest.swift
//  openXCiOSFrameworkTests
//
//  Created by Ranjan, Kumar sahu (K.) on 29/10/18.
//  Copyright © 2018 Ford Motor Company. All rights reserved.
//

import XCTest

class TraceFileManagerTest: XCTestCase {
    
  let traceFileSinkPath : NSString = "1.json"
  let traceFileSourcePath : NSString = "2.json"
  var scanValueIs : Bool = false`
  var sucessValueIs : Bool = true
  var measurmentObj:VehicleMeasurementResponse!
  override func setUp() {
    /*
     traceOutput
     valueIsBool
     getLatest
     getMesurementUnit
     */
    
    super.setUp()
    measurmentObj = VehicleMeasurementResponse()
    // Put setup code here. This method is called before the invocation of each test method in the class.
  }
  
  override func tearDown() {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    super.tearDown()
  }
  //  func testTraceOutput(){
  //    let value = measurmentObj.traceOutput()
  //    XCTAssertEqual(value, "null")
  //  }
  func testValueisBool(){
    let value = measurmentObj.valueIsBool()
    XCTAssert(!value)
  }
  //Vehicle manager Trace file sink test method
  func testEnableTraceFileSink(){
    let value = TraceFileManager.sharedInstance.enableTraceFileSink(self.traceFileSinkPath)
    if let fs : Bool? = Bundle.main.infoDictionary?["UIFileSharingEnabled"] as? Bool{
      XCTAssert(!value)
    }else{
      XCTAssert(value)
    }
  }
  //Vehicle manager trace filr source  test method
  func testEnableTraceFileSource(){
    let value = TraceFileManager.sharedInstance.enableTraceFileSource( self.traceFileSourcePath, speed:60)
    if let fs : Bool? = Bundle.main.infoDictionary?["UIFileSharingEnabled"] as? Bool{
      XCTAssert(!value )
    }else{
      XCTAssert(value )
    }
  }
  
  
  
  func testExample() {
    // This is an example of a functional test case.
    // Use XCTAssert and related functions to verify your tests produce the correct results.
  }
  
  func testPerformanceExample() {
    // This is an example of a performance test case.
    self.measure {
      // Put the code you want to measure the time of here.
    }
  }
    
}
