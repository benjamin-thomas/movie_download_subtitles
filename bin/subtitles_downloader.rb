#!/usr/bin/ruby -w

# Subtitle downloader

$DEBUG=true

require 'pp'
#==========================================================================================================================#
# >>> Exception `NoMethodError' at /usr/lib/ruby/1.8/rational.rb:78 - undefined method `gcd' for Rational(1, 2):Rational <<<
# Line(s) below generate(s) error above
require 'yaml'
require 'xmlrpc/client'
#==========================================================================================================================#

class Hasher# {{{
  def open_subtitles_hash(filename)
    raise "Need video filename" unless filename

    fh = File.open(filename)
    fsize = File.size(filename)

    hash = [fsize & 0xffff, (fsize >> 16) & 0xffff, 0, 0]

    8192.times { hash = add_unit_64(hash, read_uint_64(fh)) }

    offset = fsize - 65536
    fh.seek([0,offset].max, 0)

    8192.times { hash = add_unit_64(hash, read_uint_64(fh)) }

    fh.close

    return uint_64_format_hex(hash)
  end

  def read_uint_64(stream)
    stream.read(8).unpack("vvvv")
  end

  def add_unit_64(hash, input)
    res = [0,0,0,0]
    carry = 0

    hash.zip(input).each_with_index do |(h,i),n|
    sum = h + i + carry
    if sum > 0xffff
      res[n] += sum & 0xffff
      carry = 1
    else
      res[n] += sum
      carry = 0
    end
    end
    return res
  end

  def uint_64_format_hex(hash)
    sprintf("%04x%04x%04x%04x", *hash.reverse)
  end
end# }}}

movie_file = ARGV[0]
if ARGV[0]
  movie_file_full_path = File.expand_path(movie_file)
  movie_file_dirname = File.dirname(movie_file_full_path)
else
  movie_file_dirname = "."
end

