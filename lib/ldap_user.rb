require 'active_ldap'
require 'base64'
require 'openssl'

class LdapUser < ActiveLdap::Base
  GEN_PW_LENGTH = 24
  DEFAULT_PREFIX = 'CN=Users'

  ldap_mapping dn_attribute: 'CN', prefix: '',
               classes: ['top', 'organizationalPerson'],
               scope: :sub

  AUXILIARY_CLASSES = %w(posixAccount inetOrgPerson)
  attr_accessor :user

  # Active Directory userAccountControl flag values
  ACCOUNTDISABLE       = 0x0002
  NORMAL_ACCOUNT       = 0x0200

  class << self
    attr_accessor :private_key

    def find_or_create_ldap_user(uid)
      LdapUser.find(:first, "sAMAccountName=#{uid}") || LdapUser.new(uid)
    end

    def sync_all_to_ldap(users, private_key_file)
      puts "Syncing HarID AD/LDAP users to your LDAP server"
      begin
        key = OpenSSL::PKey::RSA.new File.read(private_key_file)
        self.private_key = key
      rescue => e
        $stderr.puts "Error opening private key file: #{e}"
        exit 1
      end
      users.each do |user|
        ldap_user = LdapUser.find_or_create_ldap_user(user["uid"])
        puts ldap_user.inspect
        ldap_user.user = user
        ldap_user.sync
      end
    end

    def remove_from_ldap(users)
      puts "Removing deleted users from LDAP"
      users.each do |user|
        begin
          ldap_user = LdapUser.find(:first, :filter => "(&(sAMAccountName=#{user['uid']})(uidNumber=#{user['uid_number']}))")
          if ldap_user.present?
            ldap_user.destroy
          end
        rescue => e
          $stderr.puts "Error occured while deleting user #{user['uid']} from LDAP: #{e}"
          $stderr.puts "error (See log for more details)"
        end
      end
    end
  end

  def add_auxiliary_classes
    AUXILIARY_CLASSES.each do |ac|
      self.classes.include?(ac) or self.add_class(ac)
    end
  end

  def set_attributes!
    raise ArgumentError, "User is not set" if self.user.blank?
    attributes_from_user.each do |attr, value|
      self.set_attribute(attr, value)
    end
  end

  def full_name
    "#{user['first_name']} #{user['last_name']}".rstrip
  end

  # Return UNIX style GECOS info
  def generate_gecos
    data = []
    data << self.full_name
    data << user["phone"]
    data << user["email"]

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
        'telephoneNumber'             => 'phone',
        'mail'                        => 'email',
        'unicodePwd'                  => Proc.new{self.ad_encoded_password},
        'unixHomeDirectory'           => 'unix_home_directory',
        'loginShell'                  => 'shell',
        'gecos'                       => Proc.new{self.generate_gecos},
        'objectCategory'              => Proc.new{object_category},
        'userAccountControl'          => Proc.new{user_account_control},
    }
  end

  # Return hash of attributes with LDAP naming
  def attributes_from_user
    user_attributes = {}
    ldap_attribute_map.each do |ldap_attr, attr|
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
    password = SecureRandom.base64(GEN_PW_LENGTH)[0...GEN_PW_LENGTH] if self.new_record? && password.to_s.empty?
    return nil if password.to_s.empty?
    return "\"#{password}\"".encode(Encoding.find('UTF-16LE'))
  end

  # Decrypt password
  def decrypted_password
    cpw = user["password_crypt"]
    return nil if cpw.nil?

    self.class.private_key.private_decrypt(Base64.decode64(cpw))
  end

  # Store previous DN base value so it won't get lost when setting CN attribute
  def store_prev_dn_base(b = nil)
    @old_dn_base = b || dn.parent
  end

  def old_dn_base
    @old_dn_base
  end

  # Setting new CN value resets base and prefix, restore it
  def compute_base
    old_dn_base || super
  end

  # Prepend either OU or Default Prefix to the base
  def base_prefix
    HaridSyncHelpers.ensure_uppercase_dn_component(user['ou'] || DEFAULT_PREFIX)
  end

  # Computes new OU base from attributes
  def compute_new_base
    ActiveLdap::DN.parse([base_prefix,self.class.base.to_s].compact.join(','))
  end

  # Ensure that the entity is moved to new OU if needed
  def ensure_ou_change
    new_base = compute_new_base
    if new_base != old_dn_base
      rdn = "#{dn_attribute}=#{self.send(self.dn_attribute)}"
      self.class.connection.modify_rdn(dn, rdn, true, new_base.to_s)
      # Store changes to current model too
      store_prev_dn_base new_base
      return true
    else
      return false
    end
  end

  def sync
    begin
      store_prev_dn_base
      add_auxiliary_classes
      set_attributes!
      save!
      ensure_ou_change
    rescue => e
      $stderr.puts "Error syncing #{self.cn} user to LDAP: #{e}"
      $stderr.puts self.errors.full_messages
      puts "error (See log for more details)"
    end
  end
end
