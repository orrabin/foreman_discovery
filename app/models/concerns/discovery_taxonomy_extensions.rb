module DiscoveryTaxonomyExtensions
  extend ActiveSupport::Concern
  included do
    has_many :discovery_facets, :class_name => 'Host::Discovered'
    before_destroy ActiveRecord::Base::EnsureNotUsedBy.new(:discovery_facets)
  end
end
