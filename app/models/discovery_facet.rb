class DiscoveryFacet < HostFacets::Base
  include ScopedSearchExtensions
  include Authorizable

  attr_accessible :discovery_rule_id, :name,
                  :subnet, :subnet_id,
                  :location, :location_id,
                  :organization, :organization_id

  has_one :discovery_attribute_set, :foreign_key => :host_id, :dependent => :destroy
  has_many :discovery_facets_fact_values, :dependent => :destroy
  has_many :fact_values, :through => :discovery_facets_fact_values
  has_one :ip_fact, -> { joins(:fact_names).where(fact_names: { name: 'ipaddress' }) }, :class_name => 'FactValue', :through => :discovery_facets_fact_values
  has_one :subnet, :foreign_key => :discovery_id
  belongs_to :location
  belongs_to :organization


  validates :discovery_attribute_set, :presence => true
  delegate :memory, :cpu_count, :disk_count, :disks_size, :to => :discovery_attribute_set

  scoped_search :on => :name, :complete_value => true
  scoped_search :on => :created_at, :default_order => :desc
  scoped_search :on => :last_report, :complete_value => true
  scoped_search :on => :ip_fact, :complete_value => true
  scoped_search :in => :location, :on => :name, :rename => :location, :complete_value => true         if SETTINGS[:locations_enabled]
  scoped_search :in => :organization, :on => :name, :rename => :organization, :complete_value => true if SETTINGS[:organizations_enabled]

  def self.from_facts(facts_hash)
    binding.pry
    validate_facts(facts_hash)
    attributes = generate_attributes(facts_hash)
    facet = where(:name => attributes[:name]).first_or_initialize
    facet.attributes = attributes
    facet.discovery_attribute_set = DiscoveryAttributeSet.from_facts(facet, facts_hash)
    facet.save!

    state = facet.import_facts(facts_hash)
    return facet, state
  end

  def self.generate_attributes(facts_hash)
    primary_ip = suggested_primary_interface_ip(facts_hash)

    if primary_ip
      subnet = Subnet.subnet_for(primary_ip)

      if subnet
        Rails.logger.info "Detected subnet: #{subnet} with taxonomy #{subnet.organizations.collect(&:name)}/#{subnet.locations.collect(&:name)}"
      else
        Rails.logger.warn "Subnet could not be detected for #{primary_ip}"
      end
    else
      raise(::Foreman::Exception.new(N_("Unable to assign subnet, primary interface is missing IP address")))
    end

    # set location and organization
    location = nil
    if SETTINGS[:locations_enabled]
      location = Location.find_by_name(Setting[:discovery_location]) ||
          subnet.try(:locations).try(:first) ||
          Location.first
      Rails.logger.info "Assigning location: #{location}"
    end

    if SETTINGS[:organizations_enabled]
      organization = Organization.find_by_name(Setting[:discovery_organization]) ||
          subnet.try(:organizations).try(:first) ||
          Organization.first
      Rails.logger.info "Assigning organization: #{organization}"
    end

    { :subnet => subnet, :location => location, :organization => organization, :name => generate_name(facts_hash) }
  end

  def self.generate_name(facts)
    prefix_from_settings = Setting[:discovery_prefix]
    hostname_prefix = prefix_from_settings if prefix_from_settings.present? && prefix_from_settings.match(/^[a-zA-Z].*/)

    name_fact = return_first_valid_fact(Setting::Discovered.discovery_hostname_fact_array, facts)
    raise(::Foreman::Exception.new(N_("Invalid facts: hash does not contain a valid value for any of the facts in the discovery_hostname setting: %s"), Setting::Discovered.discovery_hostname_fact_array.join(', '))) unless name_fact && name_fact.present?
    hostname = normalize_string_for_hostname("#{hostname_prefix}#{name_fact}")
    Rails.logger.warn "Hostname does not start with an alphabetical character" unless hostname.downcase.match /^[a-z]/
    hostname
  end

  def import_facts facts
    binding.pry
    # Is discovery possible without puppet: type = facts.delete(:_type) || 'puppet'
    importer = FactImporter.importer_for('puppet').new(self, facts)
    importer.import!
  end

  def self.validate_facts(facts)
    raise(::Foreman::Exception.new(N_("Invalid facts, must be a Hash"))) unless facts.is_a?(Hash)

    # filter facts
    facts.reject!{|k,v| k =~ /kernel|operatingsystem|osfamily|ruby|path|time|swap|free|filesystem/i }
    raise ::Foreman::Exception.new(N_("Expected discovery_fact '%s' is missing, unable to detect primary interface and set hostname") % FacterUtils::bootif_name) unless FacterUtils::bootif_present(facts)
  end

  def self.suggested_primary_interface_ip(facts)
    detected = nil

    bootif_mac = FacterUtils::bootif_mac(facts).try(:downcase)
    interfaces = facts[:interfaces]
    if interfaces.present?
      interfaces.split(',').each do |interface|
        if facts["macaddress_#{interface}"].try(:downcase) == bootif_mac
          detected = facts["ipaddress_#{interface}"]
          Rails.logger.debug "Discovery fact parser detected primary interface: #{detected}"
        end
      end
    end

    # return the detected ip
    detected || raise(::Foreman::Exception.new(N_("Unable to detect primary interface using MAC '%{mac}' specified by discovery_fact '%{fact}'") % {:mac => bootif_mac, :fact => FacterUtils::bootif_name}))
  end

  # no need to store anything in the db if the password is our default
  def root_pass
    read_attribute(:root_pass).blank? ? (hostgroup.try(:root_pass) || Setting[:root_pass]) : read_attribute(:root_pass)
  end

  def self.normalize_string_for_hostname(hostname)
    hostname = hostname.to_s.downcase.gsub(/(^[^a-z0-9]*|[^a-z0-9\-]|[^a-z0-9]*$)/,'')
    raise(::Foreman::Exception.new(N_("Invalid hostname: Could not normalize the hostname"))) unless hostname && hostname.present?
    hostname
  end

  def self.return_first_valid_fact(facts_array, facts)
    return facts[facts_array] if !facts_array.is_a?(Array)
    facts_array.each do |value|
      return facts[value] if !facts[value].nil?
    end
    return nil
  end
end