begin
  # Load previous search if it exists
  unless File.exist?("sub_search_result.txt")
    need_new_token = true
    previous_token_path = "/tmp/opensubtitles.org_token"

    server = XMLRPC::Client.new("api.opensubtitles.org", "/xml-rpc", 80)
    puts "server = #{server}"
    puts "movie_file = #{movie_file}"

    my_hasher = Hasher.new
    movie_hash = my_hasher.open_subtitles_hash(movie_file)
    movie_file_size = File.size(movie_file)

    puts "movie_hash = #{movie_hash}"
    puts "movie_file_size = #{movie_file_size}"

    # Token value is stored in temp file for later retrieval (Will be retrieved if used less than 14 minutes ago)
    # Session gets closed by server if inactive > 15 mins
    if File.exist?(previous_token_path)
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
                          when 0 then "less than a minute"
                          when 1 then "#{last_time_used} minute"
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

    searchlist = {
    "sublanguageid" => "eng",
    "moviehash" => movie_hash.to_s,
    "moviebytesize" => movie_file_size.to_s
    }
    searchlist = [] << searchlist
    print "searchlist = " ;p searchlist

    moviesList = server.call("SearchSubtitles", token, searchlist)
    # pp moviesList

    unless moviesList["data"]
      puts
      puts "No movie found based on movie hash."
      print "Enter imdb_id (or url which will be stripped of all but numbers) : "
      imdb_id = STDIN.gets.chomp.gsub(/\D/, "")
      # imdb_id = ARGV[1].gsub(/\D/, "")

      searchlist = {
      "sublanguageid" => "eng",
      "imdbid" => imdb_id.to_s,
      "moviebytesize" => movie_file_size.to_s
      }
      searchlist = [] << searchlist
      print "searchlist = " ;p searchlist

      moviesList = server.call("SearchSubtitles", token, searchlist)
      pp moviesList

      unless moviesList["data"]
        puts "No data found, exiting ..."
        exit
      end
    end

    # I want a list of subs sorted by UserRank and SubRating so I use this trick
    moviesList['data'].each do |item|
      new_value = case item['UserRank']
                  when "gold member" then "z_gold member"
                  when "silver member" then "y_silver member"
                  when "bronze member" then "x_bronze member"
                  when "trusted" then "w_trusted"
                  else "a_" + item['UserRank']
                  end
      item['UserRank'] = new_value
    end
    moviesListByRating = moviesList['data'].sort_by{|entry| [entry['UserRank'], entry['SubRating']]}.reverse

    moviesListByRating = moviesListByRating.each do |item|
      item['UserRank'] = item['UserRank'].split("_").pop     # 'z_gold member' becomes 'gold member' once more
    end

    puts
    puts "\t<<<<<<<<<<<<<<<<<<<<<<<<"
    puts "\t| MovieImdbRating = " + moviesListByRating[0]['MovieImdbRating'] + "|"
    puts "\t>>>>>>>>>>>>>>>>>>>>>>>>"

    moviesListByRatingResume= []
    moviesListByRating.each_with_index do |item,i|
      moviesListByRatingResume << [i, item['SubFileName'], item['UserRank'], item['SubRating'], item['SubDownloadLink']]
    end

    puts
    puts
    File.open(previous_token_path, "w") {|output| YAML.dump [token, Time.now], output}
    puts "#{previous_token_path} updated."
    File.open(movie_file_dirname + File::Separator + "sub_search_result.txt", "w") {|output| YAML.dump moviesListByRatingResume, output}
    puts "sub_search_result.txt saved in #{movie_file_dirname} folder."
    File.open(movie_file_dirname + File::Separator + "sub_full_search_result.txt", "w") {|output| YAML.dump moviesListByRating, output}
    puts "sub_full_search_result.txt saved in #{movie_file_dirname} folder."
  else
    # moviesListByRatingResume = File.open("sub_search_result.txt", "r") {|input| YAML.load input}
    sub_search_dest = movie_file_dirname + File::Separator + "sub_full_search_result.txt"
    p sub_search_dest
    moviesListByRating = File.open(sub_search_dest, "r") {|input| YAML.load input}
    p moviesListByRating.class
  end #unless File.exist?("sub_search_result.txt")

  moviesListByRating.each_with_index do |item,index|
      puts "--------------------------------------------------------------------------------"
      puts "Index           = " + index.to_s
      puts "SubFileName     = " + item['SubFileName']
      puts "UserRank        = " + item['UserRank']
      puts "SubRating       = " + item['SubRating']
      puts "SubDownloadLink = " + item['SubDownloadLink']
  end

  puts "--------------------------------------------------------------------------------"
  puts
  print "Which subtitles would you like to download ? Enter Index : "
  sub_index = STDIN.gets.chomp.to_i
  selection = moviesListByRating[sub_index]
  if selection.nil?
    puts "Selection out of bounds"
    exit 1
  end
  download_link = moviesListByRating[sub_index]['SubDownloadLink']

  if ARGV[0]
    sub_base_name = movie_file[0..-4]
    sub_ext = moviesListByRating[sub_index]['SubFileName'].split(".").pop
    sub_full_name = sub_base_name + sub_ext
  else
    sub_full_name = moviesListByRating[sub_index]['SubFileName']
  end
  puts
  sub_dest = movie_file_dirname + File::Separator + sub_full_name
  system "wget --quiet -O - #{download_link} | gunzip > \"#{sub_dest}\""
  puts "Downloaded #{download_link} --> #{sub_dest}"

rescue

end


# {{{
# #!/usr/bin/env python

# # Download subtitles from opensubtitles.org (nautilus version)
# # Default language is english, to change the language change sublanguageid parameter
# # in the searchlist.append function

# # Carlos Acedo (carlos@linux-labs.net)
# # Inspired on subdownloader
# # License GPL v2

# import os
# import sys
# import struct
# import subprocess
# from xmlrpclib import ServerProxy, Error


