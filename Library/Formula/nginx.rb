require 'formula'

class Nginx < Formula
  class NginxModule
    attr_accessor :name, :url, :description, :version

    def initialize(name, version, description, url, options={})
      @name        = name
      @url         = url
      @version     = version
      @description = description
      @options     = options
    end # initialize(name, url, description)

    def to_options_array
      [option_switch_name, option_description]
    end # to_options_array

    def option_switch_name
      @option_switch_name ||= "--with-#{dasherized_name}-module"
    end # option_switch_name

    def option_description
      "Compile with #{description} (version #{version})"
    end # option_description

    def brew
      download_strategy.fetch
      download_strategy.stage
    end # brew

    def nginx_configuration_argument
      "--add-module=./#{module_dirname}"
    end # nginx_configuration_argument

    def has_dependencies?
      dependencies.length > 0
      @options[:depends_on] and @options[:depends_on].length > 0
    end # has_dependencies?

    def dependencies
      @dependencies ||= (@options[:depends_on] || []).map { |d| d.to_s }
    end # dependencies

    #
    # To make modules comparable
    #
    def hash
      [name, url].hash
    end # hash

    def eql?(other)
      self == other
    end # eql?(other)

    def ==(other_module)
      return false unless other_module.kind_of?(self.class)

      other_module.name == self.name and other_module.url == self.url
    end # ==(other_module)

    protected

    def download_strategy
      @download_strategy ||= CurlDownloadStrategy.new(url, name, version, {})
    end # download_strategy

    def module_filename
      @module_filename ||= url.split('/').last
    end # module_filename

    def module_dirname
      @module_dirname ||= (@options[:module_dirname] || module_filename.sub(".tar.gz", ""))
    end # module_dirname

    def dasherized_name
      name.to_s.gsub('_', '-')
    end # dasherized_name
  end # NginxModule
  
  module Modules
    def self.included(host)
      host.extend(ClassMethods)
      host.__send__(:include, InstanceMethods)
    end # self.included(host)

    module ClassMethods

      #
      # Use this method to define optional modules for base nginx distribution
      # Positional arguments are self-descriptional.
      # Available options:
      #   * :module_dirname -- custom dirname of the module which will be usefull with modules
      #       distributes as a part of the bigger distribution. For example uwsgi-module
      #       which is bundled with the main uwsgi distribution
      #
      #   * :depends_on -- allow to specify homebrew dependencies which should
      #       be resolved before installation of the module. For example uwsgi-module depends
      #       on the uwsgi homebrew package
      def nginx_module(name, version, description, url, options = {})
        available_modules << NginxModule.new(name, version, description, url, options)
      end # nginx_module(name, description, url)

      def available_modules
        @available_modules ||= []
      end # available_modules

      def enabled_modules
        available_modules.uniq.select do |mod|
          ARGV.include?(mod.option_switch_name)
        end
      end # enabled_modules

      def enabled_modules_with_dependencies
        enabled_modules.select { |mod| mod.has_dependencies? }
      end # enabled_modules_with_dependencies
    end # module ClassMethods

    module InstanceMethods
      def options_for_available_modules
        self.class.available_modules.uniq.map { |mod| mod.to_options_array }
      end # options_for_available_modules

      def enabled_nginx_modules
        self.class.enabled_modules
      end # enabled_nginx_modules
    end # module InstanceMethods
  end # module Modules
end # class Nginx

