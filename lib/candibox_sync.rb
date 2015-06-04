require_relative 'ldap_user'
require_relative 'ldap_group'
require 'thor'
require 'yaml'

class CandiboxSync < Thor
  desc "ldap_sync", "Update LDAP user and group attributes with JSON URL or file"
  method_option :json_file, :aliases => "-f", type: :string, 
  desc: "JSON file to update LDAP users and groups. Example format is given in README file"
  method_option :host, :aliases => "-h", type: :string, 
  desc: "Hostname must match with HARID portal settings"
  method_option :box_private_key, :aliases => "-k", type: :string, 
  desc: "Private key must be stored in certs folder"
  method_option :box_cert, :aliases => "-c", type: :string, desc: "Certificate file must be stored in certs folder"
  method_option :server_ca_cert, :aliases => "-s", type: :string, desc: "Certificate file must be stored in certs folder"

  def ldap_sync
    initialize_ldap unless ActiveLdap::Base.connected?

    if options[:json_file].present?
      if File.exist?(options[:json_file])
        data           = JSON.parse(File.read(options[:json_file]))
        user_list      = data["users"]
        group_list     = data["groups"]
        deleted_users  = data["deleted_users"]
        deleted_groups = data["deleted_groups"]
      else
        raise ArgumentError, "JSON file does not exists: '#{options[:json_file]}'"
      end
    else
      if host.present?
        user_list       = get_json_data('users.json')
        group_list      = get_json_data('groups.json')
        deleted_users   = get_json_data('deleted_users.json')
        deleted_groups  = get_json_data('deleted_groups.json')
      else
        raise ArgumentError, "Domain base or JSON file must be given as arguments"
      end
    end

    LdapUser.sync_all_to_ldap(user_list, box_key)
    LdapGroup.sync_all_to_ldap(group_list)
    LdapUser.remove_from_ldap(deleted_users)
    LdapGroup.remove_from_ldap(deleted_groups)
    puts "Synchronization completed."
  end

  no_commands do
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
        raise ArgumentError, "Ldap config file does not exists: '#{config_file}'"
      end
    end

    def smart_add_url_protocol(url)
      unless url[/\Ahttp:\/\//] || url[/\Ahttps:\/\//]
          url = "https://#{url}"
      end
      return url
    end

    def get_json_data(type)
      uri          = URI.parse(smart_add_url_protocol("#{host}/api/v1/#{type}"))
      http         = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      if box_cert.present? && box_key.present?
        cert      = File.read(File.expand_path(box_cert, "certs"))
        p_key     = File.read(File.expand_path(box_key, "certs"))
        http.cert = OpenSSL::X509::Certificate.new(cert)
        http.key  = OpenSSL::PKey::RSA.new(p_key)
      else
        puts "Warning! Box cert and key was not given as argument."
      end

      cert_store = OpenSSL::X509::Store.new
      if portal_cert.present?
        cert_store.add_file File.expand_path(portal_cert, "certs")
      else
        # Try to use system defaults
        cert_store.set_default_paths
      end
      http.cert_store  = cert_store
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      uri.request_uri
      request          = Net::HTTP::Get.new(uri.request_uri)
      response         = http.request(request)
      
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
    @config_file ||= File.expand_path("../config/candibox.yml", Pathname.new(__dir__).realpath)
  end

  def attributes
    if File.exist?(config_file)
      @attributes ||= YAML.load(File.read(config_file))
    end
  end

  def host
    @host = options[:host] || attributes['portal_hostname']
  end

  def box_key
    @box_key = options[:box_private_key] || attributes['box_key']
  end
  
  def box_cert
    @box_cert = options[:box_cert] || attributes['box_cert']
  end

  def portal_cert
    @portal_cert = options[:server_ca_cert] || attributes['portal_ca_cert']
  end
end
