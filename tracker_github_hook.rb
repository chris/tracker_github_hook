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
      api_tokens = Hash.new
      if project[1]['user_api_tokens']
        project[1]['user_api_tokens'].each_value do |user_info|
          api_tokens[user_info['email'].downcase] = user_info['tracker_api_token']
        end
      end
      PROJECTS[project[1]['github_url']] = { :api_token => project[1]['tracker_api_token'], 
                                             :project_id => project[1]['tracker_project_id'], 
                                             :ref => project[1]['ref'],
                                             :user_api_tokens => api_tokens }
    end
  rescue => e
    puts "Failed to startup: #{e.message}"
    puts "Ensure you have a config.yml in this directory with the'tracker_api_token' and 'tracker_project_id' keys/values set."
    exit(-1)
  end
end

# The handler for the GitHub post-receive hook
post '/' do
  @num_commits = 0
  push = JSON.parse(params[:payload])
  tracker_info = PROJECTS[push['repository']['url']]
  raise "GitHub Webook triggerd for repo: #{push['repository']['url']}; no matching github_url in config.yml" if tracker_info == nil
  if tracker_info[:ref] && push['ref'] != tracker_info[:ref]
      puts "Skipping commit for non-tracked ref #{push['ref']}"
  end
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
    
    # get API token for the user who made the commit, if possible
    api_token = api_token_for_user(tracker_info, commit['author']['email'])

    # see if there is a Tracker story trigger, and if so, get story ID
    message.scan(/\[Story(\d+)([^\]]*)\]/) do |tracker_trigger|
      @num_commits += 1
      story_id = tracker_trigger[0]

      # post comment to the story
      RestClient.post(create_api_url(tracker_info[:project_id], story_id, '/notes'),
                      "<note><text>(from [#{commit['id']}]) #{message}</text></note>", 
                      tracker_api_headers(api_token))
    
      # See if we have a state change
      state = tracker_trigger[1].match(/.*state:(\s?\w+).*/)
      if state
        state = state[1].strip

        RestClient.put(create_api_url(tracker_info[:project_id], story_id), 
                       "<story><current_state>#{state}</current_state></story>", 
                       tracker_api_headers(api_token))
      end     
    end
  end
  
  def api_token_for_user(tracker_info, email)
    tracker_info[:user_api_tokens][email.downcase] || tracker_info[:api_token]
  end

  def create_api_url(project_id, story_id, extra_path_elemets='')
    "http://www.pivotaltracker.com/services/v2/projects/#{project_id}/stories/#{story_id}#{extra_path_elemets}"
  end
  
  def tracker_api_headers(api_token)
    { 'X-TrackerToken' => api_token, 'Content-type' => 'application/xml' }
  end

end
