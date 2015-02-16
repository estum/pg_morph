require 'spec_helper'

describe PgMorph::Polymorphic do
  before do
    @polymorphic = PgMorph::Polymorphic.new(:foos, :bars, column: :baz)
  end

  subject { @polymorphic }
  it { expect(@polymorphic.column_name).to eq :baz }
  it { expect(@polymorphic.parent_table).to eq :foos }
  it { expect(@polymorphic.child_table).to eq :bars }

  describe '#create_proxy_table_sql' do
    it 'generates proper sql' do
      expect(@polymorphic.create_proxy_table_sql.squish)
        .to eq <<-SQL.squish
          CREATE TABLE foos_bars (
            CHECK (baz_type = 'Bar'),
            PRIMARY KEY (id), FOREIGN KEY (baz_id) REFERENCES bars(id)
          ) INHERITS (foos);
        SQL
    end
  end

  describe '#create_before_insert_trigger_fun_sql' do
    it 'generates proper sql' do
      expect(@polymorphic).to receive(:before_insert_trigger_content)
      @polymorphic.create_before_insert_trigger_fun_sql
    end
  end

  describe '#create_trigger_body' do
    it 'returns proper sql for new trigger' do
      expect(@polymorphic.send(:create_trigger_body).squish)
        .to eq "IF (NEW.baz_type = 'Bar') THEN INSERT INTO foos_bars VALUES (NEW.*);"
    end
  end

  describe '#before_insert_trigger_content' do
    it 'generate proper sql' do
      expect(@polymorphic.send(:before_insert_trigger_content){'my block'}.squish)
        .to eq <<-SQL.squish
          CREATE OR REPLACE FUNCTION foos_baz_fun() RETURNS TRIGGER AS $$
            BEGIN
              my block
              ELSE
                RAISE EXCEPTION 'Wrong "baz_type"="%" used. Create proper partition table and update foos_baz_fun function', NEW.baz_type;
              END IF;
            RETURN NEW;
            END; $$ LANGUAGE plpgsql;
        SQL
    end
  end

  describe '#create_after_insert_trigger_fun_sql' do
    it do
      expect(@polymorphic.create_after_insert_trigger_fun_sql.squish)
        .to eq <<-SQL.squish
          CREATE OR REPLACE FUNCTION delete_from_foos_master_fun() RETURNS TRIGGER AS $$
          BEGIN
            DELETE FROM ONLY foos WHERE id = NEW.id;
            RETURN NEW;
          END; $$ LANGUAGE plpgsql;
        SQL
    end
  end

  describe '#create_after_insert_trigger_sql' do
    it do
      expect(@polymorphic.create_after_insert_trigger_sql.squish)
        .to eq <<-SQL.squish
          DROP TRIGGER IF EXISTS foos_after_insert_trigger ON foos;
          CREATE TRIGGER foos_after_insert_trigger
            AFTER INSERT ON foos
            FOR EACH ROW EXECUTE PROCEDURE delete_from_foos_master_fun();
        SQL
    end
  end

  describe '#remove_before_insert_trigger_sql' do
    it 'raise error if no function' do
      expect { @polymorphic.remove_before_insert_trigger_sql }
        .to raise_error PG::Error
    end

    it 'returns proper sql for single child table' do
      allow(@polymorphic).to receive(:get_function)
        .with('foos_baz_fun')
        .and_return ''
      expect(@polymorphic.remove_before_insert_trigger_sql.squish)
        .to eq <<-SQL.squish
          DROP TRIGGER foos_baz_insert_trigger ON foos;
          DROP FUNCTION foos_baz_fun();
        SQL
    end
  end
end
	