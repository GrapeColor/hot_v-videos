require 'dotenv/load'
require './hot_v-videos.rb'

hot_v_videos = HotVVideos.new(ENV['HOT_V_VIDEOS_TOKEN'], '.\offices.yml')
hot_v_videos.run