class Nginx
  homepage 'http://nginx.org/'
  url 'http://nginx.org/download/nginx-1.0.2.tar.gz'
  md5 '8a528ccaab3ddba84e72443fa40b19e7'

  depends_on 'pcre'

  skip_clean 'logs'

  include Nginx::Modules

  nginx_module :upload, '2.2.0', 'upload module by Valery Kholodkov', 'http://www.grid.net.ru/nginx/download/nginx_upload_module-2.2.0.tar.gz'
  nginx_module :upload_progress, '0.8.2.0', 'upload progress module by Brice Figureau', 'http://cloud.github.com/downloads/Audish/nginx-upload-progress-module/nginx-upload-progress-module-v0.8.2.tar.gz'
  nginx_module :http_push, '0.962', 'HTTP push module by Leo Ponomarev', 'http://pushmodule.slact.net/downloads/nginx_http_push_module-0.692.tar.gz'

  enabled_modules_with_dependencies.each do |mod|
    mod.dependencies.each do |module_dependency|
      depends_on module_dependency
    end
  end

  def patches
    # Changes default port to 8080
    # Set configure to look in homebrew prefix for pcre
    DATA
  end

  def options
    [
     ['--with-passenger', "Compile with support for Phusion Passenger module"],
     ['--with-webdav',    "Compile with support for WebDAV module"],
     ['--with-status',    "Compile with support for HTTP status module"]
    ] +
      options_for_available_modules
  end

  def passenger_config_args
      passenger_root = `passenger-config --root`.chomp

      if File.directory?(passenger_root)
        return "--add-module=#{passenger_root}/ext/nginx"
      end

      puts "Unable to install nginx with passenger support. The passenger"
      puts "gem must be installed and passenger-config must be in your path"
      puts "in order to continue."
      exit
  end

  def install
    args = ["--prefix=#{prefix}", "--with-http_ssl_module", "--with-pcre",
            "--conf-path=#{etc}/nginx/nginx.conf", "--pid-path=#{var}/run/nginx.pid",
            "--lock-path=#{var}/nginx/nginx.lock"]
    args << passenger_config_args if ARGV.include? '--with-passenger'
    args << "--with-http_dav_module" if ARGV.include? '--with-webdav'
    args << "--with-http_stub_status_module" if ARGV.include? '--with-status'

    enabled_nginx_modules.each do |mod|
      mod.brew

      args << mod.nginx_configuration_argument
    end

    system "./configure", *args
    system "make install"

    (prefix+'org.nginx.plist').write startup_plist
  end

  def caveats
    <<-CAVEATS
In the interest of allowing you to run `nginx` without `sudo`, the default
port is set to localhost:8080.

If you want to host pages on your local machine to the public, you should
change that to localhost:80, and run `sudo nginx`. You'll need to turn off
any other web servers running port 80, of course.

You can start nginx automatically on login with:
    mkdir -p ~/Library/LaunchAgents
    cp #{prefix}/org.nginx.plist ~/Library/LaunchAgents/
    launchctl load -w ~/Library/LaunchAgents/org.nginx.plist

    CAVEATS
  end

  def startup_plist
    return <<-EOPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>org.nginx</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>UserName</key>
    <string>#{`whoami`.chomp}</string>
    <key>ProgramArguments</key>
    <array>
        <string>#{sbin}/nginx</string>
        <string>-g</string>
        <string>daemon off;</string>
    </array>
    <key>WorkingDirectory</key>
    <string>#{HOMEBREW_PREFIX}</string>
  </dict>
</plist>
    EOPLIST
  end
end

__END__
--- a/auto/lib/pcre/conf
+++ b/auto/lib/pcre/conf
@@ -155,6 +155,22 @@ else
             . auto/feature
         fi
 
+        if [ $ngx_found = no ]; then
+
+            # Homebrew
+            HOMEBREW_PREFIX=${NGX_PREFIX%Cellar*}
+            ngx_feature="PCRE library in ${HOMEBREW_PREFIX}"
+            ngx_feature_path="${HOMEBREW_PREFIX}/include"
+
+            if [ $NGX_RPATH = YES ]; then
+                ngx_feature_libs="-R${HOMEBREW_PREFIX}/lib -L${HOMEBREW_PREFIX}/lib -lpcre"
+            else
+                ngx_feature_libs="-L${HOMEBREW_PREFIX}/lib -lpcre"
+            fi
+
+            . auto/feature
+        fi
+
         if [ $ngx_found = yes ]; then
             CORE_DEPS="$CORE_DEPS $REGEX_DEPS"
             CORE_SRCS="$CORE_SRCS $REGEX_SRCS"
--- a/conf/nginx.conf
+++ b/conf/nginx.conf
@@ -33,7 +33,7 @@
     #gzip  on;

     server {
-        listen       80;
+        listen       8080;
         server_name  localhost;

         #charset koi8-r;
