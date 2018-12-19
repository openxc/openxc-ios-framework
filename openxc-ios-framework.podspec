#
# Be sure to run `pod lib lint openxc-ios-framework.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'openxc-ios-framework'
  s.version          = '1.0.0'
  s.summary          = 'openxc-ios-framework is API to car .Which provide can signals'
  s.swift_version    = '3.2'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
openxc-ios-framework is API to car .Which provide can signals
                       DESC

  s.homepage         = 'https://github.com/kranjan/openxc-ios-framework'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'ranjan sahu' => 'kranjan@ford.com' }
  s.source           = { :git => 'https://github.com/kranjan/openxc-ios-framework.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '8.0'

  s.source_files = 'openxc-ios-framework/Classes/**/*'
  
  # s.resource_bundles = {
  #   'openxc-ios-framework' => ['openxc-ios-framework/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'AFNetworking', '~> 2.3'
end
