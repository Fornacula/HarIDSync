require 'active_ldap'
require 'base64'
require 'openssl'
class LdapUser < ActiveLdap::Base
  ldap_mapping dn_attribute: 'cn', prefix: 'cn=Users',
               classes: ['top', 'organizationalPerson', 'person', 'user'],
               scope: :one

  AUXILIARY_CLASSES = %w(posixAccount inetOrgPerson)
  attr_accessor :user

  # Active Directory userAccountControl flag values
  ACCOUNTDISABLE       = 0x0002
  NORMAL_ACCOUNT       = 0x0200

  # Use AES with 256-bit key in CBC mode (but still 128-bit blocks)
  CIPHER = 'AES-256-CBC'
  # AES uses 128-bit (16 byte) blocks
  IV_SIZE = 16

  class << self
    attr_accessor :private_key
  end

  def add_auxiliary_classes
    AUXILIARY_CLASSES.each do |ac|
      self.classes.include?(ac) or self.add_class(ac)
    end 
  end

  def set_attributes!
    raise ArgumentError, "User is not set" if self.user.blank?
    attributes_from_user.each do |attr, value|
      self.send "#{attr}=", value
    end
  end
  
  def full_name
    "#{user['first_name']} #{user['last_name']}".rstrip
  end

  # Return UNIX style GECOS info
  def generate_gecos
    data =[]
    data << self.full_name
    data << user["primary_phone"]
    data << user["primary_email"]

    data.compact.join(",")
  end

  def object_category
    "CN=Person,CN=Schema,CN=Configuration,#{ActiveLdap::Base.base}"
  end

  # Set userAccountControl
  def user_account_control
    flags = NORMAL_ACCOUNT
    flags += ACCOUNTDISABLE unless self.user["active"]
    flags
  end

  # provide map to get ldap attributes from current object
  # Supports both symbols and lambdas (gives self as first attribute)
  def ldap_attribute_map
    {
        'uid'                         => 'uid',
        'sAMAccountName'              => 'uid',
        'uidNumber'                   => 'uid_number',
        'gidNumber'                   => 'gid_number',
        'cn'                          => Proc.new{self.generate_cn},
        'givenName'                   => 'first_name',
        'sn'                          => 'last_name',
        'telephoneNumber'             => 'primary_phone',
        'otherTelephone'              => 'phone_numbers',
        'mail'                        => 'primary_email',
        'unicodePwd'                  => Proc.new{self.ad_encoded_password},
        'homeDirectory'               => 'homedir',
        'loginShell'                  => 'shell',
        'gecos'                       => Proc.new{self.generate_gecos},
        'objectCategory'              => Proc.new{object_category},
        'userAccountControl'          => Proc.new{user_account_control},
    }
  end

  # Return hash of attributes with LDAP naming
  def attributes_from_user
    user_attributes = {}
    self.ldap_attribute_map.each do |ldap_attr, attr|
      user_attributes[ldap_attr] = attr.is_a?(Proc) ? attr.call(self.user) : self.user[attr]
    end
    user_attributes
  end

  def generate_cn
    if self.new_record? || self.cn !~ /#{self.full_name}\d*/
      namesakes = LdapUser.find(:all, filter: { :cn =>"#{self.full_name}*".rstrip})
      max_used_seq = namesakes.map{|user| user.cn[/\d+/].to_i}.max || 0
      nextval = max_used_seq > 0 ? max_used_seq + 1 : nil
      return "#{self.full_name}#{nextval}"
    else
      return self.cn
    end
  end

  # Encode plain-text password into AD format
  def ad_encoded_password
    password = decrypted_password
    return nil if password.to_s.empty?
    return "\"#{password}\"".encode(Encoding.find('UTF-16LE'))
  end

  # Decrypt password
  def decrypted_password
    cpw = user["password_crypt"]
    return nil if cpw.nil?

    self.class.private_key.private_decrypt(Base64.decode64(cpw))
  end

  def self.find_ldap_user(uid)
    LdapUser.find(:first, "sAMAccountName=#{uid}") || LdapUser.new(uid)
  end

  def sync
    begin
      self.add_auxiliary_classes
      self.set_attributes!
      self.save!
    rescue => e
      puts "Error syncing user to LDAP: #{e}"
      puts self.errors.full_messages
      puts "error (See log for more details)"
    end
  end

  def self.sync_all_to_ldap(users, private_key_file)
    puts "Syncing database users to LDAP"
    begin
      key = OpenSSL::PKey::RSA.new File.read(File.expand_path(private_key_file, "certs"))
      self.private_key = key
    rescue => e
      puts "Error opening private key file: #{e}"
      exit 1
    end
    users.each do |user|
      ldap_user = LdapUser.find_ldap_user(user["uid"])
      ldap_user.user = user
      ldap_user.sync
    end
  end

  def self.remove_from_ldap(users)
    puts "Removing deleted users from LDAP"
    users.each do |user|
      begin
        ldap_user = LdapUser.find(:first, :filter => "(&(sAMAccountName=#{user['uid']})(uidNumber=#{user['uid_number']}))")
        if ldap_user.present?
          ldap_user.destroy
        end
      rescue => e
        puts "Error occured while deleting user #{user['uid']} from LDAP: #{e}"
        puts "error (See log for more details)"
      end
    end
  end
end
