namespace :db do
  desc "Load Solid* schemas for tables that don't exist yet"
  task solid_schemas: :environment do
    schemas = {
      "solid_queue_jobs"      => "db/queue_schema.rb",
      "solid_cache_entries"   => "db/cache_schema.rb",
      "solid_cable_messages"  => "db/cable_schema.rb"
    }

    schemas.each do |table, schema_file|
      next if ActiveRecord::Base.connection.table_exists?(table)

      puts "Loading #{schema_file}..."
      load Rails.root.join(schema_file)
    end
  end
end
