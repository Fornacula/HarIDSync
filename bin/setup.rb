require 'pathname'
require 'yaml'
require 'socket'
require 'openssl'

ROOT_DIR = File.expand_path("../", Pathname.new(__dir__).realpath)
CERT_DIR = File.expand_path("certs", ROOT_DIR)

config_file =  File.expand_path("config/candibox.yml", ROOT_DIR)
attributes = YAML.load_file(config_file)
KEY_PATH = File.expand_path("#{attributes['box_key']}", CERT_DIR)
CERT_PATH =  File.expand_path("#{attributes['box_cert']}", CERT_DIR)

def generate_cert_and_key(attributes)
  # Certificate information
  country_name = 'EE'
  hostname = Socket.gethostname

  # Create key
  key1 = OpenSSL::PKey::RSA.new(2048)
  open(KEY_PATH, "w") do |io| io.write(key1.to_pem) end
  puts "Generated new private key to #{KEY_PATH} "

  # Create cert
  name = OpenSSL::X509::Name.parse("CN=#{hostname}/C=#{country_name}")
  cert = OpenSSL::X509::Certificate.new()
  cert.version = 2
  cert.serial = 0
  cert.not_before = Time.now
  cert.not_after = cert.not_before + 3600
  cert.public_key = key1.public_key
  cert.subject = name
  File.open(CERT_PATH, "wb") { |f| f.print cert.to_pem }
  puts "Generated new self-signed certificate to #{CERT_PATH} "
  puts "Certificate expires in: #{cert.not_after}"
end

if File.exist?(config_file)
  puts 'Checking certificate and key'
  if File.exist?(CERT_PATH) && File.exist?(KEY_PATH)
    puts 'Nothing to do. Certificate and keyfile already exists.'
  else
    puts 'Generate candibox certificate and key'
    generate_cert_and_key(attributes)
  end
else
  raise ArgumentError, "Config file does not exists: '#{config_file}'"
end
