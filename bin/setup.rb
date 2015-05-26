require 'pathname'
require 'yaml'
require 'socket'
ROOT_DIR = File.expand_path("../", Pathname.new(__dir__).realpath)
CERT_DIR = File.expand_path("certs", ROOT_DIR)

# Certificate information
COUNTRY_NAME = 'EE'
hostname = Socket.gethostname

config_file =  File.expand_path("config/candibox.yml", ROOT_DIR)
attributes = YAML.load_file(config_file)
box_sert =  File.expand_path("certs/#{attributes['box_cert']}", ROOT_DIR)

if File.exist?(config_file)
  # Generate candibox certificate and key
  system("
    cd #{CERT_DIR}
    openssl req -subj '/CN=#{hostname}/C=#{COUNTRY_NAME}' -new -newkey rsa:2048 -days 365 -nodes -x509 -keyout #{attributes['box_key']} -out #{attributes['box_cert']}
    ") unless File.exist?(box_sert)
else
  raise ArgumentError, "Config file does not exists: '#{config_file}'"
end
