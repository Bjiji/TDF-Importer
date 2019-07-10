require 'nokogiri'
require 'open-uri'
require 'chronic_duration'
require 'unicode'
require_relative 'my_sql_utils'
require_relative 'nationality_utils'

def parse_xml_aso(filename)
  doc = File.open(filename) {|f| Nokogiri::XML(f)}
  doc.encoding = 'utf-8'
  mteams = {}
  doc.xpath('//teams/team').each do |team|
    team_code = team.attr("TeamCode")
    equipe_name_short = team.attr("EquipeNameShort")
    puts "add #{team_code} - #{equipe_name_short}"
    mteams[team_code] = equipe_name_short
  end

  doc.xpath('//riders/rider').each do |rider|

    dossard = rider.attr("Number")
    lastname =  rider.attr("Name")
    firstname = rider.attr("Prenom")
    team_code = rider.attr("TeamCode")
    team_name = mteams[team_code]
    nationality = rider.attr("Nation")
    dob = rider.attr("DateNaissance")


    puts "dossard #{dossard} => #{lastname} #{firstname} (#{nationality}) - Team '#{team_name}' [#{team_code}] @dob: #{dob}"

    MySQLUtils.getOrCreateRaceRunnerASO(2019, dossard, lastname, firstname, nationality, team_code, team_name, dob)
  end
end

class ImportRunners
  parse_xml_aso("../2019/Liste_des_partants_TDF19.xml")
end