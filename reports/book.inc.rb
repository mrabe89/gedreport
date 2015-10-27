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

raise "sorry, this file could not be executed directly" if File.basename(__FILE__) == File.basename(ENV["_"])
raise "$params is missing" if $params.nil?
require "lib/report.inc.rb"
require "lib/latex.inc.rb"

# CONST

DEFAULT_MUGSHOT= "#{File.dirname(__FILE__)}/book_pic_missing.png"
PICTURES_PER_LINE= 1

# FUNCTIONS

def report_usage(e= "")
	$stderr.print "usage: #{$0} #{$params[:reporttype]} #{$params[:ifname]} #{$params[:ofname]}\n"
	$stderr.print "#{e}\n" if e != ""
	exit(e == "" ? 0 : 1)
end

def report_parse_arguments()
end

def report_main(ged)
	$params[:ofile]= Latex.open($params[:ofname], "w")

	raise "error while generating title" if not report_title
	raise "error while generating index" if not report_index

	def t1(a);	return (a.idno.to_s == "" ? (1000000+(a.gid[2..-1].to_i)) : a.idno.to_i);	end
	indis= ged.individuals.sort {|a, b| t1(a) <=> t1(b) }
	raise "error while generating seperator" if not report_separator("Personen") if indis.size > 0
	indis.each_with_index {|indi, i|
		if not report_person(ged, indi)
			$stderr.print "error while generating pages for #{indi.name}(#{indi.gid})" 
			return(false)
		end
	}

	places= ged.places.delete_if {|x| x.objs.size == 0}
	places= places.sort {|a, b| a.name <=> b.name }
	raise "error while generating seperator" if not report_separator("Orte") if places.size > 0
	places.each_with_index {|place, i|
		if not report_place(ged, place)
			$stderr.print "error while generating pages for #{place.name}"
			return(false)
		end
	}

	$params[:ofile].close

	return(true)
end

def report_title
	return($params[:ofile].insertTitle({:main => "Ahnenbuch", :foot => Time.now.strftime("Erstellt am %d.%m.%Y")}))
end

def report_index
	return($params[:ofile].insertIndex)
end

def report_separator(text)
	return($params[:ofile].insertSeperator(text))
end

def report_person(ged, indi)
	$params[:ofile].insertChapter(indi.name, indi.gid)

	own_fams= ged.getFamiliesWithParent(indi)

	if not report_person_print_profile(ged, indi, own_fams)
		$stderr.print "error while printing profile for #{indi.name}(#{indi.gid})\n"
		return(false)
	end
	
	if not report_person_print_tree(ged, indi, own_fams)
		$stderr.print "error while printing family tree for #{indi.name}(#{indi.gid})\n"
		return(false)
	end

	if not report_person_print_notes(ged, indi)
		$stderr.print "error while printing notes for #{indi.name}(#{indi.gid})\n"
		return(false)
	end

	if not report_print_galerie(ged, indi)
		$stderr.print "error while printing image galerie for #{indi.name}(#{indi.gid})\n"
		return(false)
	end

	return(true)
end

def report_place(ged, place)
	$params[:ofile].insertChapter(place.name)

	if not report_print_galerie(ged, place)
		$stderr.print "error while printing image galerie for #{place.name}\n"
		return(false)
	end

	return(true)
end

def report_person_print_profile(ged, indi, own_fams)
	$params[:ofile].insertSubSubSection("Steckbrief")
	$params[:ofile].print "\\ThinHRule \\vspace{0mm}\n"

	$params[:ofile].print "\\begin{figure}[htbp]\n"

	mugshot= DEFAULT_MUGSHOT
	indi.objs.each {|o|
		img= nil; ok= false
		o[:children].each {|oc|
			case oc[:field]
			when "OBJE_FORM"	then ok= IMG_FMTS.include? oc[:value].downcase
			when "OBJE_FILE"	then img= oc[:value]
			end
		}
		(mugshot= img; break) if ok
	}

	$params[:ofile].print "\\begin{minipage}[t]{45mm} \n"
	$params[:ofile].print "\\vspace{0mm} \\centering \\incImage{width=10em}{#{conv_img4latex(mugshot)}}\n"
	$params[:ofile].print "\\end{minipage} \\hfill\n"

	def t1(a, b, c, d= nil, e= nil, f= nil, g= nil)
		s= []
		s += ["\\mbox{", b, h(c), "}"] if c.to_s != ""
		s += ["\\mbox{", d, h(e), "}"] if e.to_s != ""
		s += ["\\mbox{", f, h(g), "}"] if g.to_s != ""
		return(s.size > 0 ? "\\mbox{#{a}}: & #{s.join(' ')} \\\\\n" : "")
	end

	$params[:ofile].print "\\begin{minipage}[t]{\\textwidth-10em} \\vspace{0mm}\n"
	$params[:ofile].print "\\begin{tabular}{p{4em} p{\\textwidth-15em}}\n"
	$params[:ofile].print t1("Geboren", "am", indi.birth, "in", indi.birth_place)
	$params[:ofile].print t1("Getauft", "am", indi.leaf, "in", indi.leaf_place)
	$params[:ofile].print t1("Gestorben", "am", indi.died, "in", indi.died_place)
	# TODO EVENT, GRAD, RELI, EVEN, GRAD, EDUC, RESI, CHAN(?), BLES ## USE FOR NOTES, too

	own_fams.each {|own_fam|
		$params[:ofile].print "\\\\"

		partner= nvl((own_fam.husband == indi ? own_fam.wife : own_fam.husband), GedParse::Individual.new(0))
		t= t1("Heirat", "am", own_fam.married, "in", own_fam.married_place)
		$params[:ofile].print t
		$params[:ofile].print t1(((t == "" ? "Heirat " : "") + "mit"), "", partner.name, "\\textborn ~", partner.birth, \
				"\\textdied ~", partner.died) if not partner.nil?
		own_fam.children.each_with_index {|child, i|
			$params[:ofile].print t1((i == 0 ? "1. Kind" : "#{i+1}."), "", child.name, "\\textborn ~", child.birth, \
					"\\textdied ~", child.died)
		}
		$params[:ofile].print t1("Scheidung", "am", own_fam.divorced, "mit", partner) if own_fam.divorced.to_s != ""
	}

	$params[:ofile].print "\\end{tabular}\n"
	$params[:ofile].print "\\end{minipage}\n"

	$params[:ofile].print "\\end{figure}\n"

	return(true)
