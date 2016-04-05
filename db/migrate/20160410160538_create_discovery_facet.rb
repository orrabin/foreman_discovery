class CreateDiscoveryFacet < ActiveRecord::Migration
  def change
    create_table :discovery_facets do |t|
      t.string  :name
      t.integer :host_id
      t.integer :subnet_id
      t.integer :organization_id
      t.integer :location_id
      t.datetime :last_report

      t.timestamps
    end
  end
end
