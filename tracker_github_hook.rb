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


Sinatra::Application.default_options.merge!(
  :run => true,
  :env => :production,
  :raise_errors => true
)

TRACKER_HOST = 'www.pivotaltracker.com'


# load up configuration from YAML file
configure do
  begin
    config = open(File.expand_path(File.dirname(__FILE__) + '/config.yml')) { |f| YAML.load(f) }

    TRACKER_API_TOKEN = config['tracker_api_token']
    TRACKER_PROJECT_ID = config['tracker_project_id']

    raise "required configuration settings not found" unless TRACKER_API_TOKEN && TRACKER_PROJECT_ID    
  rescue => e
    puts "Failed to startup: #{e.message}"
    puts "Ensure you have a config.yml in this directory with the'tracker_api_token' and 'tracker_project_id' keys/values set."
    exit(-1)
  end
end


# The handler for the GitHub post-receive hook
post '/' do
  push = JSON.parse(params[:payload])
  push['commits'].each { |commit| process_commit(commit) }
  num_commits = push['commits'].length
  "Processed #{num_commits} commits"
end

  
helpers do
  def process_commit(commit)
    # get commit message
    message = commit['message']
  
    # see if there is a Tracker story trigger, and if so, get story ID
    tracker_trigger = message.match(/\[Story(\d+)(.*)\]/)
    if tracker_trigger
      story_id = tracker_trigger[1]
    
      # post comment to the story
      post_tracker_comment(story_id, commit['id'], message)
    
      # See if we have a state change
      state = tracker_trigger[2].match(/.*state:(\s?\w+).*/)
      if state
        state = state[1]
        state.strip!
 
        change_tracker_story_state(story_id, state)
      end     
    end
  end

  def post_tracker_comment(story_id, commit_id, comment)
    RestClient.post(create_api_url(story_id, '/notes'),
                    "<note><text>(from [#{commit_id}]) #{comment}</text></note>", 
                    tracker_api_headers)
  end

  def change_tracker_story_state(story_id, state)
    RestClient.put(create_api_url(story_id), 
                   "<story><current_state>#{state}</current_state></story>", 
                   tracker_api_headers)
  end
  
  def create_api_url(story_id, extra_path_elemets='')
    "http://www.pivotaltracker.com/services/v1/projects/#{TRACKER_PROJECT_ID}/stories/#{story_id}#{extra_path_elemets}"
  end
  
  def tracker_api_headers
    { 'X-TrackerToken' => TRACKER_API_TOKEN, 'Content-type' => 'application/xml' }
  end

end
