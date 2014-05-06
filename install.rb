require 'pry'

require 'net/ftp'
require 'rbconfig'
require 'zlib'
require 'rubygems/package'

BUILD_DIR = "./build"
DIST_DIR = "./dist"

FTP_SERVER = "ftp.perforce.com"
TOP_DIR = "perforce"
P4RUBY_FTP_DIR = "bin.tools"

P4RUBY_ARCHIVE = "p4ruby.tgz"

class Installer
  def initialize
    unless File.directory?(DIST_DIR)
      Dir.mkdir(DIST_DIR)
    end

    unless File.directory?(BUILD_DIR)
      Dir.mkdir(BUILD_DIR)
    end

    @platform = guess_platform

    #TODO some way of the user supplying their own ftp path/ local path for the api's
    fetch
    build
  end

  def fetch
    p4_ftp = P4Ruby_FTP.new(@platform)
    p4_ftp.download
  end

  def build
    wd = Dir.getwd
    api_dir = get_api_build_dir
    Dir.chdir(get_ruby_build_dir)
    puts `yes | ruby p4conf.rb -d #{api_dir}`
    puts `make`
    puts `ruby test.b`
    puts `make install`
    #TODO Deal with known issue wheree we have to ignore -Werror in Makefile
    Dir.chdir(wd)
  end

  def guess_cpu
    if RbConfig::CONFIG["target_os"] =~ /darwin/i
      if RbConfig::CONFIG["build"] =~ /i686|x86_64/
        "x86_64"
      else
        "x86"
      end
    else
      case RbConfig::CONFIG['target_cpu']
        when /ia/i
          'ia64'
        else
          RbConfig::CONFIG['target_cpu']
      end
    end
  end

  def guess_platform()
    case RbConfig::CONFIG["target_os"].downcase
      when /nt|mswin/
        "nt#{guess_cpu}"
      when /mingw/
        "mingwx86"
      when /darwin/
        #TODO look at darwin 100, can you complile bin for 90 on 100?
        "darwin90#{guess_cpu}"
      when /solaris/
        "solaris10#{guess_cpu}"
      when /linux/
        "linux26#{guess_cpu}"
      when /cygwin/
        #No longer built for
    end
  end

  def get_ruby_build_dir
    Dir.foreach(BUILD_DIR) do |d|
      if d =~ /p4ruby/
        return File.join(BUILD_DIR,d)
      end
    end
  end

  def get_api_build_dir
    Dir.foreach(BUILD_DIR) do |d|
      if d =~ /p4api/
        return File.join(Dir.getwd, BUILD_DIR,d)
      end
    end
  end
end


class P4Ruby_FTP

  def initialize(platform)
    @ftp = Net::FTP.new(FTP_SERVER)
    @ftp.login
    @ftp.chdir(TOP_DIR)

    @latest = latest_version
    @ftp.chdir("r#{@latest}")

    @platform = "bin.#{platform}"

    if @platform =~ /nt|mingw/
      @p4api_archive = "p4api.zip"
    else
      @p4api_archive = "p4api.tgz"
    end
  end

  def versions
    remote_files_matching(".", /r(1\d\.\d)/) { |match|
      match.captures.first
    }.sort
  end

  def latest_version
    versions.reverse_each{ |v|
      begin
        remote_files_matching("r#{v}/bin.tools",/p4ruby/) do
          return v
        end
      rescue
        next
      end
    }
  end

  def remote_files_matching(dir, regex)
    @ftp.ls(dir.to_s).map { |entry|
      if match = entry.match(regex)
        yield match
      else
        nil
      end
    }.reject { |entry|
      entry.nil?
    }
  end

  def download
    begin
      download_p4api
      download_p4ruby
    rescue => e
      binding.pry
      #TODO sort it out for them.
      puts "Failed to download API or p4ruby, please compile manually"
    end
  end

  def download_p4api
    @ftp.chdir(@platform)
    @ftp.getbinaryfile(@p4api_archive, "#{DIST_DIR}/#{@p4api_archive}", 1024)
    @ftp.chdir("..")

    decompress("#{DIST_DIR}/#{@p4api_archive}","#{BUILD_DIR}/")
  end

  def download_p4ruby
    @ftp.chdir(P4RUBY_FTP_DIR)
    @ftp.getbinaryfile(P4RUBY_ARCHIVE, "#{DIST_DIR}/#{P4RUBY_ARCHIVE}", 1024)
    @ftp.chdir("..")

    decompress("#{DIST_DIR}/#{P4RUBY_ARCHIVE}","#{BUILD_DIR}/")
  end

  def decompress(tgz, destination)
    if tgz =~ /\.zip/
      `unzip #{tgz} -d #{destination}`
      return
    end
    Gem::Package::TarReader.new(Zlib::GzipReader.open tgz) do |tar|
      tar.each do |entry|
        if entry.directory?
          puts "Making dir #{File.join(destination, entry.full_name)}"
          unless File.exists?(File.join(destination, entry.full_name))
            Dir.mkdir(File.join(destination, entry.full_name))
          end
        elsif entry.file?
          puts "Making file #{File.join(destination, entry.full_name)}"
          unless File.exists?(File.join(destination, entry.full_name))
            File.open(File.join(destination, entry.full_name), "w") do |f|
              f.write(entry.read)
            end
          end
        elsif entry.header.typeflag == '2'
          #TODO remove if not necessary
          binding.pry
        end
      end
    end
  end

end

i = Installer.new
