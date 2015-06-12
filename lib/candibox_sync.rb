require_relative 'ldap_user'
require_relative 'ldap_group'
require 'thor'
require 'yaml'
require 'openssl'

class CandiboxSync < Thor
  desc "ldap_sync", "Update LDAP user and group attributes with JSON URL or file"
  method_option :json_file, :aliases => "-f", type: :string, 
  desc: "JSON file to update LDAP users and groups. Example format is given in README file"
  method_option :host, :aliases => "-h", type: :string, 
  desc: "Hostname must match with HARID portal settings"
  method_option :box_private_key, :aliases => "-k", type: :string, 
  desc: "Private key must be stored in certs/ folder. Use bin/setup to generate new keypair"
  method_option :secret, :aliases => "-t", type: :string, desc: "HarID registered secret"
  method_option :username, :aliases => "-u", type: :string, desc: "HarID registered API user"
  method_option :server_ca_cert, :aliases => "-s", type: :string, 
  desc: "Portal certificate file must be stored in certs/ folder"

  def ldap_sync
    initialize_ldap unless ActiveLdap::Base.connected?
    case 
      when File.file?(options[:json_file].to_s)
        data           = JSON.parse(File.read(options[:json_file]))
        user_list      = data["users"]
        group_list     = data["groups"]
        deleted_users  = data["deleted_users"]
        deleted_groups = data["deleted_groups"]
        synced_method  = "file"
        synchronize(user_list, group_list, deleted_users, deleted_groups)

      when host && File.file?(box_key) && secret && username
          user_list = get_json_data('users.json')
          p group_list     = get_json_data('groups.json')
          deleted_users  = get_json_data('deleted_users.json')
          deleted_groups = get_json_data('deleted_groups.json')
          synchronize(user_list, group_list, deleted_users, deleted_groups)
      else
        raise ArgumentError, "Missing mandatory configuration"
    end
    puts 'All done.'
  end

  no_commands do
    def synchronize(users, groups, deleted_users, deleted_groups)
      LdapUser.sync_all_to_ldap(users, box_key)
      LdapGroup.sync_all_to_ldap(groups)
      LdapUser.remove_from_ldap(deleted_users)
      LdapGroup.remove_from_ldap(deleted_groups)
      puts "Synchronization completed."
    end
    
    def initialize_ldap
      if File.exist?(config_file)
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
      else
        raise ArgumentError, "Ldap config file does not exist: #{config_file}"
      end
    end

    def smart_add_url_protocol(url)
      unless url[/\Ahttp:\/\//] || url[/\Ahttps:\/\//]
          url = "https://#{url}"
      end
      return url
    end

    def get_json_data(type)
      # http://www.rubyinside.com/nethttp-cheat-sheet-2940.html
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
      puts "Error creating secure connection: #{slerror}"
      exit 1
    end
  end

  private

  def config_file
    @config_file ||= File.expand_path("../config/candibox.yml", __dir__)
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
    @box_key = File.expand_path(options[:box_private_key] || attributes['box_key'].to_s, "certs")
  end

  def portal_cert
    @portal_cert = File.expand_path(options[:server_ca_cert] || attributes['portal_ca_cert'].to_s, "certs")
  end
end
