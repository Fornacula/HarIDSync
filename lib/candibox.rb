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

class Candibox < Thor
  desc "sync", "Update LDAP user and group attributes with HarID JSON API"
  method_option :config_file, :aliases => "-c", type: :string, 
  desc: "Settings YAML file. Without this option candibox.yml is used."
  method_option :host, :aliases => "-h", type: :string, 
  desc: "Hostname must match with HarID portal settings."
  method_option :box_private_key, :aliases => "-k", type: :string, 
  desc: "Private key must be stored in certs/ folder. Use bin/setup to generate new keypair."
  method_option :secret, :aliases => "-t", type: :string, desc: "HarID registered secret."
  method_option :username, :aliases => "-u", type: :string, desc: "HarID registered API user."
  method_option :server_ca_cert, :aliases => "-s", type: :string, 
  desc: "Portal certificate file must be stored in certs/ folder."

  def sync
    mv_cert_dir_files_to_config_dir if File.exists? File.expand_path("../certs/", __dir__)
    check_configuration
    initialize_ldap unless ActiveLdap::Base.connected?
    user_list      = get_json_data('users.json')
    group_list     = get_json_data('groups.json')
    deleted_users  = get_json_data('deleted_users.json')
    deleted_groups = get_json_data('deleted_groups.json')
    synchronize(user_list, group_list, deleted_users, deleted_groups)
    say 'All done.'
  rescue => e
    $stderr.puts e
  end

  desc "setup", "Generates configuration file config/candibox.yml with some default 
  values and new private key or outputs existing keypair public key"
  method_option :config_file, :aliases => "-c", type: :string, 
  desc: "Settings YAML file. Without this option candibox.yml is used."
  method_option :host, :aliases => "-h", type: :string,
  desc: "Set default hostname. Hostname must match with HARID portal settings."
  method_option :box_private_key, :aliases => "-k", type: :string,
  desc: "Use existing private key as default. Existing key must be stored in /certs folder. 
  Use filename without path as option value."
  method_option :secret, :aliases => "-s", type: :string,
  desc: "HarID registered secret."
  method_option :username, :aliases => "-u", type: :string,
  desc: "HarID registered API user."
  
  def setup
    mv_cert_dir_files_to_config_dir if File.exists? File.expand_path("../certs/", __dir__)
    generate_configuration_file unless File.exist?(config_file)
    if File.exist?(box_key)
      say "
  Private key exist in #{box_key}.
  In case you'd like generate new private key you must remove already existing key file first and then run setup again.
      "
      read_public_key
    else
      say '
  Generating new candibox keypair
      '
      generate_key
    end
  end

  desc "read_public_key", "Outputs existing key public key"
  method_option :box_private_key, :aliases => "-k", type: :string, 
  desc: "Private key must be stored in certs/ folder. Use candibox_sync setup to generate new keypair."
  def read_public_key
    if File.file? box_key
      rsa_key = OpenSSL::PKey::RSA.new File.read(box_key)
      say "
    Public key output:

#{rsa_key.public_key}

    Before you can synchronize HarID portal and Candibox you must 
    ask EENet to authorize your newly generated key in HarID portal. 
    Please contact EENet customer support via email eenet@eenet.ee and send them 
    the contents of your public key. 
    
    It can be copied from above.
      "
    else
      $stderr.puts "Private key file does not exist. Run setup to generate new keypair."
    end
  end

  no_commands do
    def mv_cert_dir_files_to_config_dir
      certs_dir = File.expand_path("../certs/", __dir__)
      say "Moving files from certs/ folder to config/"
      cert_files = Dir.glob(File.expand_path("*", certs_dir))
      config_dir = File.expand_path("../config/", __dir__)
      FileUtils.mv cert_files, config_dir, verbose: true
      say "Removing certs/ folder."
      FileUtils.rmdir certs_dir
    end

    def check_configuration
      raise ArgumentError, "Missing mandatory configuration" unless File.exists? config_file
      
      attributes['portal_hostname'] = host
      attributes['secret'] = secret
      attributes['api_user'] = username
      attributes['box_key'] = box_key

      mandatory_attributes =  %w(portal_hostname portal_port api_user secret box_key ldap_host ldap_port 
        ldap_method ldap_base ldap_bind_dn ldap_password)
      
      missing_values = mandatory_attributes.collect {|attr| attr unless attributes[attr]}.compact

      if missing_values.any?
        raise ArgumentError, "Missing mandatory configuration: #{missing_values.join(', ')}"
      end
    end

    def generate_configuration_file
      config_template = File.expand_path("../config/candibox.yml.dist", __dir__)
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
      uri          = URI.parse(smart_add_url_protocol("#{host}/api/v1/#{type}"))
      http         = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      cert_store   = OpenSSL::X509::Store.new

      if File.file?(portal_cert)
        cert_store.add_file portal_cert
      else
        # Try to use system defaults
        cert_store.set_default_paths
      end
      http.cert_store = cert_store
      
      request = Net::HTTP::Get.new(uri.request_uri)

      if secret && username
        request.basic_auth(username, secret)
      end

      response = http.request(request)
      case response
        when Net::HTTPSuccess then
          json_data = JSON.parse(response.body)
          return json_data
        else
          raise "HTTP Error #{response.code} - #{response.message}"
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
        base: attributes["ldap_base"],
        bind_dn: attributes["ldap_bind_dn"],
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
      LdapGroup.sync_all_to_ldap(groups)
      LdapUser.remove_from_ldap(deleted_users)
      LdapGroup.remove_from_ldap(deleted_groups)
      say "Synchronization completed."
    end
  end

  private

  def generate_key
    rsa_key = OpenSSL::PKey::RSA.new(2048)
    open box_key, 'w' do |io| io.write rsa_key.to_pem end
    say "
  Generated new private key file to #{box_key}
    "
    read_public_key
  end

  def config_file
    @config_file = File.expand_path("../config/#{options[:config_file] || 'candibox.yml'}", __dir__)
  end

  def attributes
    if File.exist?(config_file)
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
    @box_key = File.expand_path("../config/#{options[:box_private_key] || attributes['box_key'].to_s}", __dir__)
  end

  def portal_cert
    @portal_cert = File.expand_path("../config/#{options[:server_ca_cert] || attributes['portal_ca_cert'].to_s}", __dir__)
  end
end
