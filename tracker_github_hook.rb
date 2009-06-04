#!/usr/bin/env ruby
#
# GitHub Post-Receive hook handler to add comments, and update state in Pivotal Tracker
# Configure your Tracker API key, and Project ID in a config.yml file placed in the
# same directory as this app.
# When you make commits to Git/GitHub, and want a comment and optionally a state update
# made to Tracker, add the following syntax to your commit message:
#     
#     [Story#####]
# or
#     [Story##### state:finished]
#

require 'rubygems'
require 'sinatra'
require 'json'
require 'rest_client'
require 'yaml'


# load up configuration from YAML file
configure do
  begin
    config = open(File.expand_path(File.dirname(__FILE__) + '/config.yml')) { |f| YAML.load(f) }
    
    PROJECTS = Hash.new
    config.each do |project|
      raise "required configuration settings not found" unless project[1]['tracker_api_token'] && project[1]['tracker_project_id']    
      PROJECTS[project[1]['github_url']] = { :api_token => project[1]['tracker_api_token'], :project_id => project[1]['tracker_project_id']}
    end
  rescue => e
    puts "Failed to startup: #{e.message}"
    puts "Ensure you have a config.yml in this directory with the'tracker_api_token' and 'tracker_project_id' keys/values set."
    exit(-1)
  end
end

# example payload (json): {"after":"88e947d8d342b69638df47bf372fc2612f24dd19","ref":"refs\/heads\/master","repository":{"owner":{"name":"apinstein","email":"apinstein@mac.com"},"description":"","forks":0,"name":"neybor","private":true,"url":"http:\/\/github.com\/apinstein\/neybor","fork":false,"watchers":3,"homepage":""},"before":"ed06823f0b08b80586a1431409c590aaa41ca4f9","commits":[{"removed":[],"modified":["classes\/syndication\/Trulia.php","classes\/syndication\/test\/HotPadsSyndicatorTest.php","classes\/syndication\/test\/TruliaSyndicatorTest.php"],"added":[],"url":"http:\/\/github.com\/apinstein\/neybor\/commit\/fb8ee7d321db5ccf22808fde51eeecaa1b047a44","timestamp":"2009-06-03T11:22:22-07:00","message":"Merge conflicting changes from file rname and git-svn cross-updating","author":{"name":"Alan Pinstein","email":"apinstein@mac.com"},"id":"fb8ee7d321db5ccf22808fde51eeecaa1b047a44"},{"removed":[],"modified":["README"],"added":[],"url":"http:\/\/github.com\/apinstein\/neybor\/commit\/88e947d8d342b69638df47bf372fc2612f24dd19","timestamp":"2009-06-03T11:33:56-07:00","message":"[Story762537 state:finished] more pivotal-github testing","author":{"name":"Alan Pinstein","email":"apinstein@mac.com"},"id":"88e947d8d342b69638df47bf372fc2612f24dd19"}]}

# The handler for the GitHub post-receive hook
post '/' do
  @num_commits = 0
  push = JSON.parse(params[:payload])
  tracker_info = PROJECTS[push['repository']['url']]
  raise "GitHub Webook triggerd for repo: #{push['repository']['url']}; no matching github_url in config.yml" if tracker_info == nil
  push['commits'].each { |commit| process_commit(tracker_info, commit) }
  "Processed #{@num_commits} commits for stories"
end

get '/' do
    "Have your github webhook point here; bridge works automatically via POST"
end

  
helpers do
  def process_commit(tracker_info, commit)
    # get commit message
    message = commit['message']

    # see if there is a Tracker story trigger, and if so, get story ID
    tracker_trigger = message.match(/\[Story(\d+)(.*)\]/)
    if tracker_trigger
      @num_commits += 1
      story_id = tracker_trigger[1]

      # post comment to the story
      RestClient.post(create_api_url(tracker_info[:project_id], story_id, '/notes'),
                      "<note><text>(from [#{commit['id']}]) #{message}</text></note>", 
                      tracker_api_headers(tracker_info[:api_token]))
    
      # See if we have a state change
      state = tracker_trigger[2].match(/.*state:(\s?\w+).*/)
      if state
        state = state[1].strip

        RestClient.put(create_api_url(tracker_info[:project_id], story_id), 
                       "<story><current_state>#{state}</current_state></story>", 
                       tracker_api_headers(tracker_info[:api_token]))
      end     
    end
  end

  def create_api_url(project_id, story_id, extra_path_elemets='')
    "http://www.pivotaltracker.com/services/v1/projects/#{project_id}/stories/#{story_id}#{extra_path_elemets}"
  end
  
  def tracker_api_headers(api_token)
    { 'X-TrackerToken' => api_token, 'Content-type' => 'application/xml' }
  end

end
