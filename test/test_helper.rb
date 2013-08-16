require_relative "./simplecov"
require 'test/unit'
require 'turn'

if RUBY_PLATFORM=='java'
  require 'rhino'
else
  require 'v8'
end

PROJECT_ROOT = File.expand_path("../../", __FILE__)
require File.join(PROJECT_ROOT, 'lib', 'profiler')

def get_js_context(javascript)
  if RUBY_PLATFORM=='java'
    @context = Rhino::Context.new
  else
    @context = V8::Context.new
  end
  @context.eval(javascript)
  @context
end

def initialize_javascript_context(hqmf_utils, codes_json, converted_hqmf)

  if RUBY_PLATFORM=='java'
    @context = Rhino::Context.new
  else
    @context = V8::Context.new
  end
end
