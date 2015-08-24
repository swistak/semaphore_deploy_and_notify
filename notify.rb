#!/usr/bin/env ruby

require 'bundler/setup'
require 'xmpp4r-simple'

xmpp = Jabber::Simple.new("appstream.build.bot@gmail.com/#{`hostname`}", ENV['BUILDBOT_PASSWORD'])

subscribers = ["some@email.com"]

subscribers.each do |roster_item|
  ARGV.each do |msg|
    puts "#{roster_item.inspect} - #{msg}"
    xmpp.deliver(roster_item, msg)
  end
end

sleep 2
