module CandiboxHelpers
  def self.ensure_uppercase_dn_component(dn)
    # Turns dc=example into DC=example
    dn.scan(/(([^=]+)=([^,]+)),?/).map{|m| "#{m[1].upcase}=#{m[2]}"}.join(",")
  end
end