#!/usr/bin/env ruby
#
# Copyright (c) 2011, 2015 Matthias Rabe (mrabe@hatdev.de)
#
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#

$LOAD_PATH << File.expand_path(File.dirname(__FILE__))
require "lib/ged_parse.inc.rb"

$params= Hash.new

def usage(e= "")
	$stderr.puts "usage: #{$0} reporttype gedcom-fname output-fname"
	$stderr.puts "#{e}" if e != ""
	exit(e == "" ? 0 : 1)
end

def parse_arguments()
	args= [:reporttype, :ifname, :ofname]
	usage("missing parameters") if ARGV.length < args.length
	args.each {|v| $params[v]= ARGV.shift }

	begin
		require "reports/#{$params[:reporttype]}.inc.rb"
	rescue LoadError
		usage("report '#{$params[:reporttype]}' is unknown/ could not be found'")
	end
end

#main
parse_arguments()
report_parse_arguments()

## PARSE
gedcom_parsed = GedParse::Gedcom.new($params[:ifname])
raise "error while parsing gedcom" if gedcom_parsed.nil?

## GEN REPORT
if not report_main(gedcom_parsed)
	$stderr.print "report_main(#{$params[:reporttype]}) failed\n"
	exit(-1)
end

exit(0) # success
