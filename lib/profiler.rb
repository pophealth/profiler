# Top level include file that brings in all the necessary code
require 'bundler/setup'
require 'rubygems'
require 'yaml'

APP_CONFIG = YAML.load_file(File.join('config', 'measures.yml'))

require_relative 'measures/calculator.rb'
require_relative 'measures/loader.rb'
require_relative 'measures/measure.rb'
require_relative 'measures/oid_helper.rb'
require_relative 'profiler/value_set_helper.rb'
require_relative '../config/initializers/mongo.rb'
require_relative '../config/application.rb'
