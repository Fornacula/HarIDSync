require 'active_ldap'
class LdapGroup < ActiveLdap::Base
  DEFAULT_PREFIX = 'CN=Users'
  ldap_mapping dn_attribute: 'CN', prefix: '',
               classes: ['top', 'posixGroup'],
               scope: :sub

  AUXILIARY_CLASSES = %w(posixGroup)

  # AD objectCategory values
  GROUP_TYPE_BUILTIN_LOCAL_GROUP = 0x00000001
  GROUP_TYPE_ACCOUNT_GROUP       = 0x00000002
  GROUP_TYPE_RESOURCE_GROUP      = 0x00000004
  GROUP_TYPE_UNIVERSAL_GROUP     = 0x00000008
  GROUP_TYPE_SECURITY_ENABLED    = -0x80000000

  attr_accessor :group

  class << self
    attr_accessor :private_key

    def sync_all_to_ldap(groups, private_key_file)
      puts "Syncing HarID AD/LDAP groups to your LDAP server"
      begin
        key = OpenSSL::PKey::RSA.new File.read(private_key_file)
        self.private_key = key
      rescue => e
        $stderr.puts "Error opening private key file: #{e}"
        exit 1
      end

      groups.each do |group|
        ldap_group = LdapGroup.find_or_create(group['gid_number'], group['name'])
        ldap_group.group = group
        ldap_group.sync
      end
    end

    def remove_from_ldap(groups)
      puts "Removing deleted groups from LDAP"
      groups.each do |group|
        begin
          ldap_group = LdapGroup.find(:first, "gidNumber=#{gid_number}")
          if ldap_group.present?
            ldap_group.destroy
          end
        rescue => e
          $stderr.puts "Error occured while deleting group from LDAP: #{e}"
        end
      end
    end

    def find_or_create(gid_number, name)
      LdapGroup.find(:first, "gidNumber=#{gid_number}") || LdapGroup.new(name)
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
      $stderr.puts "Error syncing group #{gid_number} to LDAP: #{e}"
      $stderr.puts self.errors.full_messages
    end
  end

  def add_auxiliary_classes
    AUXILIARY_CLASSES.each do |ac|
      self.classes.include?(ac) or self.add_class(ac)
    end
  end

  def set_attributes!
    raise ArgumentError, "Group is not set" if self.group.blank?
    attributes_from_group.each do |attr, value|
      next unless has_attribute?(attr)
      self.set_attribute(attr, value)
    end
  end

  # Active Directory objectCategory for groups
  def object_category
    "CN=Group,CN=Schema,CN=Configuration,#{ActiveLdap::Base.base}"
  end

  # Active Directory groupType (domain global + security)
  def group_type
    GROUP_TYPE_SECURITY_ENABLED + GROUP_TYPE_ACCOUNT_GROUP
  end

  # provide map to get ldap attributes from current object
  # Supports both symbols and lambdas (gives self as first attribute)
  def ldap_attribute_map
    {
      'cn' => 'name',
      'sAMAccountName' => 'name',
      'gidNumber' => 'gid_number',
      'description' => 'description',
      'member' => Proc.new{|grp| (grp["member_uids"].map { |uid| 
        unless LdapUser.find("uid=#{uid}").blank?
          HaridsyncHelpers.ensure_uppercase_dn_component(LdapUser.find("uid=#{uid}").dn.to_s)
        end
        }).compact.sort},
      'objectCategory' => Proc.new{self.object_category},
      'groupType' => Proc.new{self.group_type},
    }
  end

  # Return hash of attributes with LDAP naming
  def attributes_from_group
    group_attributes = {}
    self.ldap_attribute_map.each do |ldap_attr, attr|
      group_attributes[ldap_attr] = attr.is_a?(Proc) ? attr.call(self.group) : self.group[attr]
    end
    group_attributes
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
    HaridsyncHelpers.ensure_uppercase_dn_component(group['ou'] || DEFAULT_PREFIX)
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
end
