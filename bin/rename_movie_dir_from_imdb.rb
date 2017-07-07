#!/usr/bin/ruby -w

require 'fileutils'
require 'pp'
require 'xmlrpc/client'
require 'yaml'

if ARGV.size != 1
  puts "Usage: #{$0} movie_dir, exiting"
  exit 1
end

movie_dir = ARGV[0]
unless File.directory?(movie_dir)
  puts "Directory #{movie_dir} doesn't exist, exiting'"
  exit 1
end

if movie_dir.end_with? "/"
  search_pattern = "#{movie_dir}*.nfo"
else
  search_pattern = "#{movie_dir}/*.nfo"
end

# Shorter version of following code
# imdb_url = open(nfo_file_path).grep(/imdb/)[0].match(/http.*\//).to_s

# Grab first nfo file if several exist
nfo_file_path = Dir[search_pattern][0]

if nfo_file_path.nil?
  puts "No NFO file found in #{movie_dir}, exiting"
  exit 1
end

imdb_url = File.open(nfo_file_path) do |file|
  file.grep(/imdb/).collect do |line|
    line.match(/http.*\//).to_s
  end
end

if imdb_url.size > 1
  puts "Too many urls matched, exiting"
  p imdb_url
  exit 1
elsif imdb_url.size == 0
  puts "No imdb_url matched, exiting"
  exit 1
end

# array to string
imdb_url = imdb_url.to_s
puts "Using imdb_url: #{imdb_url}"

need_new_token = true
previous_token_path = "/tmp/opensubtitles.org_token"

server = XMLRPC::Client.new("api.opensubtitles.org", "/xml-rpc", 80)
puts "server = #{server}"
puts "movie_dir = #{movie_dir}"

# Token value is stored in temp file for later retrieval (Will be retrieved if used less than 14 minutes ago)
# Session gets closed by server if inactive > 15 mins
if File.exists?(previous_token_path)
  token_and_time = File.open(previous_token_path, "r") {|input| YAML.load input}
  previous_token = token_and_time.shift
  previous_token_time = token_and_time.shift

  if previous_token_time.class == Time
    if (Time.now - 60*14) < previous_token_time
      if previous_token.class == String
        if previous_token.length > 0
          need_new_token = false
          token = previous_token
          last_time_used = ((Time.now - previous_token_time) / 60.0).floor
          x_minutes = case last_time_used
                      when 0: "less than a minute"
                      when 1: "#{last_time_used} minute"
                      else "#{last_time_used} minutes"
                      end

          puts "token : #{token} is still valid (last used #{x_minutes} ago)"
        end
      end
    end
  end
else
  puts "File : \"#{previous_token_path}\" doesn't exist and will be created."
end

if need_new_token
  # if (defined? token) # Doesn't work
  puts "Will update token ..."

  #==================================================================================================#
  # >> Exception `LoadError' at /usr/lib/ruby/1.8/tmpdir.rb:14 - no such file to load -- Win32API <<
  # Line below generates error above
  session = server.call("LogIn","","","en","OS Test User Agent")
  #==================================================================================================#

  print "session = " ; pp session
  token = session["token"]
  puts "token = #{token}"
end

puts "Feeding imdb_url: #{imdb_url}"
imdb_id = imdb_url.gsub(/\D/, "")

searchlist = {
  "sublanguageid" => "eng",
  "imdbid" => imdb_id.to_s,
}
searchlist = [] << searchlist
print "searchlist = " ;p searchlist

moviesList = server.call("SearchSubtitles", token, searchlist)

# temporarly on
# pp moviesList

unless moviesList["data"]
  puts "No data found, exiting ..."
  exit 1
end

    # # I want a list of subs sorted by UserRank and SubRating so I use this trick
    # moviesList['data'].each do |item|
      # new_value = case item['UserRank']
                  # when "gold member": "z_gold member"
                  # when "silver member": "y_silver member"
                  # when "bronze member": "x_bronze member"
                  # when "trusted": "w_trusted"
                  # else "a_" + item['UserRank']
                  # end
      # item['UserRank'] = new_value
    # end
    # moviesListByRating = moviesList['data'].sort_by{|entry| [entry['UserRank'], entry['SubRating']]}.reverse

    # moviesListByRating = moviesListByRating.each do |item|
      # item['UserRank'] = item['UserRank'].split("_").pop     # 'z_gold member' becomes 'gold member' once more
    # end

    # puts
    # puts "\t<<<<<<<<<<<<<<<<<<<<<<<<"
    # puts "\t| MovieImdbRating = " + moviesListByRating[0]['MovieImdbRating'] + "|"
    # puts "\t>>>>>>>>>>>>>>>>>>>>>>>>"

    puts
    File.open(previous_token_path, "w") {|output| YAML.dump [token, Time.now], output}
    puts "#{previous_token_path} updated."
    puts

    aggregate_MovieName = []
    aggregate_MovieYear = []
    aggregate_MovieNameEng = []
  moviesList['data'].each_with_index do |item,index|
      aggregate_MovieName << item['MovieName']
      aggregate_MovieYear << item['MovieYear']

      # MovieNameEng *may be* needed ??
      aggregate_MovieNameEng << item['MovieNameEng']
  end

  movie_name = aggregate_MovieName.uniq
  movie_year = aggregate_MovieYear.uniq
  movie_nameeng = aggregate_MovieNameEng.uniq

  #remove empty elements of hash if they have been returned
  #doesn't work --> maybe it's ok now ?
  #movie_name = movie_name - [""] - [" "]

  if movie_name.size > 1
    puts "Too many movie names, exiting"
    p movie_name
    exit 1
  end

  if movie_year.size > 1
    puts "Too many movie years, exiting"
    p movie_year
    exit 1
  end

  if movie_nameeng.size > 1
    puts "Too many movie names (English), exiting"
    p movie_nameeng
    exit 1
  end

  puts "--------------------------------------------------------------------------------"
  puts "movie_name = #{movie_name}"
  puts "movie_year = #{movie_year}"
  puts "movie_nameeng = #{movie_nameeng}"
  puts "--------------------------------------------------------------------------------"
  puts

  movie_dir_new = "#{movie_name} (#{movie_year})"

  print %Q[rename directory "#{movie_dir}" --> "#{movie_dir_new}" ? (y or n) ]

  # Get only "y" or "n" (both parsing methods work)
  # answer = STDIN.gets.chomp.scan(/./)[0]
  answer = STDIN.gets.chomp[0..0]

  if answer == "y"
    FileUtils.mv movie_dir, movie_dir_new
  end
