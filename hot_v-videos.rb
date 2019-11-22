require 'yaml'
require 'net/http'
require 'nokogiri'
require 'discordrb'

class HotVVideos
  VIDEOS_RANGE  = 30  # 各新着動画の最低数
  RANKING_RANGE = 50  # 48時間ランキングのデフォルト取得範囲
  FAILURE_MSG = "動画を取得できませんでした(m´・ω・｀)m ｺﾞﾒﾝ…"

  def initialize(bot_token)
    # インスタンス変数初期化
    ## グループ一覧読み込み
    @offices = open('offices.yml', 'r') {|f| YAML.load(f) }
    ## 各新着動画URIをパース
    @office_uris = @offices.map do |office, value|
      [office, URI.parse("https://virtual-youtuber.userlocal.jp/movies?office=#{value}")]
    end.to_h
    @ranking_uri = URI.parse("https://virtual-youtuber.userlocal.jp/movies?range=48h")
    ## アーカイブURL配列初期化
    @office_videos  = @offices.keys.map {|office| [office, []] }.to_h
    @ranking_videos = []
    
    # BOT初期化
    @bot = Discordrb::Commands::CommandBot.new(
      token: bot_token,
      prefix: '?',
      help_command: false,
      ignore_bots: true
    )
    
    # BOTステータス初期化
    @bot.ready do
      @bot.game = "#{@bot.prefix}おすすめ | #{@bot.prefix}オプション"
      cache_update
      @last_time = Time.now
    end
    
    # キャッシュ更新
    @bot.heartbeat do
      if Time.now - @last_time > 600
        cache_update
        @last_time = Time.now
      end
    end
    
    # おすすめコマンド
    @bot.command :おすすめ do |event|
      content = event.content
      content.slice!("#{@bot.prefix}おすすめ ")
      get_video(event, content)
    end

    @bot.command :オプション do |event|
      send_options(event)
    end
  end
  
  # BOT起動
  def run(async = false)
    @bot.run(async)
  end
  
  private
  
  # ランキングから動画を取得
  def get_video(event, office)
    # 48時間ランキングから取得
    if office =~ /^\d+$/ || office.nil?
      range = $&.to_i
      range = RANKING_RANGE if range < 1
      range -= 1

      respod_video = @ranking_videos[0..range].sample
      return FAILURE_MSG if respod_video.nil?
      return "**#{respod_video[:rank]}位**: #{respod_video[:uri]}\n（User Local48時間再生数ランキングより）"
    end

    # 各グループの新着動画一覧から取得
    if @office_videos[office].nil?
      send_options(event)
      return
    end
    respod_video = @office_videos[office].sample
    return FAILURE_MSG if respod_video.nil?
    return "#{respod_video}\n（User Local**#{office}**新着動画一覧より）"
  end

  # ランキングキャッシュ更新
  def cache_update
    # 48時間ランキング取得
    response = Net::HTTP.get_response(@ranking_uri)
    html = Nokogiri::HTML.parse(response.body, nil, 'UTF-8')
  
    @ranking_videos = html.css('.item-video').map.with_index(1) do |item, rank|
      next unless item['data-video-url']
      { rank: rank, uri: item['data-video-url'] }
    end.compact

    # 各グループの新着動画取得
    @offices.keys.each do |office|
      response = Net::HTTP.get_response(@office_uris[office])
      html = Nokogiri::HTML.parse(response.body, nil, 'UTF-8')

      # 1万再生以上を取得
      @office_videos[office] = html.css('.item-video.primary').map do |item|
        item['data-video-url']
      end.compact
      next if @office_videos[office].length > VIDEOS_RANGE

      # 2千再生以上を取得
      @office_videos[office].concat(
        html.css('.item-video.secondary').map do |item|
          item['data-video-url']
        end.compact
      )
      next if @office_videos[office].length > VIDEOS_RANGE

      # 全動画を取得
      @office_videos[office] = html.css('.item-video').map do |item|
        item['data-video-url']
      end.compact
    end
  end

  # オプション一覧送信
  def send_options(event)
    event.send_embed do |embed|
      embed.color = 0xed0000
      embed.title = "オプション一覧"
      embed.description = <<DESC
**`数字`**: [48時間ランキング](https://virtual-youtuber.userlocal.jp/movies?range=48h)から数字のランキング以内の動画を紹介
  
以下の文字列を付けると、そのグループごとの新着動画を紹介
DESC
      @offices.each do |office, value|
        embed.description += "**`#{office}`**　"
      end
    end
  end
end
