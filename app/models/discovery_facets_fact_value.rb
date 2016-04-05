class DiscoveryFacetsFactValue < ActiveRecord::Base
  belongs_to :fact_value, :dependent => :destroy
  belongs_to :discovery_facet
end
