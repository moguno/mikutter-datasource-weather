# coding: utf-8

Plugin.create(:"mikutter-datasource-weather") {
  require "open-uri"
  require "rexml/document"
  require "digest/md5"

  UserConfig[:weather_days] ||= 8

  @places = {}
  @cache = {}

  # 都市情報を取得
  def get_places()
    result = {}

    begin
      xml = open("http://weather.livedoor.com/forecast/rss/primary_area.xml") { |fp|
        fp.read
      }

      doc = REXML::Document.new(xml)

      doc.elements.each("rss/channel/ldWeather:source/pref") { |pref|
        pref.elements.each("city") { |city|
          result[city.elements["@id"].value] = "#{pref.elements["@title"].value}/#{city.elements["@title"].value}"
        }
      }
    rescue => e
      puts e
      puts e.backtrace
    end

    result
  end

  # 天気予報を取得
  def get_forecast(id)
    begin
      xml = open("http://weather.livedoor.com/forecast/rss/area/#{id}.xml") { |fp|
        fp.read
      }

      doc = REXML::Document.new(xml)

      result = doc.elements.collect("rss/channel/item") { |_| _ }.select { |_| _.elements["day"] }
        .map { |item|
        item.elements["description"].text
      }

      result
    rescue => e
      puts e
      puts e.backtrace

      []
    end
  end

  # メッセージを組み立てる
  def create_message(place, forecast_array)
    msg = "ぴんぽんぱんぽーん♪\n#{place}のお天気です。\n\n"
    msg += forecast_array[0, UserConfig[:weather_days]].join("\n")

    md5 = Digest::MD5.hexdigest(msg)

    result = if !@cache[md5]
      @cache[md5] = Message.new(:message => msg, :system => true)
    end

    @cache[md5]
  end

  # データソースを更新する
  def refresh
    Plugin.filtering(:extract_tabs_get, []).first.map { |_|
      Array(_[:sources]).select { |__| __.to_s =~ /^weather_/ }
    }.flatten.each { |datasource|
      id = datasource.to_s.sub(/^weather_/, "")

      forecast_array = get_forecast(id)
      msg = create_message(@places[id].sub(/\//, "の"), forecast_array)

      Plugin.call(:extract_receive_message, datasource, Messages.new([msg]))
    }
  end

  # 起動時処理
  on_boot { |service|
    if service == Service.primary
      @places = get_places()
    end
  }

  # データソース登録
  filter_extract_datasources { |datasources| 
    @places.each { |id, place|
      datasources[:"weather_#{id}"] = "天気/#{place}"
    }

    [datasources]
  }

  # 1分周期で問い合わせ
  on_period { |service|
    if service == Service.primary
      refresh
    end
  }

  # 設定
  settings(_("天気")) {
    adjustment(_("表示日数"), :weather_days, 1, 8)
  }
}
