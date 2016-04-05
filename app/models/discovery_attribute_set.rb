class DiscoveryAttributeSet < ActiveRecord::Base
  belongs_to :discovery_facet, :foreign_key => :host_id
  attr_accessible :cpu_count, :disk_count, :disks_size, :memory

  validates :cpu_count, :presence => true, :numericality => {:greater_than_or_equal_to => 0}
  validates :memory, :presence => true,    :numericality => {:greater_than_or_equal_to => 0}
  validates :discovery_facet, :presence => true

  def self.from_facts(discovery_facet, facts)
    discovery_attribute_set = where(:host_id => discovery_facet.id).first_or_initialize
    discovery_attribute_set.attributes = generate_attributes(facts)
    discovery_attribute_set
  end

  def self.generate_attributes(facts)
    cpu_count  = facts['physicalprocessorcount'].to_i rescue 0
    memory     = facts['memorysize_mb'].to_f.ceil rescue 0
    disks      = facts.select { |key, value| key.to_s =~ /blockdevice.*_size/ }
    disks_size = 0
    disk_count = 0

    if disks.any?
      disks.values.each { |size| disks_size += (size.to_f rescue 0) }
      disk_count = disks.size
      # Turning disks_size to closest Mega for easier to read UI
      disks_size = (disks_size / 1024 / 1024).ceil if disks_size > 0
    end

    {:cpu_count => cpu_count, :memory => memory, :disk_count => disk_count, :disks_size => disks_size}
  end
end
