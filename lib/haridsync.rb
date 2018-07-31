require_relative 'haridsync_helpers'
require_relative 'ldap_user'
require_relative 'ldap_group'
require 'thor'
require 'yaml'
require 'openssl'
require 'net/https'
require 'uri'
require 'pathname'
require 'socket'
require 'fileutils'

class Haridsync < Thor
  desc "sync", "Update LDAP user and group attributes with HarID JSON API"
  method_option :config_file, :aliases => "-c", type: :string, 
  desc: "Settings YAML file. Without this option haridsync.yml is used."
  method_option :host, :aliases => "-h", type: :string, 
  desc: "Hostname must match with HarID portal settings."
  method_option :box_private_key, :aliases => "-k", type: :string, 
  desc: "Private key must be stored in config/ folder. Use bin/setup to generate new keypair."
  method_option :secret, :aliases => "-t", type: :string, desc: "HarID registered secret."
  method_option :username, :aliases => "-u", type: :string, desc: "HarID registered API user."
  method_option :server_ca_cert, :aliases => "-s", type: :string, 
  desc: "Portal certificate file must be stored in config/ folder."

  def sync
    check_configuration
    initialize_ldap unless ActiveLdap::Base.connected?
    user_list      = get_json_data('ad_users.json')
    group_list     = get_json_data('ad_groups.json')
    deleted_users  = get_json_data('deleted_ad_users.json')
    deleted_groups = get_json_data('deleted_ad_groups.json')
    synchronize(user_list, group_list, deleted_users, deleted_groups)
    say 'All done.'
  rescue => e
    $stderr.puts e
  end

  desc "setup", "Generates configuration file config/haridsync.yml with some default 
  values and new private key or outputs existing keypair public key"
  method_option :config_file, :aliases => "-c", type: :string, 
  desc: "Settings YAML file. Without this option haridsync.yml is used."
  method_option :host, :aliases => "-h", type: :string,
  desc: "Set default hostname. Hostname must match with HARID portal settings."
  method_option :box_private_key, :aliases => "-k", type: :string,
  desc: "Use existing private key as default. Existing key must be stored in config/ folder. 
  Use filename without path as option value."
  method_option :secret, :aliases => "-s", type: :string,
  desc: "HarID registered secret."
  method_option :username, :aliases => "-u", type: :string,
  desc: "HarID registered API user."
  
  def setup
    generate_configuration_file unless File.file?(config_file)
    if File.file?(box_key)
      say "
    Private key exists in #{box_key}
    In case you'd like to generate a new private key you must remove already existing key file first and then run setup again.
      "
      read_public_key
    else
      generate_key
    end
  end

  desc "read_public_key", "Outputs existing key public key"
  method_option :box_private_key, :aliases => "-k", type: :string, 
  desc: "Output public key."
  def read_public_key
    if File.file? box_key
      rsa_key = OpenSSL::PKey::RSA.new File.read(box_key)
      say "

    STEP 1: Copy public key into HarID portal: 

    Public key output (from private key at #{box_key}):

#{rsa_key.public_key}
    Before you can synchronize HarID portal you must 
    enter your newly generated public key into HarID portal. 

    Documentations for managing API keys at HarID portal:
    In English: https://harid.ee/docs/en/how_to_manage_api_users_for_harid_ad_ldap_sync.html
    Eesti keeles: https://harid.ee/docs/et/kuidas_lisada_api_kasutaja_harid_ad_ldap_andmevahetuseks.html

    STEP 2: Configure and enable HarIDSync utility:
    
    Please configure HarIDSync utility at #{config_file}

    Please contact HarID customer support if you need any help.
      "
    else
      $stderr.puts "Private key file does not exist. Run setup to generate new keypair."
    end
  end

  no_commands do
    def check_configuration
      raise ArgumentError, "Missing mandatory configuration in #{config_file}" unless File.file? config_file
      
      missing_files = [:config_file, :box_key].select{|k| File.file?(send(k).to_s) == false}
      missing_options = [:host, :secret, :username].select{|k| send(k).nil?}

      mandatory_attributes = %w(portal_port ldap_host ldap_port ldap_method ldap_base ldap_bind_dn ldap_password)
      missing_attributes = mandatory_attributes.collect {|attr| attr unless attributes[attr]}.compact

      missing_values = missing_files + missing_options + missing_attributes
      
      if missing_values.any?
        raise ArgumentError, "Missing mandatory configuration: #{missing_values.join(', ')}. Try running 'haridsync setup'."
      end

      if attributes['haridsync_enabled'].blank? || attributes['haridsync_enabled'] == 'false'
        raise ArgumentError, "HarIDSync is disabled. You can enable it at #{config_file}"
      end
    end

    def generate_configuration_file
      config_template = File.expand_path("../config/haridsync_example.yml", __dir__)
      FileUtils.cp config_template, config_file
      attributes = YAML::load_file(config_file)
      case
        when options.any?
          case
            when options[:config_file]
              attributes["box_key"] = "#{options[:config_file].chomp(File.extname(options[:config_file]))}.key"
            when options[:host]
              attributes["portal_hostname"] = options[:host]
            when options[:username]
              attributes["api_user"] = options[:username]
            when options[:secret]
              attributes["secret"] = options[:secret]              
            when options[:box_private_key]
              attributes["box_key"] = options[:box_private_key]
          end
          File.open(config_file, 'w') {|f| f.write attributes.to_yaml }
      end
    end

    def get_json_data(type)
      uri          = URI.parse(smart_add_url_protocol("#{host}/api/v2/#{type}"))
      http         = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      cert_store = OpenSSL::X509::Store.new
      if File.file?(portal_ca_cert)
        cert_store.add_file portal_ca_cert
      else
        # Try to use system defaults
        cert_store.set_default_paths
      end
      http.cert_store = cert_store

      if host == 'l.harid' # dev mode
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      
      url = smart_add_url_protocol("#{host}#{uri.request_uri}")
      puts "GET request: #{url}"
      request = Net::HTTP::Get.new(url)

      if secret && username
        request.basic_auth(username, secret)
      end

      response = http.request(request)
      case response
        when Net::HTTPSuccess then
          json_data = JSON.parse(response.body)
          return json_data
        else
          raise "\nHTTP Error #{response.code} - #{response.message}\n\n#{response.body}"
      end
    rescue OpenSSL::SSL::SSLError => slerror
      $stderr.puts "Error creating secure connection: #{slerror}"
      exit 1
    end

    def initialize_ldap
      ldap_config = {
        host: attributes["ldap_host"],
        port: attributes["ldap_port"],
        method: attributes["ldap_method"],
        base: HaridsyncHelpers.ensure_uppercase_dn_component(attributes["ldap_base"]),
        bind_dn: HaridsyncHelpers.ensure_uppercase_dn_component(attributes["ldap_bind_dn"]),
        password: attributes["ldap_password"],
        allow_anonymous: attributes["allow_anonymous"]
      }

      ActiveLdap::Base.setup_connection ldap_config
      ActiveLdap::Base.connection
      raise ConnectionError, "Could not establish LDAP connection." unless ActiveLdap::Base.connected?
    end

    def smart_add_url_protocol(url)
      unless url[/\Ahttp:\/\//] || url[/\Ahttps:\/\//]
          url = "https://#{url}"
      end
      return url
    end

    def synchronize(users, groups, deleted_users, deleted_groups)
      LdapUser.sync_all_to_ldap(users, box_key)
      LdapGroup.sync_all_to_ldap(groups, box_key)
      LdapUser.remove_from_ldap(deleted_users)
      LdapGroup.remove_from_ldap(deleted_groups)
      say "Synchronization completed."
    end
  end

  private
  
  def generate_key
    rsa_key = OpenSSL::PKey::RSA.new(2048)
    open box_key, 'w' do |io| io.write rsa_key.to_pem end

    if debian_package?
      File.chmod(0600, box_key)
      FileUtils.chown('haridsync', 'haridsync', box_key)
    end

    say "
  Generated a new private key file to #{box_key}
    "
    read_public_key
  end

  def config_file
    @config_file ||= "#{config_path}/#{options[:config_file] || 'haridsync.yml'}"
  end

  def debian_package?
    @debian_package ||= 
      [ENV['ENCLOSE_IO_WORKDIR'], File.expand_path(__FILE__)].include?('/usr/share/haridsync')
  end

  def config_path
    return "/etc/haridsync" if debian_package?
    return "#{ENV['ENCLOSE_IO_WORKDIR']}/config" if ENV['ENCLOSE_IO_WORKDIR'].present?
    File.expand_path("../config", __dir__)
  end

  def attributes
    if File.file?(config_file)
      @attributes ||= YAML.load(File.read(config_file))
    end
  end

  def host
    @host = options[:host] || attributes['portal_hostname']
  end

  def secret
    @secret = options[:secret] || attributes['secret']
  end

  def username
    @username = options[:username] || attributes['api_user']
  end

  def box_key
    @box_key ||= "#{config_path}/#{options[:box_private_key] || attributes['box_key'] || 'haridsync_private.key'}"
  end

  def portal_ca_cert
    @portal_ca_cert ||= "#{config_path}/#{options[:portal_ca_cert] || attributes['portal_ca_cert'] || 'cacert.pem'}"
  end
end
