require 'bundler/setup'
require './control'

use Rack::ContentLength
run Control.new
