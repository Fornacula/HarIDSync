require 'active_ldap'
class LdapGroup < ActiveLdap::Base
  ldap_mapping dn_attribute: 'cn', prefix: 'cn=Users',
               classes: ['top', 'group'],
               scope: :one

  AUXILIARY_CLASSES = %w(posixGroup)

  # AD objectCategory values
  GROUP_TYPE_BUILTIN_LOCAL_GROUP = 0x00000001
  GROUP_TYPE_ACCOUNT_GROUP       = 0x00000002
  GROUP_TYPE_RESOURCE_GROUP      = 0x00000004
  GROUP_TYPE_UNIVERSAL_GROUP     = 0x00000008
  GROUP_TYPE_SECURITY_ENABLED    = -0x80000000

  attr_accessor :group

  def add_auxiliary_classes
    AUXILIARY_CLASSES.each do |ac|
      self.classes.include?(ac) or self.add_class(ac)
    end
  end

  def set_attributes!
    raise ArgumentError, "Group is not set" if self.group.blank?
    attributes_from_group.each do |attr, value|
      self.send "#{attr}=", value
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
        'member' => Proc.new{|grp| (grp["member_uids"].map { |uid| LdapUser.find("uid=#{uid}").dn unless LdapUser.find("uid=#{uid}").blank?}).compact},
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

  def self.find_ldap_group(name)
    LdapGroup.find(:first, "sAMAccountName=#{name}") || LdapGroup.new(name)
  end

  def sync
    begin
      self.add_auxiliary_classes
      self.set_attributes!
      self.save!

    rescue => e
      $stderr.puts "Error syncing group to LDAP: #{e}"
      $stderr.puts self.errors.full_messages
      puts "error (See log for more details)"
    end
  end

  def self.sync_all_to_ldap(groups)
    puts "Syncing database groups to LDAP"
    groups.each do |group|
      ldap_group = LdapGroup.find_ldap_group(group["name"])
      ldap_group.group = group
      ldap_group.sync
    end
  end

  def self.remove_from_ldap(groups)
    puts "Removing deleted groups from LDAP"
    groups.each do |group|
      begin
        ldap_group = LdapGroup.find(:first, :filter => "(&(sAMAccountName=#{group['name']})(gidNumber=#{group['gid_number']}))")
        if ldap_group.present?
          ldap_group.destroy
        end
      rescue => e
        $stderr.puts "Error occured while deleting group from LDAP: #{e}"
        puts "error (See log for more details)"
      end
    end
  end
end
