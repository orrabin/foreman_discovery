class CreateDiscoveryFacetsFactValue < ActiveRecord::Migration
  def change
    create_table :discovery_facets_fact_values do |t|
      t.integer  :fact_value_id
      t.integer :discovery_facet_id

      t.timestamps
    end
  end
end
