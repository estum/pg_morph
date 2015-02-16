module PgMorph
  class Engine < Rails::Engine
    initializer 'PgMorph.active_record' do
      ActiveSupport.on_load :active_record do
        ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.class_eval do
          include PgMorph::Adapter
        end
      end
    end
  end
end