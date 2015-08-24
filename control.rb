require 'pp'
require 'fileutils'
require 'logger'
require 'json'

class Control
  attr_accessor :body, :req, :project, :r, :logger, :builds

  def initialize
    FileUtils.mkdir_p("log")
    self.logger = Logger.new("log/production.log")
    self.logger.debug "Started at #{Time.now.to_s}"
    @builds ||= {}
  end

  def index
    puts "<h1>Semaphore buld notifications via XMPP</h1>"
  end

  def puts(string)
    logger.debug string
    r.puts(string)
    string
  end

  def ping
    puts("ping")
  end

  def notify(*msgs)
    notifier = File.join(File.dirname(__FILE__), 'notify.rb')
    cmd = "#{notifier} #{msgs.map{|msg| msg.inspect}.join(" ")}"
    puts "#{cmd}: #{`#{cmd} 2>&1`}"
  end

  # Integration finished
  #
  #   {
  #     "branch_name"=>"master",
  #     "branch_url"=>
  #     "https://semaphoreapp.com/..../branches/master",
  #     "project_name"=>"appfocus-tv-server",
  #     "build_url"=>"https://semaphoreapp.com/.../branches/master/builds/2",
  #     "build_number"=>2,
  #     "result"=>"passed",
  #     "started_at"=>"2014-02-20T14:28:34Z",
  #     "finished_at"=>"2014-02-20T14:35:40Z",
  #     "commit"=>{
  #       "id"=>"a84295431de2f1c7539eb00085eff253358edce3",
  #       "url"=>"https://github.com/.../commit/a84295431de2f1c7539eb00085eff253358edce3",
  #       "author_name"=>"Marcin Raczkowski",
  #       "author_email"=>"marcin.raczkowski@gmail.com",
  #       "message"=>"Updating configuration & installing active admin",
  #       "timestamp"=>"2014-02-20T14:28:16Z"
  #     }
  #   }
  def integration_finished
    if body.strip.empty? || !req.post?
      puts "Expected a post payload"
      return
    end

    payload = JSON.parse(body)
    logger.debug payload.pretty_inspect

    build_number = payload["build_number"]
    branch = payload["branch_name"]
    result = payload["result"] # passed or failed
    commit = payload["commit"]
    build_url = payload["build_url"]
    cmsg   = commit && commit["message"]
    cmsg &&= cmsg.split("\n\n").first

    if builds[build_number]
      logger.debug "Got #{builds[build_number] += 1} hit with same build number."
      return
    else
      builds[build_number] = 1
    end

    msg  = "#{branch.capitalize} #{result.upcase}! "
    msg += "Last commit: #{cmsg.inspect} by #{commit["author_name"]}. " if commit.is_a?(Hash)
    msg += build_url unless result == "passed"

    notify msg
  rescue => e
    notify "Got exception during build callback: #{e.class.name}: #{e.to_s} on line: #{e.backtrace[0]}"
    logger.error "#{e.class.name}: #{e.to_s}\n  #{e.backtrace.join("\n  ")}"

    raise(e)
  end

  # Deploy:
  #
  #   {
  #     "project_name"="project_name",
  #     "server_name"=>"heroku-staging",
  #     "number"=>1,
  #     "result"=>"passed",
  #     "created_at"=>"2014-02-20T14:40:26Z",
  #     "updated_at"=>"2014-02-20T14:41:54Z",
  #     "started_at"=>"2014-02-20T14:40:33Z",
  #     "finished_at"=>"2014-02-20T14:41:54Z",
  #     "html_url"=> "https://semaphoreapp.com/..../servers/heroku-staging/deploys/1",
  #     "build_html_url"=> "https://semaphoreapp.com/....../branches/master/builds/2",
  #     "commit"=> {
  #       "id"=>"a84295431de2f1c7539eb00085eff253358edce3",
  #       "url"=>"https://github.com/..../commit/a84295431de2f1c7539eb00085eff253358edce3",
  #       "author_name"=>"Marcin Raczkowski",
  #       "author_email"=>"marcin.raczkowski@gmail.com",
  #       "message"=>"Updating configuration & installing active admin",
  #       "timestamp"=>"2014-02-20T14:28:16Z"
  #     }
  #   }
  #
  def deployed
    if body.strip.empty? || !req.post?
      puts "Expected a post payload"
      return
    end

    payload = JSON.parse(body)
    logger.debug payload.pretty_inspect

    deploy_number = payload["number"]
    server_name = payload["server_name"]
    result = payload["result"] # passed or failed
    commit = payload["commit"]
    deploy_url = payload["html_url"]
    cmsg   = commit && commit["message"]
    cmsg &&= cmsg.split("\n\n").first

    msg  = "Deploy ##{deploy_number} to #{server_name} #{result.upcase}! "
    msg += "Last commit: #{cmsg.inspect} by #{commit["author_name"]}. " if commit.is_a?(Hash)
    msg += deploy_url unless result == "passed"

    notify msg
  rescue => e
    notify "Got exception during build callback: #{e.class.name}: #{e.to_s} on line: #{e.backtrace[0]}"
    logger.error "#{e.class.name}: #{e.to_s}\n  #{e.backtrace.join("\n  ")}"

    raise(e)
  end


  def call(env)
    self.req = Rack::Request.new(env)
    self.body = req.body.read
    self.r = StringIO.new

    _, self.project, method = *req.path_info.split("/")

    if project
      case method
      when "integration" then integration_finished
      when "deploy"      then deployed
      when "ping"        then ping
      end
    else
      index
    end

    r.rewind
    [200, {'Content-Type' => 'text/html'}, [$layout % [project, r.read]]]
  rescue => e
    logger.error e.to_s
    raise
  end
end

$layout = <<DOC
<!DOCTYPE html>
<html>
  <head>
    <title>Deploy Control Panel</title>

    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link href="//netdna.bootstrapcdn.com/twitter-bootstrap/2.3.1/css/bootstrap-combined.min.css" rel="stylesheet" />
  </head>
  <body><div class="container">
    <h1>%s</h1>
    %s
  </div></body>
</html>
DOC
