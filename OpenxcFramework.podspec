#
#  Be sure to run `pod spec lint OpenxcFramework.podspec.podspec' to ensure this is a
#  valid spec and to remove all comments including this before submitting the spec.
#
#  To learn more about Podspec attributes see https://docs.cocoapods.org/specification.html
#  To see working Podspecs in the CocoaPods repo see https://github.com/CocoaPods/Specs/
#

Pod::Spec.new do |s|
  s.name         = "OpenXCFramework-Swift"
  s.version      = "0.01"
  s.summary      = "OpenXC for Swift"
  s.homepage     = "http://openxcplatform.com/"
  s.license      = "Ford"
  s.documentation_url = "https://github.com/openxc/openxc-ios-framework.git"
  s.license      = { :type => 'Apache License, Version 2.0', :text =>
    <<-LICENSE
    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at
    http://www.apache.org/licenses/LICENSE-2.0
    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
    Copyright 2008 Google Inc.
    LICENSE
  }

  s.author       = { "Ranjan kumar sahu" => "kranjan@ford.com" }
  s.authors      = { "Ranjan kumar sahu" => "kranjan@ford.com" }

  s.ios.deployment_target = '8.0'
  s.osx.deployment_target = '10.10'
  s.watchos.deployment_target = '2.0'
  s.tvos.deployment_target = '9.0'

  s.module_name = "OpenXCFramework"
  s.source       = { :git => 'https://github.com/openxc/openxc-ios-framework.git', :branch => s.version }
  s.source_files = 'Source/*.{swift}'
  s.requires_arc = true
  s.frameworks   = 'Foundation'
end
