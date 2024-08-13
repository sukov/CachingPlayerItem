Pod::Spec.new do |s|
  s.name             = 'CachingPlayerItem'
  s.version          = '1.1.1'
  s.summary          = 'Cache & Play audio and video files'

  s.homepage         = 'https://github.com/sukov/CachingPlayerItem'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'sukov' => 'gorjan5@hotmail.com' }
  s.source           = { :git => 'https://github.com/sukov/CachingPlayerItem.git', :tag => s.version.to_s }

  s.swift_version = '5.0'
  s.ios.deployment_target = '10.0'

  s.source_files = 'Source/*.swift'

  s.frameworks = 'Foundation', 'AVFoundation'
end
