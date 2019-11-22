require 'net/http'
require 'nokogiri'
require 'yaml'
require 'pry'
require 'pry-doc'

offices_list = open('rankings.yml', 'r') { |f| YAML.load(f) }

def update_videos
  
end

def get_videos(office)
  # 引数チェック
  raise ArgumentError unless office.is_a?(String)
end