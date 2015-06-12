require 'pathname'
require 'yaml'
require 'socket'
require 'openssl'
config_file = File.expand_path("../config/candibox.yml", __dir__)

def generate_cert_and_key(attributes, pri_key_path, pub_key_path)
  # Create keypair
  rsa_key = OpenSSL::PKey::RSA.new(2048)
  open(pri_key_path, "w") do |io| io.write(rsa_key.to_pem) end
  puts "Generated new private key to #{pri_key_path} "
  open pub_key_path, 'w' do |io| io.write rsa_key.public_key end
  puts "Generated new public key to #{pub_key_path} "

  puts "Public key file output:"
  puts
  puts rsa_key.public_key
  puts "
  Before you can synchronize HarID portal and Candibox you must 
  ask EENet to authorize your newly generated key in HarID portal. 
  Please contact EENet customer support via email eenet@eenet.ee and send them 
  the contents of your public key file. 
  
  It can be copied from above.
  "
end

if File.exist?(config_file)
  attributes = YAML.load_file(config_file)
  key        = File.expand_path("../certs/#{attributes['box_key']}", __dir__)
  public_key = File.expand_path("../certs/#{attributes['box_pub']}", __dir__)
  
  puts 'Checking certificate and key'
  if File.exist?(public_key) && File.exist?(key)
    puts 'Nothing to do. Certificate and keyfile already exists.'
  else
    puts 'Generate candibox certificate and key'
    generate_cert_and_key(attributes, key, public_key)
  end
else
  raise ArgumentError, "Config file does not exists: '#{config_file}'"
end