end

def report_person_print_tree(ged, indi, own_fams)
	$params[:ofile].insertSubSubSection(own_fams.size > 1 ? "Stammbäume" : "Stammbaum")
	$params[:ofile].print "\\ThinHRule \\vspace{2mm}\n"

	indi_ancs= nil
	part_ancs= []

	if own_fams.size > 0
		indi_ancs= ged.getFamilyWithChild(indi)
		own_fams.each {|fam| part_ancs << ged.getFamilyWithChild(indi.male? ? fam.wife : fam.husband) }
	else
		own_fams= [nil]
		indi_ancs= ged.getFamilyWithChild(indi)
		if indi_ancs.nil?
			$params[:ofile].print "Keine Familienbeziehung vorhanden.\\\\\n"
			return(true)
		end
	end

	def t1(a)
		s= "\\parbox{11em}{"
			s += "\\centering #{h(a.name)} \\tiny \\mbox{(S. \\pageref{#{a.gid}})} \\\\ "
			s += "\\mbox{ \\textborn ~ #{h(a.birth)} } " if a.birth.to_s != ""
			s += "\\mbox{ \\textleaf ~ #{h(a.leaf)} } " if a.leaf.to_s != ""
			s += "\\mbox{ \\textdied ~ #{h(a.died)} } " if a.died.to_s != ""
		s += "}"
		return(s)
	end

	def t2(f)
		s= "\\parbox{4em}{\\centering \\tiny "
		s += "\\mbox{\\textmarried ~ #{h(f.married)}} " if f.married.to_s != ""
		s += "\\\\ " if f.married.to_s != "" and f.divorced.to_s != ""
		s += "\\mbox{\\textdivorced ~ #{h(f.divorced)}} " if f.divorced.to_s != ""
		s += "}"
		return(s)
	end

	own_fams.each_with_index {|fam, i|
		matrix= []; 7.times {matrix << []}
		path= [] 
		line= []

		if not indi_ancs.nil?
			if not (a= indi_ancs.husband).nil?
				matrix[0][0]= "\\node [block] (G1) {#{t1(a)}};"
				path << "(G1) -- (G12) -- (I)"
			end
			if not (a= indi_ancs.wife).nil?
				matrix[2][0]= "\\node [block] (G2) {#{t1(a)}};"
				path << "(G2) -- (G12) -- (I)"
			end
			matrix[1][0]= "\\node [cloud] (G12) {#{t2(indi_ancs)}};" \
					if [matrix[0][0].nil?, matrix[2][0].nil?].include? false
		end

		if not part_ancs[i].nil?
			if not (a= part_ancs[i].husband).nil?
				matrix[4][0]= "\\node [block] (G3) {#{t1(a)}};"
				path << "(G3) -- (G34) -- (P)"
			end
			if not (a= part_ancs[i].wife).nil?
				matrix[6][0]= "\\node [block] (G4) {#{t1(a)}};"
				path << "(G4) -- (G34) -- (P)"
			end
			matrix[5][0]= "\\node [cloud] (G34) {#{t2(part_ancs[i])}};" \
					if [matrix[4][0].nil?, matrix[6][0].nil?].include? false
		end

		matrix[1][1]= "\\node [block] (I) {#{t1(indi)}};"
		if not own_fams[i].nil?
			line << "(I) -- (Q)"

			if not (a= (indi.male? ? fam.wife : fam.husband)).nil?
				matrix[5][1]= "\\node [block] (P) {#{t1(a)}};"
				line << "(P) -- (Q)"
			end
			matrix[3][1]= "\\node [cloud] (Q) {#{t2(own_fams[i])}};" \
					if [matrix[1][1].nil?, matrix[5][1].nil?].include? false

			pos_lst= {0 => "", 1 => "3", 2 => "24", 3 => "135", 4 => "0246", 5 => "01356", 6 => "012456",7=>"0123456"}
			c_childs= own_fams[i].children.size
			(c_childs-7).times {matrix << []}
			lst= c_childs > 7 ? (0..own_fams[i].children.size-1) : (pos_lst[own_fams[i].children.size].split(""))
			lst.each_with_index {|pos, j|
				matrix[pos.to_i][3]= "\\node [block] (C#{j+1}) {#{t1(own_fams[i].children[j])}};"
				path << "(Q) -- +(2.5,0) -- (C#{j+1}.west)"
			}
		end

		$params[:ofile].print """\\begin{tikzpicture}
[auto,
block/.style ={rectangle, draw=blue, thick, fill=blue!20, text width=14em, text centered, rounded corners, minimum height=3em},
cloud/.style ={draw=red, thick, ellipse, fill=red!20, text width=6em, text centered, minimum height=3em},
line/.style ={draw, thick, -latex',shorten >=0pt},
lineconnect/.style ={draw, thick,shorten >=0pt}]
\\matrix [column sep=3mm,row sep=2mm]
{
"""
		matrix.each {|m|
			$params[:ofile].puts m.join(" & ") + "\\\\"
		}
		$params[:ofile].print """};
\\begin{scope}[every path/.style=line, rounded corners]
"""
		path.each {|p|
			$params[:ofile].puts "\\path #{p} ;"
		}
		$params[:ofile].print """\\end{scope}
\\begin{scope}[every path/.style=lineconnect, rounded corners]
"""
		line.each {|l|
			$params[:ofile].puts "\\path #{l} ;"
		}
		$params[:ofile].print """\\end{scope}
\\end{tikzpicture} \\\\
"""
	}

	return(true)
