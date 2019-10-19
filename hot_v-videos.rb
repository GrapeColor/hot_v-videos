require 'net/http'
require 'nokogiri'
require 'dotenv'
require 'discordrb'

# 取得するURI
rank_uri = URI.parse("https://virtual-youtuber.userlocal.jp/movies?range=48h")

# BOT初期化
Dotenv.load
bot = Discordrb::Commands::CommandBot.new(
  token: ENV['DISCORD_TOKEN'],
  client_id: ENV['DISCORD_CLIENT_ID'],
  prefix: '?',
  ignore_bots: true
)

bot.ready do
  bot.game = "?おすすめ"
end

bot.command "おすすめ".to_sym do |event|
  # GETリクエスト
  response = Net::HTTP.get_response(rank_uri)
  puts "HTTP Status Code: " + response.code
  
  html = Nokogiri::HTML.parse(response.body, nil, 'UTF-8')
  
  video_uris = []
  html.css('.item-video.primary').each_with_index do |item, index|
    video_uris << { rank: index + 1, uri: item['data-video-url'] }
  end

  # ランキング取得失敗
  if video_uris == []
    event << "ランキングを取得できませんでした(m´・ω・｀)m ｺﾞﾒﾝ…"
    next
  end

  respod_video = video_uris.sample
  event << "**" + respod_video[:rank].to_s + "位**：" + respod_video[:uri]
  event << "（User Local再生数ランキング(48時間)より取得）"
end

bot.run