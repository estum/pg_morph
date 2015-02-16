require 'active_support'
require 'active_record'

require "pg_morph/naming"
require "pg_morph/polymorphic"
require "pg_morph/adapter"
require "pg_morph/engine" if defined? Rails

module PgMorph
  class Exception < RuntimeError;  end
end
