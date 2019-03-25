require 'nokogiri'
require 'open-uri'
require 'chronic_duration'
require 'unicode'
require_relative 'my_sql_utils'
require_relative 'nationality_utils'

class ImportUtils

  PatternCol = /km\s+([\d\.]+)\s+-\s+([-\/'A-zÀ-ÿ\s]+)(?:,\s*([0-9]+)\sm)?\s+\(([\w\.]+)\)/
  CommentPattern = /<!--[\s\S\n]*?-->/
  PatternSingle = /^([-'A-zÀ-ÿ0-9\s]+)\W+\((\w{3})\)$/
  PatternWinner = /^1(?:\.)?\W+([-'A-zÀ-ÿ0-9\s]+)\W+\((\w{3})\)/
  # strict PatternTime = /(\d+)(?:\.)?\W+([-'A-zÀ-ÿ\s]+)\s+\((\w{3})\)\W+en\W+(?:(\d+)h)?(?:(\d+)')?(\d+)/ # match: "1. Marcel Kittel (All) en 4h56'52" (moy : 43.050 km/h)" avec nat, heure et minute optionnelle
  PatternTime = /^(\d+)(?:\.)?\W*([-'A-zÀ-ÿ0-9\s]+)(?:\s+\((\w{3})\))?\W+en\W+(?:(\d+)h)?(?:(\d+)')?(\d+)/
  PatternDelay = /^(\d+)(?:\.)?\W*([-'A-zÀ-ÿ0-9\s]+)(?:\s+\((\w{3})\))?\W+à\W+(?:(\d+)h)?(?:(\d+)')?(\d+)/ # match: "30. Andreas Klöden (All) à 1h02'43" avec heure et minute optionnelle
  # strict PatternSameTime1 = /(\d+)(?:\.)?\W+([-'A-zÀ-ÿ\s]+)\W+\((\w{3})\)(?:\W+m\.t\.)?/ # match 22. Andrew Talansky (Usa) m.t.
  PatternSameTime1 = /^(\d+)(?:\.)?\W*([\-'A-zÀ-ÿ0-9\s]+)(?:\W+\((\w{3})\))?(?:\W+m\.t\.)?/

  # deprecated use generic PatternTime instead
  # #PatterTeamTTT = /^(\d+)(?:\.)?\W+([\-'A-zÀ-ÿ\s]+)\s+en\W+(?:(\d+)h)?(?:(\d+)')?(\d+)/ # 1. BMC RACING TEAM en 32'15"
  #StageDescRegex = /(?:([A-zÀ-ÿ-'\s\/\(\)]*)-)?(.*),\D+([\d\.]+)\s+km(?:\sCLM)?\s+[^\(\w]*(?:\()?(.*)(?:\))?/
  StageDescRegex = /(?:([A-zÀ-ÿ\-'\s\/\(\)]*)-)?(.*),\D+([\d\.]+)\s+km\s+[^\(]*(?:\()?(.*)(?:\))/
  ExtraInfosPattern = /^\*\s+(.*)/

  MountainCategoryMapping = {
      "Cat.1" => "1",
      "Cat.2" => "2",
      "Cat.3" => "3",
      "Cat.4" => "4",
      "H.C" => "HC",
      "Cat.HC" => "HC",
      "Cat.H.C" => "HC"
  }

  NBSP_CHAR = 160.chr(Encoding::UTF_8)

  def self.get_url_resource(url)
    uri = URI(url)
    path = uri.path
    filename = 'cache' + path
    if File.exist?(filename) then
      puts 'using cache for resource'
      html = File.open(filename, 'r:iso-8859-1').read
    else
      begin
        print 'downloading resource... '
        html = open(url, 'r:binary', :http_basic_authentication => ['lafay', 'patr75']).read.encode('iso-8859-1', 'iso-8859-1')
        dirname = File.dirname(filename)
        unless File.directory?(dirname)
          FileUtils.mkdir_p(dirname)
        end
        File.open(filename, 'a:iso-8859-1').puts html
        sleep(1.0 / 8.0)
        puts 'done'
      rescue OpenURI::HTTPError => e
        puts url + ': ' + e.message
        return nil
      end
    end
    return html
  end

  def parse_result(url, year, ordinal, stageNb, subStageNb, prefix)
    puts 'working on ' + url
    html = ImportUtils.get_url_resource(url)
    if (html == nil)
      return nil
    end
    doc = Nokogiri::HTML(html)
    #nbsp = Nokogiri::HTML("&nbsp;").text
    doc.encoding = 'UTF-8'
    doc.css('script').each {|node| node.remove}
    doc.css('br').each {|node| node.replace('µµ')}
    doc.css('comment').each {|node| node.remove}
    result = ''
    valid = false
    ref_time = 0
    res_pos = []
    res_num = []
    res_time = []
    j = 0


    #doc.xpath('//td[@class='center']/a[following::tr[@class='strong'] and preceding::a[@name='ITE'] and not(preceding::a[@name='ITG']) and starts-with(@href,'/HISTO')]')
    race_id = MySQLUtils.getOrCreateRace(year, nil)['id']
    stage_details = doc.xpath("//text()[preceding::img[@src=\"../images/fin.gif\"]][following::img[@src=\"../images/tour_de_france/profil.gif\"]]").text().squeeze(" ").gsub("µ", "").strip
    stage_str = doc.xpath("//text()[preceding::img[@src=\"../images/tour_de_france/parcours.gif\"]][following::img[@src=\"../images/tour_de_france/profil.gif\"]]").text().gsub("\n", " ").squeeze(" ").gsub("µ", " ").strip
    if (stage_str == nil || stage_str.size == 0) then
      stage_str = doc.xpath("//text()[preceding::img[@src=\"../images/tour_de_france/parcours.gif\"]][following::a[@href=\"tdf#{year}.php\"]]").text().gsub("\n", " ").squeeze(" ").gsub("µ", " ").strip
    end
    if (stage_str == nil || stage_str.size == 0) then
      aaa = doc.xpath("//td[@class='texte']").text()
      val = aaa.to_s.gsub("\n", " ").squeeze(" ").gsub(CommentPattern, " ")
      val = val.strip
      tmp_line = val.split('µµ')
      tmp_line.each do |line|
        puts line
        if (line =~ StageDescRegex) then
          stage_str = line
          break
        end
      end
    end

    if (stage_str =~ StageDescRegex) then
      captures = stage_str.match(StageDescRegex).captures
      sstart = captures[0]
      send = captures[1]
      sdist = captures[2]
      sdate = captures[3]
      if sstart == nil then
        sstart = send
      end
      sstart.squeeze(" ").strip
      send.squeeze(" ").strip
      sdist.squeeze(" ").strip
      if (sdate != nil) then
        sdate = sdate.squeeze(" ").strip + " #{year}"
      end
      if (sstart == nil || sstart == "")
        sstart == send
      end
      is_TTT_stage = (stage_str =~ /CLM par équipes/)
      is_ITT = !is_TTT_stage && stage_str =~ /CLM/
    else
      raise "pb for stage #{stageNb}.#{subStageNb} (#{year}). No def found : >#{stage_str}<"
    end

    stage = MySQLUtils.getStage(race_id, stageNb, subStageNb)
    if (stage == nil) then
      #raise "pb for stage #{stageNb}.#{subStageNb} (#{year}). No stage found"
      if (is_ITT) then
        stage_type = "ITT"
      elsif (is_TTT_stage) then
        stage_type = "TTT"
      else
        stage_type = detectStageType(doc)
      end
      stage = MySQLUtils.createStage(race_id, year, stageNb, subStageNb, sstart, send, sdist, sdate, stage_type, ordinal, stage_details)
    else
      # MySQLUtils.updateStageRoute(stage, stage_details)
    end


    stage_id = stage['id'];
    tmp = doc.xpath("//td[@class='texte']")
    # TODO: on ne parse pas résultat montagne, maillot vert, etc... ce qui empêche de remplir ig_stage_result
    last_dif = 0
    last_pos = '?'
    last_time = 0
    stage_winner_str = nil
    jersey_str = nil
    mountain_str = nil
    sprint_str = nil
    young_str = nil
    team_str = nil
    combat_str = nil
    col_id = nil
    col_pos = 0
    col_str = nil
    col_cat = nil
    col_alt = nil
    col_km = nil
    mode = "ite"
    tmp.each do |node|
      val = node.text.to_s.gsub('\n', ' ')
      val.strip
      tmp_line = val.split('µµ')

      if (is_TTT_stage) then
        handler = self.method(:classementTTTLineHandler)
      else
        handler = self.method(:classementEtapeLineHandler)
      end
      tmp_line.each do |line|
        line = line.gsub(NBSP_CHAR, ' ').gsub(CommentPattern, "").gsub(/\s+/, ' ').strip
        # puts "parsing >#{line}<"
        if (line.include?('Etape')) then
          mode = 'ite'
        elsif (line.include?('Hors-delai') || line.include?('Hors-delais') || line.include?('Disqualifié') || line.include?('Disqualifiés')) then
          mode = 'dnq'
        elsif (line.include?('Non-partant') || line.include?('Non-partants')) then
          mode = 'dns'
        elsif (line.include?('Abandon') || line.include?('Abandons')) then
          mode = 'dnf'
        elsif (line.include?("Côtes de l'étape") || line.include?("Côte de l'étape")) then
          mode = 'cols'
        elsif line.include?('Points :') || (line.include?('Classement général par points') || line.include?('Classement par points')) then
          mode = 'sprint'
          handler = self.method(:discardLineHandler)
        elsif (line.include?('Montagne :') || line.include?('Classement général de la montagne') || line.include?('Classement de la montagne')) then
          mode = 'mountain'
        elsif (line.include?('Classement général des jeunes') || line.include?('Classement des jeunes')) then
          mode = 'young'
        elsif line.include?('Equipes :') || (line.include?('Classement général par équipes') || line.include?('Classement par équipes')) then
          mode = 'team'
        elsif (line.include?('Classement général')) then
          mode = 'jersey'
          last_dif = 0
          last_pos = '?'
          last_time = 0
          handler = self.method(:classementGeneralLineHandler)
        elsif (line.include?('Prix de la combativité') && line.match(/:\W*(?:\d+\.)?\W*([-'A-zÀ-ÿ\s]+)\W+\((\w{3})\)/)) then
          combat_str = line.match(/:\W*(?:\d+\.)?\W*([-'A-zÀ-ÿ\s]+)\W+\((\w{3})\)/).captures[0]
        elsif (mode == 'cols' && line =~ PatternCol) then
          col_pos += 1
          col_km = line.match(PatternCol).captures[0]
          col_str = line.match(PatternCol).captures[1]
          col_alt = line.match(PatternCol).captures[2]
          col_cat = line.match(PatternCol).captures[3]
          if (col_cat == nil || col_cat == "")
            col_cat = "Cat.H.C"
          end
          if (col_cat != nil && MountainCategoryMapping[col_cat] != nil) then
            col_cat = MountainCategoryMapping[col_cat]
          end
        elsif (line =~ PatternWinner) then
          winner = line.match(PatternWinner).captures[0]
          if (mode == 'ite' && stage_winner_str == nil) then
            stage_winner_str = winner
          elsif (mode == 'jersey' && jersey_str == nil) then
            jersey_str = winner
          elsif (mode == 'sprint' && sprint_str == nil) then
            sprint_str = winner
          elsif (mode == 'mountain' && mountain_str == nil) then
            mountain_str = winner
          elsif (mode == 'young' && young_str == nil) then
            young_str = winner
          elsif (mode == 'team' && team_str == nil) then
            team_str = winner
          elsif (col_str != nil && mode == 'cols') then
            MySQLUtils.getOrCreateMountain(year, stage_id, normalize_name(winner), col_str, col_cat, col_pos, col_km, col_alt)
          end
        end

        if (mode != 'team') then
          if (line =~ PatternDelay) then
            captures = line.match(PatternDelay).captures
            position = captures[0]
            rr_name = captures[1]
            nationality = captures[2]
            last_dif = Utils.strDurationToSec(captures[3], captures[4], captures[5])
            time = last_dif + last_time
            last_pos = position
            handler.call(year, stage_id, position, normalize_name(rr_name), nationality, time, last_dif)
            # puts 'set last_pos to à >' + last_pos + '<'
          elsif (line =~ PatternTime) then
            captures = line.match(PatternTime).captures
            position = captures[0]
            rr_name = captures[1]
            nationality = captures[2]
            time = Utils.strDurationToSec(captures[3], captures[4], captures[5])
            last_dif = last_time == 0 ? 0 : time - last_time
            last_time = time
            last_pos = position
            handler.call(year, stage_id, position, normalize_name(rr_name), nationality, time, last_dif)
            # resume here (add other Pattern, exploit them)
            # last_pos = tmp.split(';')[0]
            # last_dif = ''
            # output.puts prefix + tmp
            # puts 'set last_pos to en >' + last_pos + '<'
          elsif (line =~ PatternSameTime1) then
            captures = line.match(PatternSameTime1).captures
            position = captures[0]
            rr_name = captures[1]
            nationality = captures[2]
            last_pos = position
            time = last_time + last_dif
            handler.call(year, stage_id, position, normalize_name(rr_name), nationality, time, last_dif)
            # puts 'set last_pos to >' + last_pos + '<'
          elsif (line =~ PatternSingle) then
            captures = line.match(PatternSingle).captures
            rr_name = captures[0]
            rr_name = normalize_name(rr_name)
            nationality = captures[1]
            if (mode == "dns") then
              MySQLUtils.create_ITE_stage_result(year, stage_id, nil, rr_name, nationality, nil, nil, true, false, false)
            elsif (mode == "dnf") then
              MySQLUtils.create_ITE_stage_result(year, stage_id, nil, rr_name, nationality, nil, nil, false, true, false)
            elsif (mode == "dnq") then
              MySQLUtils.create_ITE_stage_result(year, stage_id, nil, rr_name, nationality, nil, nil, false, false, true)
            end
          else
            if (line =~ ExtraInfosPattern) then
              comment = line.match(ExtraInfosPattern).captures[0]
              MySQLUtils.addInfosToStage(stage_id, comment)
            else
              puts 'unable to parse: ' + '>' + line + '<'
            end
          end

        end
      end
      #puts '!!' + val + '!!'
      j = j + 1
    end

    j = j + 1


    MySQLUtils.create_IG_stage_result(year, stage_id, normalize_name(stage_winner_str), normalize_name(jersey_str), normalize_name(sprint_str), normalize_name(mountain_str), normalize_name(young_str), nil, normalize_name(combat_str))


    if (res_time.length == res_num.length && res_num.length == res_pos.length) then

      for j in (0..res_num.length - 1) do
        res = prefix + res_num[j] + ';' + res_pos[j] + ';' + res_time[j] + ';\n'
        result = result + res
      end
      return result
    else
      puts 'res_num.length : ' + res_num.length.to_s
      puts 'res_pos.length : ' + res_pos.length.to_s
      puts 'res_time.length : ' + res_time.length.to_s
      puts 'pb for stage ' + prefix
      return nil
    end
  end

  def detectStageType(doc)
    return "plaine ?"
  end

  def get_prefix_url(year)
    if (year >= 1987) then
      'http://www.memoire-du-cyclisme.eu/eta_tdf_2010_2019/'
    elsif (year >= 2006) then
      'http://www.memoire-du-cyclisme.eu/eta_tdf_2006/'
    elsif (year >= 1978) then
      'http://www.memoire-du-cyclisme.eu/eta_tdf_1978_2005/'
    elsif (year >= 1947) then
      'http://www.memoire-du-cyclisme.eu/eta_tdf_1947_1977/'
    else
      'http://www.memoire-du-cyclisme.eu/eta_tdf_1903_1939/'
    end
  end

  def get_generic_infos(prefix_url, year)
    url = "#{prefix_url}tdf#{year}.php"

    html = ImportUtils.get_url_resource(url)
    if (!html) then
      html = ImportUtils.get_url_resource("http://www.memoire-du-cyclisme.eu/eta_tdf/tdf#{year}.php")
    end
    doc = Nokogiri::HTML(html)
    doc.encoding = 'utf-8'
    doc.css('script, link').each {|node| node.remove}
    doc.css('br').each {|node| node.replace('µµ')}


    # http://rubular.com/
    runner_regexp = /^([0-9]+)\s+([[[:upper:]]c\s\-\']+)\s+([[:upper:]][[[:alpha:]]\'\-\s]+)\s+\(([[:upper:]][[:alpha:]]+)\).*/
    race_runner_result_regexp = /([0-9]+)\.\s+([[:upper:]][[[:alpha:]]\'\-\s]+)\s+([[[:upper:]]c\s\-\']+)\(([[:upper:]][[:alpha:]]+)\)\s+en\s+([[:digit:]]+h[[:digit:]]+'[[:digit:]]+").*/

    race_description = doc.xpath("//text()[preceding::b[u[text()='La petite histoire']]][following::a[@name='partants']]").text().gsub("µµ", "\n").squeeze(" ").strip;


    cgeneralstr = doc.xpath("//text()[preceding::img[@src='../images/tour_de_france/maillot_jaune.gif']][following::u[text()='Classement par points']]").text()

    cgeneralstr.split('µµ').each do |line|
      if ((line =~ race_runner_result_regexp)) then
        line = line.gsub(race_runner_result_regexp, '\1\t\2\t\3\t\4\t\5').split('\t')
        firstname = line[1].strip
        lastname = line[2].strip
        nationality = line[3].strip
        #puts line
      else
        puts "discard >#{line}<"
      end
    end

    race = MySQLUtils.getOrCreateRace(year, race_description);


    runners = doc.xpath("//node()[preceding::a[@name='partants']][following-sibling::a[@name='etapes']]")
    if (runners == nil || runners.size() == 0 || runners == "") then
      runners = doc.xpath("//node()[preceding::a[@name='Les partants']][following::a[@href='../eta_tdf/tour_de_france.php']]")
    end
    if (runners == nil || runners.size() == 0 || runners == "") then
      raise "no runners found for year #{year}"
    end
    current_team = "<unknown>"
    runners.each do |node|
      if (node.name == "strong" || node.name == "b") then
        current_team = node.text
        # puts "#find new team #{current_team}"
      else
        val = node.text.to_s.gsub('\n', '')
        tmp = val.split('µµ')

        tmp.each do |line|
          line.strip!
          line = line.gsub(/[[:space:]]/, ' ')

          if (line =~ runner_regexp) then
            recordstr = line.gsub(runner_regexp, '\1\t\2\t\3\t\4\t')
            record = recordstr.split('\t')
            dossard = record[0].strip
            lastname = record[1].strip
            firstname = record[2].strip
            nationality = NationalityUtils.normalizeNationality(record[3].strip)
            if (firstname != nil && firstname.length > 1 && lastname != nil && lastname.length > 1 && dossard != nil && dossard.length > 0) then
              rr = MySQLUtils.getOrCreateRaceRunner(year, dossard, lastname, firstname, nationality, current_team)
              @runner_map_id[my_downcase(firstname + ' ' + lastname)] = rr['id']
              @runner_map_name[my_downcase(firstname + ' ' + lastname)] = rr['firstname'] + ' ' + rr['lastname']

            else
              puts "bad format ? >#{line}<"
            end
          else
            if (line =~ /^([0-9]+)\s+/) then
              puts "discard ? >#{line}<"
            else
              # puts ">#{line}<"
            end
          end
        end
      end
    end

  end

  def parse_ig_result(prefix_url, year)
    url = "#{prefix_url}tdf#{year}.php"
    ImportUtils.get_url_resource(url)

    race = MySQLUtils.getOrCreateRace(year, nil)
    race_id = race['id']
    html = ImportUtils.get_url_resource(url)

    if (!html) then
               html = ImportUtils.get_url_resource("http://www.memoire-du-cyclisme.eu/eta_tdf/tdf#{year}.php")
    end
    if (!html) then
      raise "unable to find #{url}"
    end
    doc = Nokogiri::HTML(html)
    doc.encoding = 'utf-8'
    doc.css('script, link').each {|node| node.remove}
    doc.css('br').each {|node| node.replace('µµ')}


    # http://rubular.com/
    runner_regexp = /^([0-9]+)\s+([[[:upper:]]c\s\-\']+)\s+([[:upper:]][[[:alpha:]]\'\-\s]+)\s+\(([[:upper:]][[:alpha:]]+)\).*/
    race_runner_result_regexp = /([0-9]+)\.\s+([[:upper:]][[[:alpha:]]\'\-\s]+)\s+([[[:upper:]]c\s\-\']+)\(([[:upper:]][[:alpha:]]+)\)\s+en\s+([[:digit:]]+h[[:digit:]]+'[[:digit:]]+").*/

    race_description = doc.xpath("//text()[preceding::b[u[text()='La petite histoire']]][following::a[@name='partants']]").text().gsub("µµ", "\n").squeeze(" ").strip;


    cgeneralstr = doc.xpath("//text()[preceding::b[u[text()='Classement général']]][following::b[u[text()='Classement par points']]]").text()
    #cgeneralstr = doc.xpath("//text()[preceding::b[u[text()='Classement général']]]").text()
    if cgeneralstr == nil || cgeneralstr == "" then
      cgeneralstr = doc.xpath("//text()[preceding::img[@src='../images/tour_de_france/maillot_jaune.gif']]").text()
    end
    if cgeneralstr == nil || cgeneralstr == "" then
      cgeneralstr = doc.xpath("//text()[preceding::img[@src='../images/tour_de_france/classements.gif']]").text()
    end
    doc.encoding = 'UTF-8'
    doc.css('script').each {|node| node.remove}
    doc.css('br').each {|node| node.replace('µµ')}
    doc.css('comment').each {|node| node.remove}
    result = ''
    valid = false
    ref_time = 0
    res_pos = []
    res_num = []
    res_time = []

    #doc.xpath('//td[@class='center']/a[following::tr[@class='strong'] and preceding::a[@name='ITE'] and not(preceding::a[@name='ITG']) and starts-with(@href,'/HISTO')]')
    last_dif = 0
    last_pos = '?'
    last_time = 0
    stage_winner_str = nil
    jersey_str = nil
    mountain_str = nil
    sprint_str = nil
    young_str = nil
    team_str = nil
    combat_str = nil
    col_id = nil
    col_pos = 0
    col_str = nil
    col_cat = nil
    col_km = nil
    mode = "ite"
    last_stage = MySQLUtils.getLastStage(year)

    if (last_stage == nil)
      raise "no last stage for year #{year}"
    end
    stage_id = last_stage['id']
    stage_winner_id = MySQLUtils.getStageInfos(stage_id)['stage_winner_id']
    stage_winner_str = MySQLUtils.getRaceRunnerName(stage_winner_id)

    cgeneralstr = cgeneralstr.to_s.gsub('\n', ' ')
    cgeneralstr = cgeneralstr.strip
    tmp_line = cgeneralstr.split('µµ')
    mode = 'jersey'
    handler = self.method(:classementGeneralLineHandler)
    tmp_line.each do |line|
      line = line.gsub(NBSP_CHAR, ' ').gsub(/\s+/, ' ').strip

      if (line.include?('Etape')) then
        mode = 'ite'
      elsif (line.include?('Hors-delai') || line.include?('Hors-delais') || line.include?('Disqualifié') || line.include?('Disqualifiés')) then
        mode = 'dnq'
      elsif (line.include?('Non-partant') || line.include?('Non-partants')) then
        mode = 'dns'
      elsif (line.include?('Abandon') || line.include?('Abandons')) then
        mode = 'dnf'
      elsif (line.include?("Côtes de l'étape") || line.include?("Côte de l'étape")) then
        mode = 'cols'
      elsif (line.include?('Classement général')) then
        mode = 'jersey'
      elsif (line.include?('Classement par points')) then
        mode = 'sprint'
      elsif (line.include?('Classement de la montagne')) then
        mode = 'mountain'
      elsif (line.include?('Classement des jeunes')) then
        mode = 'young'
      elsif (line.include?('Classement des équipes')) then
        mode = 'team'
      elsif (line.include?('Prix de la combativité') && line.match(/:\W*(?:\d+\.)?\W*([-'A-zÀ-ÿ\s]+)\W+\((\w{3})\)/)) then
        combat_str = line.match(/:\W([-'A-zÀ-ÿ\s]+)\W+\((\w{3})\)/).captures[0]
      elsif (mode == 'cols' && line =~ PatternCol) then
        col_pos += 1
        col_km = line.match(PatternCol).captures[0]
        col_str = line.match(PatternCol).captures[1]
        col_cat = line.match(PatternCol).captures[2]
        if (col_cat != nil && MountainCategoryMapping[col_cat] != nil) then
          col_cat = MountainCategoryMapping[col_cat]
        end
      elsif (line =~ PatternWinner) then
        winner = line.match(PatternWinner).captures[0]
        if (mode == 'ite' && stage_winner_str == nil) then
          stage_winner_str = winner
        elsif (mode == 'jersey' && jersey_str == nil) then
          jersey_str = winner
        elsif (mode == 'sprint' && sprint_str == nil) then
          sprint_str = winner
        elsif (mode == 'mountain' && mountain_str == nil) then
          mountain_str = winner
        elsif (mode == 'young' && young_str == nil) then
          young_str = winner
        elsif (mode == 'team' && team_str == nil) then
          team_str = winner
        elsif (col_str != nil && mode == 'cols') then
        end
      elsif (line =~ PatternTime) then
        winner = line.match(PatternTime).captures[1]
        if (mode == 'team' && team_str == nil) then
          team_str = winner
        end
      end
      if (line =~ PatternDelay) then
        captures = line.match(PatternDelay).captures
        position = captures[0]
        rr_name = captures[1]
        nationality = captures[2]
        last_dif = Utils.strDurationToSec(captures[3], captures[4], captures[5])
        time = last_dif + last_time
        last_pos = position
        handler.call(year, stage_id, position, normalize_name(rr_name), nationality, time, last_dif)
        # puts 'set last_pos to à >' + last_pos + '<'
      elsif (line =~ PatternTime) then
        captures = line.match(PatternTime).captures
        position = captures[0]
        rr_name = captures[1]
        nationality = captures[2]
        time = Utils.strDurationToSec(captures[3], captures[4], captures[5])
        last_dif = last_time == 0 ? 0 : time - last_time
        last_time = time
        last_pos = position
        handler.call(year, stage_id, position, normalize_name(rr_name), nationality, time, last_dif)
        # resume here (add other Pattern, exploit them)
        # last_pos = tmp.split(';')[0]
        # last_dif = ''
        # output.puts prefix + tmp
        # puts 'set last_pos to en >' + last_pos + '<'
      elsif (line =~ PatternSameTime1) then
        captures = line.match(PatternSameTime1).captures
        position = captures[0]
        rr_name = captures[1]
        nationality = captures[2]
        last_pos = position
        time = last_time + last_dif
        handler.call(year, stage_id, position, normalize_name(rr_name), nationality, time, last_dif)
        # puts 'set last_pos to >' + last_pos + '<'
      elsif (line =~ PatternSingle) then
        captures = line.match(PatternSingle).captures
        rr_name = captures[0]
        nationality = captures[1]
        rr_name = normalize_name(rr_name)
        if (mode == "dns") then
          MySQLUtils.create_ITE_stage_result(year, stage_id, nil, rr_name, nationality, nil, nil, true, false, false)
        elsif (mode == "dnf") then
          MySQLUtils.create_ITE_stage_result(year, stage_id, nil, rr_name, nationality, nil, nil, false, true, false)
        elsif (mode == "dnq") then
          MySQLUtils.create_ITE_stage_result(year, stage_id, nil, rr_name, nationality, nil, nil, false, false, true)
        end
      else
        puts 'unable to parse: ' + '>' + line + '<'
      end

    end
    MySQLUtils.create_IG_stage_result(year, stage_id, normalize_name(stage_winner_str), normalize_name(jersey_str), normalize_name(sprint_str), normalize_name(mountain_str), normalize_name(young_str), nil, normalize_name(combat_str))
    MySQLUtils.create_IG_race_result(year, race_id, normalize_name(jersey_str), normalize_name(sprint_str), normalize_name(mountain_str), normalize_name(young_str), nil, normalize_name(combat_str))
  end

  def my_downcase(s)
    return nil if s.nil?
    Unicode::downcase(s.squeeze(" "))
  end

  def normalize_name(name)
    return nil if name.nil?
    result = @runner_map_name[my_downcase(name)]
    if (result == nil)
      s = name
      s.tr('ÁÉÍÓÚ', 'aeiou')
      s.tr!('ÀÈÌÒÙ', 'aeiou')
      s.tr!('ÄËÏÖÜ', 'aeiou')
      s.tr!('ÂÊÎÔÛ', 'aeiou')
      s.tr!('áéíóú', 'aeiou')
      s.tr!('àèìòù', 'aeiou')
      s.tr!('äëïöü', 'aeiou')
      s.tr!('âêîôû', 'aeiou')
      s.tr!('ØøñÑ', 'oonn')
      result = @runner_map_name[my_downcase(s)]

    end
    if (result == nil)
      name
    else
      result
    end
  end

  def retrieve_stage(year, stageNb)
    @runner_map_id = Hash.new
    @runner_map_name = Hash.new
    prefix_url = get_prefix_url(year)
    get_generic_infos(prefix_url, year)
    prefix_url = get_prefix_url(year)
    url = "#{prefix_url}tdf#{year}_#{stageNb}.php"
    parse_result(url, year, stageNb, stageNb, 0, year.to_s + ';' + stageNb.to_s + '.' + 0.to_s + ';')
  end

  def get_stages_infos(prefix_url, year)

    stage = 0
    sub = 0
    ordinal = stage + sub
    remaining_stage = true
    while (remaining_stage && stage <= 24) do
      begin
        search_sub = false
        result_found = false
        error = false
        stage_str = if (stage == 0) then
                      'p'
                    else
                      stage.to_s
                    end
        if (sub > 0) then
          search_sub = true
          if (sub == 1) then
            stage_str = stage_str + 'a'
          end
          if (sub == 2) then
            stage_str = stage_str + 'b'
          end
          if (sub == 3) then
            stage_str = stage_str + 'c'
          end
          if (sub == 4) then
            stage_str = stage_str + 'd'
          end
        end
        url = "#{prefix_url}tdf#{year}_#{stage_str }.php"
        #	url = 'http://www.memoire-du-cyclisme.net/eta_tdf_1978_2005/Mémoire du cyclisme_files/tdf1981_7.htm'

        #url = 'http://www.letour.fr/HISTO/fr/TDF/' + year.to_s + '/' + stage.to_s+'0'+sub.to_s+'/etape.html'

        result = parse_result(url, year, ordinal, stage, sub, year.to_s + ';' + stage.to_s + '.' + sub.to_s + ';')
        if (result != nil) then
          # file.puts(result)
          # file.flush
          if (search_sub) then
            sub = sub + 1
          elsif stage = stage + 1
          end
        else
          puts 'no result found for stage y:' + year.to_s + ' s:' + stage.to_s + ' sub:' + sub.to_s
          if (search_sub) then
            puts 'PB : no result found for stage y:' + year.to_s + ' s:' + stage.to_s + ' sub:' + sub.to_s
            if (stage > 0 && sub == 1) then
              remaining_stage = false
            end
            stage = stage + 1
            sub = 0
          else
            sub = sub + 1
          end
        end
        ordinal += 1
      end
    end
  end

  def classementTTTLineHandler(year, stage_id, position, team_name, nationality, time, dif_time)
    #   captures = line.match(patterTeamTTT).captures
    MySQLUtils.create_ITE_stage_result_TTT(year, stage_id, position, team_name, time, dif_time, false, false, false)
    # puts "TTT: #{year}-#{stage_id} #{position} #{rr_name} (#{nationality}) #{time} (#{last_dif})"
  end


  def classementGeneralLineHandler(year, stage_id, position, rr_name, nationality, time, last_dif)
    MySQLUtils.create_yj_stage_result(year, stage_id, position, rr_name, nationality, time, last_dif)
  end

  def classementEtapeLineHandler(year, stage_id, position, rr_name, nationality, time, last_dif)
    MySQLUtils.create_ITE_stage_result(year, stage_id, position, rr_name, nationality, time, last_dif)
  end

  def discardLineHandler(year, stage_id, position, rr_name, nationality, time, last_dif)
    # puts "discard: #{position}"
  end

  def retrieve_year(year)
    @runner_map_id = Hash.new
    @runner_map_name = Hash.new
    prefix_url = get_prefix_url(year)
    get_generic_infos(prefix_url, year)
    get_stages_infos(prefix_url, year)
    parse_ig_result(prefix_url, year)
  end
end