end

def report_person_print_notes(ged, indi)
	items= []
	[["Geburtsnotiz", "BIRT_NOTE"], ["Taufnotiz", "CHR_NOTE"], ["Sterbenotiz", "DEAT_NOTE"],
			["Andere", "NOTE"]].each {|x| key, val= x
		indi.get_details(val).each {|note_id| text= note_id= note_id[:value]
			if note_id[0].chr == '@'
				note= ged.find_by_node_gid(note_id)
				if note.nil?
					$stderr.print "could not find note with id '#{note_id.inspect}' for " + \
							"#{indi.name}(#{indi.gid})\n"
					return(false)
				end
				text= note.text
				text= text.gsub("**********", "********** ") # hack to avaid LaTeX warning
			end
			items << "\\item[#{key}] #{replace_newline(h(text))}"
		}
	}

	if items.size > 0
		$params[:ofile].insertSubSubSection("Notizen")
		$params[:ofile].print "\\ThinHRule \\vspace{2mm}\n"

		$params[:ofile].print "\\begin{description}\n"
		$params[:ofile].print items.join("\n")+"\n"
		$params[:ofile].print "\\end{description}\n"
	end

	return(true)
end

def report_print_galerie(ged, section)
	items= {};
	section.objs.each {|o|
		img= nil; titl= nil; note= nil; ok= false
		o[:children].each {|oc|
			case oc[:field]
			when "OBJE_FORM"	then ok= IMG_FMTS.include? oc[:value].downcase
			when "OBJE_FILE"	then img= oc[:value]
			when "OBJE_TITL"	then titl= oc[:value]
			when "OBJE_NOTE"	then note= oc[:value]
			end
		}
		items[img]= nvl(note, titl) if ok
	}
	items= items.to_a

	if items.size > 0
		$params[:ofile].insertSubSubSection("Galerie")
		$params[:ofile].print "\\ThinHRule \\vspace{2mm}\n"

		width= sprintf("%.2f\\textwidth", (1 / (PICTURES_PER_LINE.to_f*1.1)))
		width_tbl= []; PICTURES_PER_LINE.times {width_tbl << "p{#{width}+1pt}"}; width_tbl= width_tbl.join(" ")

		(1..(items.size / PICTURES_PER_LINE.to_f).ceil).to_a.each {|i| i= (i-1) * PICTURES_PER_LINE
			$params[:ofile].print "\\begin{tabular}{#{width_tbl}}\n"
			p= []
			l= []
			(0..(PICTURES_PER_LINE-1)).to_a.each {|j| next if items[i+j].nil?
				note= items[i+j][1]
				if note[0].chr == '@'
					note= ged.find_by_node_gid(note)
					if note.nil?
						$stderr.print "could not find note with id '#{items[i+j][1].inspect}'\n"
						return(false)
					end
					note= note.text
				end

				p << "\\incImageC{width=#{width},height=\\textheight,keepaspectratio=true}{#{conv_img4latex(items[i+j][0])}}"
				l << "\\centering \\small #{h(note)}"
			}

			$params[:ofile].print "#{p.join(" & ")} \\\\\n #{l.join(" & ")} \\\\\n"
			$params[:ofile].print "\\end{tabular}\n\n"
		}
	end

	return(true)
end
