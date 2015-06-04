require 'pathname'
require 'yaml'
require 'socket'
require 'openssl'

ROOT_DIR    = File.expand_path("../", Pathname.new(__dir__).realpath)
CERT_DIR    = File.expand_path("certs", ROOT_DIR)
config_file = File.expand_path("config/candibox.yml", ROOT_DIR)

def generate_cert_and_key(attributes, key_path, cert_path)
  # Certificate information
  country_name = 'EE'
  hostname     = Socket.gethostname

  # Create key
  key1 = OpenSSL::PKey::RSA.new(2048)
  open(key_path, "w") do |io| io.write(key1.to_pem) end
  puts "Generated new private key to #{key_path} "
  
  # Create cert
  name = OpenSSL::X509::Name.parse("CN=#{hostname}/C=#{country_name}")
  cert = OpenSSL::X509::Certificate.new()
  cert.version     = 2
  cert.serial      = 0
  cert.not_before  = Time.now
  cert.not_after   = cert.not_before + 3600
  cert.public_key  = key1.public_key
  cert.subject     = name
  File.open(cert_path, "wb") { |f| f.print cert.to_pem }
  puts "Generated new self-signed certificate to #{cert_path} "
  puts "Certificate expires in: #{cert.not_after}"
  puts "Certificate file output:"
  puts
  File.readlines(cert_path).each do |line|
    puts line
  end
  puts "
  Before you can synchronize HarID portal and Candibox you must 
  ask EENet to authorize your newly generated certificate in HarID portal. 
  Please contact EENet customer support via email eenet@eenet.ee and send them 
  the contents of your certificate file. 
  
  It can be copied from above."
end

if File.exist?(config_file)
  attributes = YAML.load_file(config_file)
  key        = File.expand_path("#{attributes['box_key']}", CERT_DIR)
  cert       = File.expand_path("#{attributes['box_cert']}", CERT_DIR)
  
  puts 'Checking certificate and key'
  if File.exist?(cert) && File.exist?(key)
    puts 'Nothing to do. Certificate and keyfile already exists.'
  else
    puts 'Generate candibox certificate and key'
    generate_cert_and_key(attributes, key, cert)
  end
else
  raise ArgumentError, "Config file does not exists: '#{config_file}'"
end
