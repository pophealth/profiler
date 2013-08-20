# Top level include file that brings in all the necessary code
require 'bundler/setup'
require 'rubygems'

APP_CONFIG = YAML.load_file(File.join('config', 'measures.yml'))

require_relative 'measures/calculator.rb'
require_relative 'measures/loader.rb'
require_relative 'measures/measure.rb'
require_relative 'profiler/value_set_helper.rb'
