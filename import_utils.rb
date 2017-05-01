require 'nokogiri'
require 'open-uri'
require 'chronic_duration'
require_relative 'my_sql_utils'
require_relative 'nationality_utils'

class ImportUtils

  NBSP_CHAR = 160.chr(Encoding::UTF_8)

  @@mu = MySQLUtils.new

  def get_url_resource(url)
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
        sleep(1.0/8.0)
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
    html = get_url_resource(url)
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
    ref_time=0
    res_pos = []
    res_num = []
    res_time = []
    j = 0

    commentPattern = /<!--[\s\S\n]*?-->/
    patternSingle = /^([-'A-zÀ-ÿ\s]+)\W+\((\w{3})\)$/
    patternWinner = /^1\.\W+([-'A-zÀ-ÿ\s]+)\W+\((\w{3})\)/
    patternTime = /(\d+)\.\W+([-'A-zÀ-ÿ\s]+)\s+\((\w{3})\)\W+en\W+(?:(\d+)h)?(?:(\d+)')?(\d+)/ # match: "1. Marcel Kittel (All) en 4h56'52" (moy : 43.050 km/h)" avec nat, heure et minute optionnelle
    patternDelay = /(\d+)\.\W+([-'A-zÀ-ÿ\s]+)\s+\((\w{3})\)\W+à\W+(?:(\d+)h)?(?:(\d+)')?(\d+)/ # match: "30. Andreas Klöden (All) à 1h02'43" avec heure et minute optionnelle
    patternSameTime1 = /(\d+)\.\W+([-'A-zÀ-ÿ\s]+)\W+\((\w{3})\)(?:\W+m\.t\.)?/ # match 22. Andrew Talansky (Usa) m.t.

    #doc.xpath('//td[@class='center']/a[following::tr[@class='strong'] and preceding::a[@name='ITE'] and not(preceding::a[@name='ITG']) and starts-with(@href,'/HISTO')]')
    race_id = @@mu.getOrCreateRace(year, nil)['id']
    stage_str = doc.xpath("//text()[preceding::img[@src=\"../images/tour_de_france/parcours.gif\"]][following::a[@href=\"tdf2013.php\"]]").text().gsub("\n", "").squeeze(" ").gsub("µ", "").strip
    stage_details = doc.xpath("//text()[preceding::img[@src=\"../images/fin.gif\"]][following::img[@src=\"../images/tour_de_france/profil.gif\"]]").text().squeeze(" ").gsub("µ", "").strip
    stage_desc_regex = /([\s'\w-]*)-(.*),\D+([\d\.]+)\s+km.*\((.*)\)/
    if (stage_str == nil || stage_str.size == 0) then
      aaa = doc.xpath("//td[@class='texte']").text()
      val=aaa.to_s.gsub("\n", " ").squeeze(" ").gsub(commentPattern, "")
      val = val.strip
      tmp_line = val.split('µµ')
      tmp_line.each do |line|
        puts line
        if (line =~ stage_desc_regex) then
          stage_str = line
          break
        end
      end
    end

    if (stage_str =~ stage_desc_regex) then
      sarr = stage_str.gsub(stage_desc_regex, '\1;\2;\3;\4;').split(';')
      sstart = sarr[0].squeeze(" ").strip
      send = sarr[1].squeeze(" ").strip
      sdist = sarr[2].squeeze(" ").strip
      sdate = sarr[3].squeeze(" ").strip
    else
      puts "pb for stage #{stageNb}.#{subStageNb} (#{year}). No def found : >#{stage_str}<"
    end
    stage = @@mu.getStage(race_id, stageNb, subStageNb)
    if (stage == nil) then
      stage_type = detectStageType(doc)
      stage = @@mu.createStage(race_id, year, stageNb, subStageNb, sstart, send, sdist, sdate, stage_type, ordinal, stage_details)
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
    mode = "ite"
    tmp.each do |node|
      val=node.text.to_s.gsub('\n', ' ')
      val.strip
      tmp_line = val.split('µµ')

      handler = self.method(:classementEtapeLineHandler)
      tmp_line.each do |line|
        line = line.gsub(NBSP_CHAR, ' ').gsub(/\s+/, ' ').strip
        if (line.include?('Etape :')) then
          mode = "ite"
        elsif (line.include?('Hors-delai :') || line.include?('Disqualifié :') || line.include?('Disqualifiés :')) then
          mode = "dnq"
        elsif (line.include?('Non-partant :') || line.include?('Non-partants :')) then
          mode = "dns"
        elsif (line.include?('Abandon :') || line.include?('Abandons :')) then
          mode = "dnf"
        elsif (line.include?('Classement général :')) then
          mode = "jersey"
          handler = self.method(:classementGeneralLineHandler)
        elsif (line.include?('Classement général par points')) then
          mode = "sprint"
          handler = self.method(:discardLineHandler)
        elsif (line.include?('Classement général de la montagne :')) then
          mode = "mountain"
        elsif (line.include?('Classement général des jeunes :')) then
          mode = "young"
        elsif (line.include?('Classement général par équipes :')) then
          mode = "team"
        elsif (line.include?('Prix de la combativité : ')) then
          combat_str = line.match(/:\W([-'A-zÀ-ÿ\s]+)\W+\((\w{3})\)/).captures[0]
        else
          if (line =~ patternWinner) then
            winner = line.match(patternWinner).captures[0]
            if (mode == "ite" && stage_winner_str == nil) then
              stage_winner_str = winner
            elsif (mode == "jersey" && jersey_str == nil) then
              jersey_str = winner
            elsif (mode == "sprint" && sprint_str == nil) then
              sprint_str = winner
            elsif (mode == "mountain" && mountain_str == nil) then
              mountain_str = winner
            elsif (mode == "young" && young_str == nil) then
              young_str = winner
            elsif (mode == "team" && team_str == nil) then
              team_str = winner
            end
          end

          if (line =~ patternDelay) then
            captures = line.match(patternDelay).captures
            position = captures[0]
            rr_name = captures[1]
            nationality = captures[2]
            last_dif = Utils.strDurationToSec(captures[3], captures[4], captures[5])
            time = last_dif + last_time
            last_pos = position
            handler.call(year, stage_id, position, rr_name, nationality, time, last_dif)
            # puts 'set last_pos to à >' + last_pos + '<'
          elsif (line =~ patternTime) then
            captures = line.match(patternTime).captures
            position = captures[0]
            rr_name = captures[1]
            nationality = captures[2]
            time = Utils.strDurationToSec(captures[3], captures[4], captures[5])
            last_dif = last_time == 0 ? 0 : time - last_time
            last_time = time
            last_pos = position
            handler.call(year, stage_id, position, rr_name, nationality, time, last_dif)
            # resume here (add other pattern, exploit them)
            # last_pos = tmp.split(';')[0]
            # last_dif = ''
            # output.puts prefix + tmp
            # puts 'set last_pos to en >' + last_pos + '<'
          elsif (line =~ patternSameTime1) then
            captures = line.match(patternSameTime1).captures
            position = captures[0]
            rr_name = captures[1]
            nationality = captures[2]
            last_pos = position
            time = last_time + last_dif
            handler.call(year, stage_id, position, rr_name, nationality, time, last_dif)
            # puts 'set last_pos to >' + last_pos + '<'
          elsif (line =~ patternSingle) then
            captures = line.match(patternSingle).captures
            rr_name = captures[0]
            nationality = captures[1]
            if (mode == "dns") then
              @@mu.create_ITE_stage_result(year, stage_id, nil, rr_name, nationality, nil, nil, true, false, false)
            elsif (mode = "dnf") then
              @@mu.create_ITE_stage_result(year, stage_id, nil, rr_name, nationality, nil, nil, false, true, false)
            elsif (mode = "dnq") then
              @@mu.create_ITE_stage_result(year, stage_id, nil, rr_name, nationality, nil, nil, false, false, true)
            end
          else
            #  tester pour "Mark Cavendish (Gbr)" avec mode dns ou dnf ou dnq
            puts 'unable to parse: ' + '>' + line + '<'
          end
        end
        #puts '!!' + val + '!!'
        j=j+1
      end
    end
    j=j+1


    @@mu.create_IG_stage_result(year, stage_id, stage_winner_str, jersey_str, sprint_str, mountain_str, young_str, team_str, combat_str)

    if (res_time.length == res_num.length && res_num.length == res_pos.length) then

      for j in (0..res_num.length - 1) do
        res = prefix + res_num[j] + ';' + res_pos[j]+ ';' + res_time[j] + ';\n'
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
    if (year >= 2014) then
      'http://www.memoire-du-cyclisme.eu/eta_tdf_2014_2023/'
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

  def retrieve_year(year)
    prefix_url = get_prefix_url(year)
    get_generic_infos(prefix_url, year)
    get_stages_infos(prefix_url, year)
  end

  def get_generic_infos(prefix_url, year)
    url = "#{prefix_url}tdf#{year}.php"
    get_url_resource(url)

    html = get_url_resource(url)
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

    race = @@mu.getOrCreateRace(year, race_description);


    runners = doc.xpath("//node()[preceding::a[@name='partants']][following-sibling::a[@name='etapes']]")
    current_team = "<unknown>"
    runners.each do |node|
      if (node.name == "strong" || node.name == "b") then
        current_team = node.text
        # puts "#find new team #{current_team}"
      else
        val=node.text.to_s.gsub('\n', '')
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
              @@mu.insertRaceRunner(year, dossard, lastname, firstname, nationality, current_team)
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

  def get_stages_infos(prefix_url, year)

    stage=1
    sub=0
    ordinal = stage + sub
    remaining_stage=true
    while (remaining_stage) do
      begin
        search_sub = false
        result_found=false
        error=false
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
              remaining_stage=false
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

  def classementGeneralLineHandler(year, stage_id, position, rr_name, nationality, time, last_dif)
    # puts "général: #{line}"
  end

  def classementEtapeLineHandler(year, stage_id, position, rr_name, nationality, time, last_dif)
    @@mu.create_ITE_stage_result(year, stage_id, position, rr_name, nationality, time, last_dif)
  end

  def discardLineHandler(year, stage_id, position, rr_name, nationality, time, last_dif)
    # puts "discard: #{position}"
  end
end