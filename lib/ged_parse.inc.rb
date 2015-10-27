#
# based on Michael Farmer on 2007-07-20.
# souce: https://github.com/mikefarmer/ruby-gedcom-parser
# Licence: None
#
#
# Modifications:
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

module GedParse
	class GedDetailList
		attr_reader :list

		def initialize 
			@list= []
		end

		def add_detail(level, tag, val)
			h= {:field => tag, :value => val, :children => []}

			level= level.to_i
			case level
			when 0 then raise "Level cannot be Zero"
			when 1 then @list.push h
			else
				last_detail= @list.last
				(2...level).to_a.each {|a|
					last_detail= last_detail[:children].last
				}

				case tag
				when "CONT"	then last_detail[:value]= last_detail[:value].to_s + "\n" + val.to_s
				when "CONC"	then last_detail[:value]= last_detail[:value].to_s + val.to_s
				else
					h[:field]= last_detail[:field] + '_' + tag.to_s 
					last_detail[:children].push h
				end
			end

			return @list.last
		end
	end

	class GedSection
		attr_reader :details, :gid

		def initialize(gid)
			@gid= gid
			@d_list= GedDetailList.new
			@details= []
			@cached_details= {}
			@type= :general
		end

		def add_detail(level, tag, val)
			@d_list.add_detail level, tag, val
			@details= @d_list.list
			return @details.last
		end

		def get_detail(tag, details= @details, i= 0)
			tg= tag.split('_')
			t= tg[0..i].join('_')

			details.each do |detail|
				if detail[:field] == t
					if (tg.size-1) == i
						return detail
					else
						return get_detail(tag, detail[:children], i+1)
					end
				end
			end

			return nil
		end

		def get_details(tag, details= @details, i= 0, list= [])
			tg= tag.split('_')
			t= tg[0..i].join('_')

			details.each do |detail|
				if detail[:field] == t
					if (tg.size-1) == i
						list << detail
					else
						list= get_details(tag, detail[:children], i+1, list)
					end
				end
			end

			return list
		end

		def get_cached_detail(sym, tag)
			if @cached_details[sym].nil?
				t= get_detail(tag)
				@cached_details[sym]= t.nil? ? "" : t[:value]
			end
			return @cached_details[sym]
		end

		def fields
			f= []
			@details.each do |detail|
				f.push detail[:field]
			end
			return f.uniq
		end

		def is_general?;	return @type == :general;	end
		def is_individual?;	return @type == :individual;	end
		def is_family?;		return @type == :family;	end
		def is_note?;		return @type == :note;		end
		def is_place?;		return @type == :place;		end
	end

	class Individual < GedSection
		attr_reader :name

		def initialize(gid)
			super
			@name= ""
			@type= :individual
		end

		def add_detail(level, tag, val)
			@name= val if tag == 'NAME'
			super
		end

		def idno;		return get_cached_detail(:idno,		"IDNO");	end
		def sex;		return get_cached_detail(:sex,		"SEX");		end
		def birth;		return get_cached_detail(:birth,	"BIRT_DATE");	end
		def birth_place;	return get_cached_detail(:birth_place,	"BIRT_PLAC");	end
		def leaf;		return get_cached_detail(:leaf,		"CHR_DATE");	end
		def leaf_place;		return get_cached_detail(:leaf_place,	"CHR_PLAC");	end
		def died;		return get_cached_detail(:died,		"DEAT_DATE");	end
		def died_place;		return get_cached_detail(:died_place,	"DEAT_PLAC");	end
		def objs;		return get_details("OBJE");	end

		def male?;	return sex == "M";	end
		def female?;	return sex == "F";	end

	end

	class Family < GedSection
		attr_reader :children, :husband, :wife

		def initialize(gid)
			super
			@children= []
			@husband= nil
			@wife= nil
			@type= :family
		end

		def add_relation(type, individual)
			raise "No Individual to add" if ! individual
			@husband= individual if type == 'HUSB'
			@wife= individual if type == 'WIFE'
			@children.push individual if type == 'CHIL'
			return individual
		end

		def married;		return get_cached_detail(:married,		"MARR_DATE");	end
		def married_place;	return get_cached_detail(:married_place,	"MARR_PLAC");	end
		def divorced;		return get_cached_detail(:divorced,		"DIV_DATE");	end
	end

	class Note < GedSection
		attr_reader :text

		def initialize(gid)
			super
			@text= ""
			@type= :note
		end

		def add_detail(level, tag, val)
			case tag
			when "TEXT"	then @text= val.to_s # not in standard - used internally
			when "CONT"	then @text += "\n" + val.to_s
			when "CONC"	then @text += val.to_s
			else
				raise "unknown tag '#{tag.inspect}'"
			end
		end

		def get_detail(tag, details= @details, i= 0);	raise "NOT AVAILABLE FOR NOTES";	end
		def get_details(tag);				raise "NOT AVAILABLE FOR NOTES";	end
		def get_cached_detail(sym, tag);		raise "NOT AVAILABLE FOR NOTES";	end
		def fields;					raise "NOT AVAILABLE FOR NOTES";	end
	end

	class Place < GedSection
		attr_reader :name

		def initialize(gid)
			super
			@name= gid
			@type= :place
		end

		def objs;		return get_details("OBJE");	end
	end

	class Gedcom
		attr_reader :individuals, :families, :tags, :sections, :places, :sources

		def initialize(file_name)
			@file_name= file_name
			refresh
		end

		def refresh 
			@individuals= []
			@families= []
			@notes= []
			@sections= []
			@places= []
			@sources= [] #TODO
			@tags= []

			f= File.new(@file_name, 'r')
			# initial pass, get meta data about the gedcom
			f.each do |gedline|
				level, tag, rest= gedline.chop.split(' ', 3)
				@tags.push tag
				@tags.uniq!
			end
			f.rewind

			# second pass, get individuals
			section_type= ""
			section= nil

			place_section= nil
			place_level= nil
			place_level_higher= false

			f.each do |gedline|

				level, tag, rest= gedline.chop.split(' ', 3)

				if level.to_i == 0
					place_section= nil
					place_level= nil
					place_level_higher= false

					# push the last section
					case section_type
					when ""		then 1
					when "INDI"	then @individuals.push section if section
					when "FAM"	then @families.push section if section
					when "NOTE"	then @notes.push section if section
					else 
						@sections.push section if section
					end

					#start a new section
					case rest.to_s.chomp
					when "INDI"
						#create an individual
						section= Individual.new(tag)
						section_type= 'INDI'
					when "FAM"
						#create a family
						section= Family.new(tag)
						section_type= 'FAM'
					else 
						#create a general section
						if not rest.nil? and rest[0..3] == "NOTE"
							section= Note.new(tag)
							section.add_detail 1, "TEXT", rest[5..-1]
							section_type= "NOTE"
						else
							section= GedSection.new(tag)
							section_type= ""
						end
					end
				else
					#add a detail to the section
					if section_type == 'FAM' && ['HUSB', 'WIFE', 'CHIL'].include?(tag)
						section.add_relation(tag, find_by_individual_gid(rest)) if section
					else
						section.add_detail level, tag, rest if section
					end

					if tag == "PLAC" and find_by_place(rest).nil?
						place_section= Place.new(rest)
						@places.push place_section
						place_level= level
						place_level_higher= false
					end

					if place_section
						if level < place_level
							place_section= nil
							place_level= nil
							place_level_higher= false
						elsif level == place_level
							place_level_higher= false
							if "OBJE".include? tag
								place_level_higher= true
								place_section.add_detail((level.to_i-place_level.to_i+1), tag, rest)
							end
						elsif place_level_higher
							place_section.add_detail((level.to_i-place_level.to_i+1), tag, rest)
						end
					end
				end
			end 

			# add the last section
			case section_type 
			when "INDI"	then @individuals.push section if section
			when "FAM"	then @families.push section if section
			when "NOTE"	then @notes.push section if section
			else 
				@sections.push section if section
			end

			@individuals.compact!
			@families.compact!
			@notes.compact!
			@sections.compact!
			@places.compact!
			@sources.compact!

			f.close

			return true
		end

		def find_by_family_gid(gid)
			@families.each do |f|
				return f if f.gid == gid
			end
			return nil
		end

		def find_by_individual_gid(gid)
			@individuals.each do |i|
				return i if i.gid == gid 
			end
			return nil
		end

		def find_by_node_gid(gid)
			@notes.each do |n|
				return n if n.gid == gid
			end
			return nil
		end

		def find_by_place(name)
			@places.each do |p|
				return p if p.name == name
			end
			return nil
		end

		def getFamilyWithChild(indi)
			@families.each {|f|
				f.children.each {|fc|
					return f if fc == indi
				}
			}
			return nil
		end

		def getFamiliesWithParent(indi)
			f= []
			@families.each {|family|
				f << family if family.husband == indi or family.wife == indi
			}
			return f
		end

	end
end

# TODO redesign for years < 1900
def str2time(str)
	return nil if str.to_s == ""

	yr= nil; mo= nil; dy= nil
	mon_list= [nil, "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

	r= /([0-9a-zA-Z]*).([0-9a-zA-Z]*).([0-9a-zA-Z]*)/.match(str)

	dy= r[1].to_i
	mo= mon_list.index(r[2])
	yr= r[3].to_i

	return Time.local(yr, mo, dy)
end
