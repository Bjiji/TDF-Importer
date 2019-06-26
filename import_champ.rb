require 'nokogiri'
require 'open-uri'
require 'chronic_duration'
require 'unicode'
require_relative 'my_sql_utils'
require_relative 'nationality_utils'

def parse_txt_plaf(race_name, race_label, filename)

#  f = File.open(filename, "r")
  File.foreach(filename) do |line|
    if ls = line.split("\t")
      if (ls.length > 1) then
        year = ls[0].strip
        cyclist = ls[1].strip
        if (year.match(/^[0-9]{4}/)) then
          mc = MySQLUtils.getMatchingCyclist(year, cyclist)
          if (mc == nil) then
            names = cyclist.split(" ")
            if (names.length == 2) then
              cid = MySQLUtils.createCyclist(names[-1], names[0], nil, nil, nil)
            else
              cid = MySQLUtils.createCyclist(cyclist,"", nil, nil, nil)
            end
            puts("!! #{year} create: #{cyclist} #{mc}")
          else
            cid = mc['id']
            puts("#{year} OK: #{cyclist} #{mc}")
          end

          MySQLUtils.addOtherRaceResultToCyclist(cid, year, race_name, race_label)

        end
      end
    end
  end
end

class ImportRunners
  #parse_txt_plaf("champ_france", "championnat du monde", "./Championnat_de_France_Tour_.txt")
  parse_txt_plaf("champ_world", "championnat du monde", "./Championnat_du_monde_Tour_.txt")

end