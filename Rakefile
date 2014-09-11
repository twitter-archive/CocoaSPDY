require 'rubygems'
require 'bundler' 
Bundler.setup
require 'xctasks/test_task'
require 'erb'
require 'highline/import'

XCTasks::TestTask.new do |t|
  t.workspace = 'CocoaSPDY.xcworkspace'
  t.schemes_dir = 'SPDYUnitTests/Schemes'
  t.runner = :xcpretty
  t.subtasks = { ios: 'CocoaSPDYTests' }
end

class PodRelease
  attr_accessor :name, :version, :tag
  
  def initialize(options = {})
    options.each { |k,v| self.send("#{k}=", v) }
  end
  
  def filename
    "#{name}.podspec"
  end
  
  def get_binding
    binding
  end
end

desc "Tag a new release of CocoaSPDY-Layer"
task :release do
  current_branch = `git symbolic-ref --short HEAD`.chomp
  fail "Release can only be tagged from `master` or `layer`" unless %w{layer master}.include?(current_branch)
  version = Time.now.strftime('%Y%m%d%H%M%S%3N').to_i
  pod_release = PodRelease.new(name: 'CocoaSPDY-Layer', version: version, tag: version)
  
  erb = ERB.new(File.read(File.join(File.dirname(__FILE__), '.podspec.erb')))
  File.open(pod_release.filename, 'w+') { |f| f << erb.result(pod_release.get_binding) }
  say "Wrote podspec version #{pod_release.version} to #{pod_release.filename}"
  system("git add #{pod_release.filename}")
  response = ask("Review diff?  (y/n)  ") { |q| q.in = %w{y n} }
  system "git diff --cached" if response == 'y'
  response = ask("Commit changes?  (y/n)  ") { |q| q.in = %w{y n} }
  system "git commit -m 'Updated podspec to #{version}'" if response == 'y'
  response = ask("Tag release?  (y/n)  ") { |q| q.in = %w{y n} }
  system "git tag #{version}" if response == 'y'
  response = ask("Push release?  (y/n)  ") { |q| q.in = %w{y n} }
  if response == 'y'
    system "git push origin #{current_branch} --tags"
    if $?.exitstatus.zero?
      puts "Executing `pod repo push layer #{pod_release.filename}`"
      Bundler.with_clean_env { system "pod repo push layer #{pod_release.filename}" }
    end
  end
end
