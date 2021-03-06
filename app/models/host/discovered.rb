require 'foreman_discovery/facts'

class Host::Discovered < ::Host::Base

  belongs_to :location
  belongs_to :organization
  belongs_to :subnet
  belongs_to :hostgroup

  validates :mac, :uniqueness => true, :format => {:with => Net::Validations::MAC_REGEXP}, :presence => true
  validates :ip, :format => {:with => Net::Validations::IP_REGEXP}, :uniqueness => true

  scoped_search :on => :name, :complete_value => true, :default_order => true
  scoped_search :on => :last_report, :complete_value => true
  scoped_search :on => :ip, :complete_value => true
  scoped_search :on => :mac, :complete_value => true
  scoped_search :in => :model, :on => :name, :complete_value => true, :rename => :model
  scoped_search :in => :fact_values, :on => :value, :in_key => :fact_names, :on_key => :name, :rename => :facts, :complete_value => true, :only_explicit => true
  scoped_search :in => :location, :on => :name, :rename => :location, :complete_value => true         if SETTINGS[:locations_enabled]
  scoped_search :in => :organization, :on => :name, :rename => :organization, :complete_value => true if SETTINGS[:organizations_enabled]
  scoped_search :in => :subnet, :on => :network, :complete_value => true, :rename => :subnet

  default_scope lambda {
    org = Organization.current
    loc = Location.current
    conditions = {}
    conditions[:organization_id] = org.subtree_ids if org
    conditions[:location_id]     = loc.subtree_ids if loc
    where(conditions)
  }

  def self.import_host_and_facts facts
    raise(::Foreman::Exception.new(N_("Invalid facts, must be a Hash"))) unless facts.is_a?(Hash)
    fact_name = Setting[:discovery_fact] || 'macaddress'
    hostname = facts[fact_name].try(:downcase).try(:gsub,/:/,'').try(:sub,/^/,'mac')
    raise(::Foreman::Exception.new(N_("Invalid facts: hash does not contain the required fact '%s'"), fact_name)) unless hostname
    raise(::Foreman::Exception.new(N_("Invalid facts: hash does not contain IP address"))) unless facts['ipaddress']

    # filter facts
    facts.reject!{|k,v| k =~ /kernel|operatingsystem|osfamily|ruby|path|time|swap|free|filesystem/i }

    h = ::Host::Discovered.find_by_name hostname
    h ||= Host.new :name => hostname, :type => "Host::Discovered"
    h.type = "Host::Discovered"
    h.mac = facts[fact_name].try(:downcase)

    if SETTINGS[:locations_enabled]
      begin
        h.location = (Location.find_by_name Setting[:discovery_location]) || Location.first
      rescue
        h.location = Location.first
      end
    end
    if SETTINGS[:organizations_enabled]
      begin
        h.organization = (Organization.find_by_name Setting[:discovery_organization]) || Organization.first
      rescue
        h.organization = Organization.first
      end
    end

    h.save(:validate => false) if h.new_record?
    state = h.import_facts(facts)
    return h, state
  end

  def import_facts facts
    # Discovered Hosts won't report in via puppet, so we can use that field to
    # record the last time it sent facts...
    self.last_report = Time.now
    super
  end

  def attributes_to_import_from_facts
    super + [:ip]
  end

  def populate_fields_from_facts facts = self.facts_hash, type = 'puppet'
    # type arg only added in 1.7
    if Gem::Dependency.new('', '>= 1.7').match?('', SETTINGS[:version].notag)
      importer = super
    else
      importer = super(facts)
    end
    self.subnet = Subnet.subnet_for(importer.ip)
    self.save
  end

  # no need to store anything in the db if the password is our default
  def root_pass
    read_attribute(:root_pass).blank? ? (hostgroup.try(:root_pass) || Setting[:root_pass]) : read_attribute(:root_pass)
  end

  def refresh_facts
    # TODO: Can we rely on self.ip? The lease might expire/change....
    begin
      logger.debug "retrieving facts from proxy on ip: #{self.ip}"
      facts = ForemanDiscovery::Facts.new(:url => "http://#{self.ip}:8443").facts
    rescue Exception => e
      raise _("Could not get facts from proxy: %s") % e
    end

    return self.class.import_host_and_facts facts
  end

  def self.model_name
    ActiveModel::Name.new(Host)
  end

  def compute_resource
    false
  end

end
