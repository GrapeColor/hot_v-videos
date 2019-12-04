require 'net/http'
require 'nokogiri'
require 'discordrb'

class HotVVideos
  VIDEOS_MIN = 30  # 各新着動画の最低数
  RANKING_DEFAULT = 50  # 48時間ランキングのデフォルト取得範囲
  RANKING_MAX     = 150 # 48時間ランキングの最大取得範囲
  YOUTUBE_URL    = "https://www.youtube.com/watch?v="
  USER_LOCAL_URL = "https://virtual-youtuber.userlocal.jp"
  THUMB_URL      = "https://img.youtube.com/vi/"
  THUMB_FILE_NAMES = [
    "maxresdefault.jpg",
    "sddefault.jpg",
    "hqdefault.jpg",
    "mqdefault.jpg",
    "default.jpg"
  ].freeze
  FAILURE_MSG = "動画を取得できませんでした (m´・ω・｀)m ｺﾞﾒﾝ…"

  def initialize(bot_token, offices_path)
    @offices = get_offices

    # 各新着動画URIをパース
    @office_uris = @offices.map do |office, value|
      [office, URI.parse("#{USER_LOCAL_URL}/movies?office=#{value}")]
    end.to_h
    @ranking_uri = URI.parse("#{USER_LOCAL_URL}/movies?range=48h")

    # アーカイブURL配列初期化
    @office_videos = @offices.keys.map {|office| [office, []] }.to_h
    @office_videos.default = []
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
    end

    # キャッシュ更新
    @bot.heartbeat do
      if Time.now - @last_cache > 1800
        @last_cache = Time.now
        cache_update
      end
    end

    # おすすめコマンド
    @bot.command :おすすめ do |event, *args|
      send_video(event, args.join(" "))
    end

    # オプションコマンド
    @bot.command :オプション do |event|
      send_options(event)
    end
  end

  # BOT起動
  def run(async = false)
    # キャッシュ初期化
    @last_cache = Time.now
    cache_update

    @bot.run(async)
  end

  private

  # ランキングから動画を取得
  def send_video(event, office)
    # 48時間ランキングから取得
    if office =~ /^\d+$/ || office.empty?
      range = $&.to_i
      range = RANKING_DEFAULT if range < 1
      range = RANKING_MAX if range > RANKING_MAX

      video_data = @ranking_videos[0..(range - 1)].sample
      return FAILURE_MSG if video_data.nil?

      send_card(
        event,
        video_data[:author],
        USER_LOCAL_URL + video_data[:channel],
        video_data[:title],
        video_data[:id],
        "📈 **#{video_data[:rank]}位**\nUser Local [48時間再生数ランキング](#{@ranking_uri.to_s})（#{range}位以内）より"
      )
      return
    end

    # 各グループの新着動画一覧から取得
    video_data = @office_videos[office].sample
    if video_data.nil?
      send_options(event, "**#{office}** の新着動画は取得できませんでした ( TДT)ｺﾞﾒﾝﾖｰ")
      return
    end

    send_card(
      event,
      video_data[:author],
      USER_LOCAL_URL + video_data[:channel],
      video_data[:title],
      video_data[:id],
      "User Local [#{office} 新着動画一覧](#{@office_uris[office].to_s}) より"
    )
    return
  end

  # 動画カードを送信
  def send_card(event, author, author_url, title, video_id, description, content = nil)
    event.send_embed(content) do |embed|
      embed.color  = 0xed0000
      embed.author = Discordrb::Webhooks::EmbedAuthor.new(
        name: author,
        url: author_url
      )
      embed.title  = title
      embed.url    = YOUTUBE_URL + video_id
      embed.description = description
      embed.image  = Discordrb::Webhooks::EmbedImage.new(
        url: get_video_thumb(video_id)
      )
      embed.footer = Discordrb::Webhooks::EmbedFooter.new(
        text: "Powered by User Local"
      )
      embed.timestamp = @last_cache
    end
  end

  # オプション一覧送信
  def send_options(event, content = nil)
    event.send_embed(content) do |embed|
      embed.color = 0xed0000
      embed.title = "オプション一覧"

      embed.description = <<DESC
**`数字`** : [48時間ランキング](https://virtual-youtuber.userlocal.jp/movies?range=48h)から指定された順位以内の動画をランダムに1つ紹介
  
グループ名を指定すると、そのグループの新着動画をランダムに1つ紹介
DESC
      @offices.each do |office, value|
        next if @office_videos[office].empty?
        embed.description += "**`#{office}`** / "
      end

      embed.footer = Discordrb::Webhooks::EmbedFooter.new(
        text: "Powered by User Local"
      )
      embed.timestamp = @last_cache
    end
  end

  # ランキングキャッシュ更新
  def cache_update
    # 48時間ランキング取得
    response = Net::HTTP.get_response(@ranking_uri)
    html = Nokogiri::HTML.parse(response.body, nil, 'UTF-8')

    @ranking_videos = html.css('.item-video').map.with_index(1) do |item, rank|
      get_video_data(item, rank)
    end

    # 各グループの新着動画取得
    @offices.keys.each do |office|
      response = Net::HTTP.get_response(@office_uris[office])
      html = Nokogiri::HTML.parse(response.body, nil, 'UTF-8')

      # 1万再生以上を取得
      @office_videos[office] = html.css('.item-video.primary').map do |item|
        get_video_data(item)
      end
      next if @office_videos[office].length > VIDEOS_MIN

      # 2千再生以上を取得
      @office_videos[office].concat(
        html.css('.item-video.secondary').map {|item| get_video_data(item) }
      )
      next if @office_videos[office].length > VIDEOS_MIN

      # 全動画を取得
      @office_videos[office] = html.css('.item-video').map do |item|
        get_video_data(item)
      end
    end
  end

  # グループ一覧と取得
  def get_offices
    uri = URI.parse(USER_LOCAL_URL)
    response = Net::HTTP.get_response(uri)
    html = Nokogiri::HTML.parse(response.body, nil, 'UTF-8')

    html.css('.office-link').map do |item|
      item['href'] =~ %r{/office/(\w+)}
      [item.content.strip, $1]
    end.to_h
  end

  # 動画データ取得
  def get_video_data(item, rank = nil)
    title = item['data-title']
    title.gsub!(/^\[LIVE\] /, '') if item['data-live-flag'] == "true"
    { rank: rank,
      id: item['data-id'],
      title: title,
      author: item['data-name'],
      channel: item['data-channel-link'] }
  end

  # サムネイル画像取得
  def get_video_thumb(video_id)
    uri = nil
    THUMB_FILE_NAMES.each do |file_name|
      uri = URI.parse(THUMB_URL + video_id + '/' + file_name)
      response = Net::HTTP.get_response(uri)
      break if response.code =~ /2../
    end
    return uri.to_s
  end
end
