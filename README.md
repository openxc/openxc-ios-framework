# OpenXC-iOS-Framework
This framework is part of the OpenXC project. This iOS framework contains the tools required to read vehicle data from the vehicle's CAN bus through the OpenXC vehicle interface in any iOS application.

OpenXC iOS framework for use with the C5 BLE device. See also the [openxc-ios-app-demo](https://github.com/openxc/openxc-ios-app-demo)

##Supported versions:
* iOS - upto 9.3
* XCode - upto 7.3.1
* Swift - Swift2

## Using the Framework
The framework can be picked directlt from the releases
* Simulator build - openXCiOSFramework.framework.simulator.zip, ProtocolBuffers.framework.simulator.zip
* Device build - openXCiOSFramework.framework.device.zip, ProtocolBuffers.framework.device.zip

## Building from XCode

Make sure you have XCode7 installed with iOS 9 to build it from XCode. This framework must be included in any iOS application that needs to connect to a VI

Refer to this [document](https://github.com/openxc/openxc-ios-framework/blob/master/OpenXC_iOS_Document.docx) for more details on installation and usage.

API usage details are available [here](https://github.com/openxc/openxc-ios-framework/blob/master/iOS%20Framework%20API%20Guide.pdf). 

Also see [Step by Step Guide] (https://github.com/openxc/openxc-ios-framework/blob/master/StepsToBuildOpenXCiOSFrameworkAndDemoApp.docx) to build framework. 


## Tests
* to be added


## Building from Command Line
The project requires XCode, XCode command line tools installed. 

To install XCode command line tools, follow these steps for XCode7:

* Launch XCode
* Go to Preferences - Locations - Command Line Tools - Install


## Releasing the App and Library

* Update CHANGELOG.mkd
* Merge into master push to GitHub
* Travis CI will take care of the rest.



## Contributing

Please see our [Contribution Documents] (https://github.com/openxc/openxc-ios-framework/blob/master/CONTRIBUTING.mkd)

## License
Copyright (c) 2016 Ford Motor Company
Licensed under the BSD license.
