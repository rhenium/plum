# frozen-string-literal: true

# client/twitter.rb
# Twitter の User stream に（現在はサーバーが非対応のため）HTTP/1.1 を使用して接続する。
# 「にゃーん」を含むツイートを受信したら、REST API で HTTP/2 を使用して返信する。
$LOAD_PATH.unshift File.expand_path("../../../lib", __FILE__)
require "plum"
require "json"
require "cgi"
require "simple_oauth"

credentials = { consumer_key: "",
                consumer_secret: "",
                token: "",
                token_secret: "" }

rest = Plum::Client.start("api.twitter.com", 443)
Plum::Client.start("userstream.twitter.com", 443) { |streaming|
  streaming.get("/1.1/user.json",
                headers: { "authorization" => SimpleOAuth::Header.new(:get, "https://userstream.twitter.com/1.1/user.json", {}, credentials).to_s,
                           "accept-encoding" => "gzip, deflate" }) { |res|
    if res.status != "200"
      puts "failed userstream"
      exit
    end

    buf = String.new
    res.on_chunk { |chunk| # when received DATA frame
      next if chunk.empty?
      buf << chunk
      *msgs, buf = buf.split("\r\n", -1)

      msgs.each do |msg|
        next if msg.empty?

        json = JSON.parse(msg)
        next unless json["user"] # unless it is a tweet

        puts "@#{json["user"]["screen_name"]}: #{json["text"]}"

        if /にゃーん/ =~ json["text"]
          args = { "status" => "@#{json["user"]["screen_name"]} にゃーん",
                   "in_reply_to_status_id" => json["id"].to_s }
          rest.post(
            "/1.1/statuses/update.json",
            args.map { |k, v| "#{k}=#{CGI.escape(v)}" }.join("&"),
            headers: { "authorization" => SimpleOAuth::Header.new(:post, "https://api.twitter.com/1.1/statuses/update.json", args, credentials).to_s,
                       "content-type" => "application/x-www-form-urlencoded" }
          ).join
        end
      end
    }
  }
}
rest.close
