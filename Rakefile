require 'rubygems'
require 'bundler' 
Bundler.setup
require 'xctasks/test_task'

XCTasks::TestTask.new do |t|
  t.workspace = 'CocoaSPDY.xcworkspace'
  t.schemes_dir = 'SPDYUnitTests/Schemes'
  t.runner = :xcpretty
  t.subtasks = { ios: 'CocoaSPDYTests' }
end
