require 'pathname'
require 'yaml'
require 'socket'
require 'openssl'

def read_public_key(private_key)
  puts "
  Public key output:

  #{private_key.public_key}

  Before you can synchronize HarID portal and Candibox you must 
  ask EENet to authorize your newly generated key in HarID portal. 
  Please contact EENet customer support via email eenet@eenet.ee and send them 
  the contents of your public key. 
  
  It can be copied from above.
  "
end

def generate_key(pri_key_path)
  rsa_key = OpenSSL::PKey::RSA.new(2048)
  open(pri_key_path, "w") do |io| io.write(rsa_key.to_pem) end
  puts "Generated new private key file to #{pri_key_path} "
  read_public_key(rsa_key.public_key)
end

def check_configuration
  tries ||= 2

  config_file     = File.expand_path("../config/candibox.yml", __dir__)
  config_template = File.expand_path("../config/candibox.yml.dist", __dir__)
  attributes      = YAML.load_file(config_file)
  key             = File.expand_path("../certs/#{attributes['box_key']}", __dir__)

  if File.exist?(key)
    private_key = OpenSSL::PKey::RSA.new File.read(key)
    puts "
    Private key already exist. 
    In case you'd like generate new private key you must remove already existing key file first and then run setup again.
    #{key} 
    "
    read_public_key(private_key.public_key)
  else
    puts 'Generating new candibox keypair'
    generate_key(key)
  end
  
rescue Exception => e
  if (tries -= 1) > 0
    sample_attributes = YAML::load_file(config_template)

    attributes = {
      "portal_hostname" => nil,
      "portal_port" => sample_attributes['portal_port'],
      "api_user" => nil,
      "secret" => nil,
      "box_key" => sample_attributes['box_key'],
      "ldap_host" => nil,
      "ldap_port" => nil,
      "ldap_method" => sample_attributes['ldap_method'],
      "ldap_base" => nil,
      "ldap_bind_dn" => nil,
      "ldap_password" => nil,
      "allow_anonymous" => sample_attributes['allow_anonymous'],
    }

    File.open(config_file, 'w') {|f| f.write attributes.to_yaml }
    retry
  else
    raise ArgumentError, "Config file does not exist: '#{config_file}'"
  end
end

check_configuration