# def hashFile(name):
#       try:
#                 longlongformat = 'q'  # long long
#                 bytesize = struct.calcsize(longlongformat)
#
#                 f = open(name, "rb")
#
#                 filesize = os.path.getsize(name)
#                 hash = filesize
#
#                 if filesize < 65536 * 2:
#                        return "SizeError"
#
#                 for x in range(65536/bytesize):
#                         buffer = f.read(bytesize)
#                         (l_value,)= struct.unpack(longlongformat, buffer)
#                         hash += l_value
#                         hash = hash & 0xFFFFFFFFFFFFFFFF #to remain as 64bit number
#
#
#                 f.seek(max(0,filesize-65536),0)
#                 for x in range(65536/bytesize):
#                         buffer = f.read(bytesize)
#                         (l_value,)= struct.unpack(longlongformat, buffer)
#                         hash += l_value
#                         hash = hash & 0xFFFFFFFFFFFFFFFF
#
#                 f.close()
#                 returnedhash =  "%016x" % hash
#                 return returnedhash
#
#       except(IOError):
#                 return "IOError"
# }}}

# # ================== Main program ========================

# server = ServerProxy("http://api.opensubtitles.org/xml-rpc")
# print "server = " + str(server)
# # movie_file = os.environ['NAUTILUS_SCRIPT_SELECTED_FILE_PATHS'].strip('\n')
# movie_file = sys.argv[1]
# print "movie_file = " + movie_file

# try:
#     myhash = hashFile(movie_file)
#     print "myhash = " + myhash
#     movie_file_size = os.path.getsize(movie_file)
#     print "movie_file_size = " + str(movie_file_size)
#     # session =  server.LogIn("","","en","python")
#     session =  server.LogIn("","","en","OS Test User Agent")
#     print "session = " + str(session)
#     token = session["token"]
#     print "token = " + token
#
#     searchlist = []
#     searchlist.append({'sublanguageid' :"eng",'moviehash':myhash,'moviebytesize':str(movie_file_size)})
#     print "searchlist = " + str(searchlist)
#     print
#
#     moviesList = server.SearchSubtitles(token, searchlist)
#     # print(moviesList)
#     # print "moviesList = " + str(moviesList)
#     for item in moviesList['data']:
#         print "--------------------------------------------"
#         print "SubFileName     = " + item['SubFileName']
#         print "UserRank        = " + item['UserRank']
#         print "SubRating       = " + item['SubRating']
#         print "MovieImdbRating = " + item['MovieImdbRating']
#         print "SubDownloadLink = " + item['SubDownloadLink']
#         # print
#     exit()
#     if moviesList['data']:
#         kdialog_items = []
#         for item in moviesList['data']:
#             kdialog_items += [item['SubFileName'],item['LanguageName'],item['MatchedBy']]
#
#         args = ['zenity','--list','--width=600','--height=400','--text=Select subtitle',]
#         args += ['--column=File name','--column=Lang','--column=Mathed by']
#
#         resp = subprocess.Popen(args+ kdialog_items,stdout=subprocess.PIPE).communicate()[0].strip('\n')

#         if resp != '':
#             index = 0
#             data = moviesList['data']
#
#             while index < len(data) and data[index]['SubFileName'] != resp:
#                 index += 1

#             sub = data[index]
#
#             subFileName = os.path.splitext(os.path.basename(peli))[0] + os.path.splitext(sub['SubFileName'])[1]
#             subDirName = os.path.dirname(peli)
#             subURL = sub['SubDownloadLink']
#
#             # string hasn't got a format method !
#             #response = os.system("wget -O - '{0}' | gunzip  >  {1}".format(subURL, os.path.join(subDirName,subFileName)))
#             # response = os.system("wget -O - '%s' | gunzip  >  %s" % (subURL, os.path.join(subDirName,subFileName)))
#             response = os.system("wget -O - '%s' | gunzip  >  '%s'" % (subURL, os.path.join(subDirName,subFileName)))
#
#             if response != 0:
#                 os.system('zenity --error --text="An error ocurred downloading or writing the subtitle"')
#
#     else:
#         os.system('zenity --error --text="No subtitles found"')
#
#     server.Logout(session["token"])
# except Error, v:
#     os.system('zenity --error --text="An error ocurred"')




