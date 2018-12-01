require 'time'
require 'optparse'
require 'server_log_parser'

ASSETS_EXTENSIONS = ['.svg', '.css', '.js', '.png', '.ico', '.gif']
# One of:
# ServerLogParser::COMMON_LOG_FORMAT
# ServerLogParser::COMMON_LOG_FORMAT_VIRTUAL_HOST
# ServerLogParser::COMBINED
# ServerLogParser::COMBINDED_VIRTUAL_HOST
LOG_FORMAT = ServerLogParser::Parser.new(ServerLogParser::COMBINED)

options = {file: "access.log"}
OptionParser.new do |parser|
  parser.banner = "Usage: nginx_log_stats.rb [options]"

  parser.on("-h", "--help", "Show this help message") do ||
    puts parser
  end

  parser.on("-f", "--file FILEPATH", "The filepath of the nginx logs to process.") do |file|
    options[:file] = file
  end
end.parse!


def parse_logs(filepath)
  log_parser = LOG_FORMAT
  data = {}
  
  File.foreach(filepath) do |line|
    parsed = log_parser.handle!(line)
    data = add_host(data, parsed)
  end
  data
end

def add_host(data, parsed)
  host = parsed["%h"]
  if data[host].nil? then data[host] = {} end
  data[host] = add_time(data[host], parsed)
  data
end

def add_time(data_host, parsed)
  time = parsed["%t"].iso8601
  if data_host[time].nil? then data_host[time] = [] end
  data_host[time] = add_resource(data_host[time], parsed)
  data_host
end

def add_resource(data_host_time, parsed)
  req = parsed["%r"]
  res = if req.nil? then nil else req["resource"] end
  data_host_time << res
end

def is_asset?(resource)
  ret = false
  ASSETS_EXTENSIONS.each do |ext|
    ret ||= resource.end_with?(ext)
  end
  ret
end

def get_stats(data)
  max_reqps = 0
  min_reqps = 10
  avg_reqps = 0
  num_reqs = 0
  total_avg_req_hosts = 0
  reqs_app_avgs = []
  reqs_assets_avgs = []
  data.each do |host, time_reqs|
    total_reqs_host = 0
    time_reqs.each do |time, reqs|
      if reqs.length > max_reqps
        max_reqps = reqs.length
      elsif reqs.length < min_reqps
        min_reqps = reqs.length
      end
      num_reqs += reqs.length
      total_reqs_host += reqs.length
      reqs_app_avgs << reqs.compact.select { |req| not is_asset?(req) }.length
      reqs_assets_avgs << reqs.compact.select { |req| is_asset?(req) }.length
    end
    total_avg_req_hosts += total_reqs_host / time_reqs.keys.length
  end
  avg_reqps = total_avg_req_hosts / data.keys.length
  return {
    number_of_ips: data.keys.length,
    max_reqps: max_reqps,
    min_reqps: min_reqps,
    num_reqs: num_reqs,
    avg_reqps: avg_reqps,
    avg_reqps_app: reqs_app_avgs.reduce(:+).to_f / (reqs_app_avgs.length),
    avg_reqps_assets: reqs_assets_avgs.reduce(:+).to_f / (reqs_assets_avgs.length),
  }
end

data = parse_logs(options[:file])
pp get_stats(data)

