require 'net/http'
require 'nokogiri'
require 'dotenv'
require 'discordrb'

# グローバル変数初期化
rank_uri = URI.parse("https://virtual-youtuber.userlocal.jp/movies?range=48h")
last_time = Time.new(0)
video_uris = []

# BOT初期化
Dotenv.load
bot = Discordrb::Commands::CommandBot.new(
  token: ENV['DISCORD_TOKEN'],
  client_id: ENV['DISCORD_CLIENT_ID'],
  prefix: '?',
  ignore_bots: true
)

bot.ready do
  bot.game = bot.prefix + "おすすめ"
end

# キャッシュ更新
bot.heartbeat do
  # 10分キャッシュ
  if Time.now - last_time >= 600
    # GETリクエスト
    response = Net::HTTP.get_response(rank_uri)
    html = Nokogiri::HTML.parse(response.body, nil, 'UTF-8')
    
    # ランキング配列作成
    video_uris = html.css('.item-video.primary').map.with_index(1) do |item, index|
      next if !(item['data-video-url'])
      { rank: index, uri: item['data-video-url'] }
    end.compact

    last_time = Time.now
  end
end

# 'おすすめ'コマンド
bot.command "おすすめ".to_sym do |event|
  # ランキング取得失敗
  if video_uris == []
    event << "ランキングを取得できませんでした(m´・ω・｀)m ｺﾞﾒﾝ…"
    next
  end

  # メッセージ生成
  respod_video = video_uris.sample
  event << "**" + respod_video[:rank].to_s + "位**：" + respod_video[:uri]
  event << "（User Local再生数ランキング(48時間)より）"
end

bot.run
