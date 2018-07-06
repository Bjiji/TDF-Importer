require 'nokogiri'
require 'open-uri'
require 'chronic_duration'
require 'unicode'
require_relative 'my_sql_utils'
require_relative 'nationality_utils'

def parse_xml_aso(filename)
  doc = File.open(filename) {|f| Nokogiri::XML(f)}
  doc.encoding = 'utf-8'

  doc.xpath('//riders/rider').each do |rider|

    dossard = rider.attr("Number")
    lastname =  rider.attr("Name")
    firstname = rider.attr("Prenom")
    team_code = rider.attr("TeamCode")
    nationality = rider.attr("Nation")
    dob = rider.attr("DateNaissance")

    puts "dossard #{dossard} => #{lastname} #{firstname} (#{nationality}) - #{team_code} @dob: #{dob}"

    MySQLUtils.getOrCreateRaceRunnerASO(2018, dossard, lastname, firstname, nationality, team_code, dob)
  end
end

class ImportRunners

  parse_xml_aso("e:/Perso/TdF/PARTANTS_TDF-2018.xml")

end