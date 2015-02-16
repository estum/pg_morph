module PgMorph
  class Polymorphic
    include PgMorph::Naming
    
    QUERY_PATTERN = /(( +(ELS)?IF.+\n?)(\s+INSERT INTO.+;\n?))/
    
    attr_reader :parent_table, :child_table, :column_name

    def initialize(parent_table, child_table, options)
      @parent_table = parent_table
      @child_table = child_table
      @column_name = options[:column]

      raise PgMorph::Exception.new("Column not specified") unless @column_name
    end

    def create_proxy_table_sql
      <<-SQL.strip_heredoc  
        CREATE TABLE #{proxy_table} (
          CHECK (#{column_name_type} = '#{type}'),
          PRIMARY KEY (id),
          FOREIGN KEY (#{column_name_id}) REFERENCES #{child_table}(id)
        ) INHERITS (#{parent_table});
      SQL
    end

    def create_before_insert_trigger_fun_sql
      before_insert_trigger_content do
        create_trigger_body.strip
      end
    end

    def create_before_insert_trigger_sql
      fun_name = before_insert_fun_name
      trigger_name = before_insert_trigger_name

      create_trigger_sql(parent_table, trigger_name, fun_name, 'BEFORE INSERT')
    end

    def create_after_insert_trigger_sql
      fun_name = after_insert_fun_name
      trigger_name = after_insert_trigger_name

      create_trigger_sql(parent_table, trigger_name, fun_name, 'AFTER INSERT')
    end

    def create_after_insert_trigger_fun_sql
      fun_name = after_insert_fun_name
      create_trigger_fun(fun_name) do
        <<-SQL.strip_heredoc
          DELETE FROM ONLY #{parent_table} WHERE id = NEW.id;
        SQL
      end
    end

    def remove_before_insert_trigger_sql
      trigger_name = before_insert_trigger_name
      fun_name = before_insert_fun_name

      prosrc = get_function(fun_name)
      raise PG::Error.new("There is no such function #{fun_name}()\n") unless prosrc

      scan =  prosrc.scan(QUERY_PATTERN)
      cleared = scan.reject { |x| x[0].match("#{proxy_table}") }

      if cleared.present?
        cleared[0][0].sub!('ELSIF', 'IF')
        before_insert_trigger_content do
          cleared.map { |m| m[0] }.join('').strip
        end
      else
        drop_trigger_and_fun_sql(trigger_name, parent_table, fun_name)
      end
    end

    def remove_partition_table
      table_empty = ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{parent_table}_#{child_table}").to_i.zero?
      if table_empty
        <<-SQL.strip_heredoc
          DROP TABLE IF EXISTS #{proxy_table};
        SQL
      else
        raise PG::Error.new("Partition table #{proxy_table} contains data.\nRemove them before if you want to drop that table.\n")
      end
    end

    def remove_after_insert_trigger_sql
      prosrc = get_function(before_insert_fun_name)
      scan =  prosrc.scan(QUERY_PATTERN)
      cleared = scan.reject { |x| x[0].match("#{proxy_table}") }

      return '' if cleared.present?
      fun_name = after_insert_fun_name
      trigger_name = after_insert_trigger_name

      drop_trigger_and_fun_sql(trigger_name, parent_table, fun_name)
    end

    private
    def create_trigger_fun(fun_name, &block)
      <<-SQL.strip_heredoc
        CREATE OR REPLACE FUNCTION #{fun_name}() RETURNS TRIGGER AS $$
        BEGIN
          #{block.call}
          RETURN NEW;
        END; $$ LANGUAGE plpgsql;
      SQL
    end

    def before_insert_trigger_content( &block)
      create_trigger_fun(before_insert_fun_name) do
        <<-SQL.strip_heredoc
          #{block.call}
          ELSE
            RAISE EXCEPTION 'Wrong "#{column_name}_type"="%" used. Create proper partition table and update #{before_insert_fun_name} function', NEW.#{column_name}_type;
          END IF;
        SQL
      end
    end

    def create_trigger_body
      prosrc = get_function(before_insert_fun_name)

      if prosrc
        scan =  prosrc.scan(QUERY_PATTERN)
        raise PG::Error.new("Condition for #{proxy_table} table already exists in trigger function") if scan[0][0].match proxy_table
        <<-SQL.strip_heredoc
          #{scan.map { |m| m[0] }.join.strip}
          ELSIF (NEW.#{column_name}_type = '#{child_table.to_s.singularize.camelize}') THEN
          INSERT INTO #{parent_table}_#{child_table} VALUES (NEW.*);
        SQL
      else
        <<-SQL.strip_heredoc 
          IF (NEW.#{column_name}_type = '#{child_table.to_s.singularize.camelize}') THEN
          INSERT INTO #{parent_table}_#{child_table} VALUES (NEW.*);
        SQL
      end
    end

    def create_trigger_sql(parent_table, trigger_name, fun_name, when_to_call)
      <<-SQL.strip_heredoc
        DROP TRIGGER IF EXISTS #{trigger_name} ON #{parent_table};
        CREATE TRIGGER #{trigger_name}
          #{when_to_call} ON #{parent_table}
          FOR EACH ROW EXECUTE PROCEDURE #{fun_name}();
      SQL
    end

    def drop_trigger_and_fun_sql(trigger_name, parent_table, fun_name)
      <<-SQL.strip_heredoc
        DROP TRIGGER #{trigger_name} ON #{parent_table};
        DROP FUNCTION #{fun_name}();
      SQL
    end

    def get_function(fun_name)
      run("SELECT prosrc FROM pg_proc WHERE proname = '#{fun_name}'")
    end

    def run(query)
      ActiveRecord::Base.connection.select_value(query)
    end
  end
end