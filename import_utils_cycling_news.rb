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
        html = open(url, 'r:binary').read.encode('utf-8', 'utf-8')
        dirname = File.dirname(filename)
        unless File.directory?(dirname)
          FileUtils.mkdir_p(dirname)
        end
        File.open(filename, 'a:utf-8').puts html
        puts 'done'
      rescue OpenURI::HTTPError => e
        puts url + ': ' + e.message
        return nil
      end
    end
    return html
  end

  def parse_result(url, year, stageNb, isTTT = false)
    puts 'working on ' + url
    doc = Nokogiri::HTML(ImportUtils.get_url_resource(url))

    doc.encoding = 'UTF-8'
    doc.css('script').each {|node| node.remove}
    doc.css('comment').each {|node| node.remove}
    result = ''
    res_pos = []
    res_num = []
    res_time = []
    j = 0

    race_id = MySQLUtils.getOrCreateRace(2019, "")['id']
    stage = MySQLUtils.getStage(race_id, stageNb, 0)
    div_gc = doc.xpath("(//div[@class=\"results\"][preceding::h4[text()='Full Results']])[1]");
    if (!isTTT) then
      parse_ite(div_gc, stage)
    else
      parse_ttt(div_gc, stage)
    end
    div_yj = doc.xpath("(//tbody[preceding::caption[contains(text(), 'General Classification')]])[1]");
    if (div_yj == nil || div_yj.empty?) then
      div_yj = doc.xpath("(//tbody[preceding::caption[contains(text(), 'General classification')]])[1]");
    end
    parse_yj(div_yj, stage)


  end

  def parse_ite(div_gc, stage)
    ref_time = 0
    diff_time = 0
    div_gc.xpath(".//tr").each do |res|
      pos_s = res.xpath("td[1]/text()").text()
      if (pos_s != nil && !pos_s.empty?) then
        begin
          pos = Integer(pos_s)
        rescue
          if (pos =~ 'DNS') then
            dns = true
          elsif (pos =~ 'DNF') then
            dnf = true
          elsif (pos =~ 'DNQ') then
            dnq = true
          end
          pos = 900
        end
      end
      infos = res.xpath("td[2]/text()").text()
      time_s = res.xpath("td[3]/text()").text()
      if (time_s.match(/([0-9]+):([0-9]{2}):([0-9]{2})/)) then
        match = time_s.match(/([0-9]+):([0-9]{2}):([0-9]{2})/)
        time = Utils.strDurationToSec(match.captures[0], match.captures[1], match.captures[2])
      else
        #time = nil
      end
      if (pos == 1) then
        ref_time = time
        diff_time = 0
      else
        if (time != nil)
          diff_time = time
          ref_time += diff_time
        end
      end
      matches = infos.match(/(.*)\((.*)\)(.*)/)
      if (matches) then
        runner = matches.captures[0]
        nationality = matches.captures[1]
        nationality = NationalityUtils.normalizeNationality(nationality)
        team = matches.captures[2]
        puts "#{pos} #{runner} #{nationality} #{team} '#{diff_time}' (#{ref_time})"
        MySQLUtils.create_ITE_stage_result(stage['year'], stage['id'], pos, runner, nationality, ref_time, diff_time, dns, dnf, dnq)
      else
        puts "unable to parse result '#{infos}'"
      end
    end
  end

  def parse_ttt(div_gc, stage)
    ref_time = 0
    diff_time = 0
    div_gc.xpath(".//tr").each do |res|
      # puts res
      pos_s = res.xpath("td[1]/text()").text()
      if (pos_s != nil && !pos_s.empty?) then
        pos = Integer(pos_s)
      end
      team = res.xpath("td[2]/text()").text()
      time_s = res.xpath("td[3]/text()").text()
      if (time_s.match(/([0-9]+):([0-9]{2}):([0-9]{2})/)) then
        match = time_s.match(/([0-9]+):([0-9]{2}):([0-9]{2})/)
        time = Utils.strDurationToSec(match.captures[0], match.captures[1], match.captures[2])
      else
        #time = nil
      end
      if (pos == 1) then
        ref_time = time
        diff_time = 0
      else
        if (time != nil)
          diff_time = time
          ref_time += diff_time
        end
      end
      puts "#{pos} #{team} '#{diff_time}' (#{ref_time})"
      MySQLUtils.create_ITE_stage_result_TTT(stage['year'], stage['id'], pos, team, ref_time, diff_time)
    end
  end

  def parse_yj(div_yj, stage)
    ref_time = 0
    diff_time = 0
    div_yj.xpath(".//tr").each do |res|
      # puts res
      pos_s = res.xpath("td[1]/text()").text()
      if (pos_s != nil && !pos_s.empty?) then
        pos = Integer(pos_s)
      end
      infos = res.xpath("td[2]/text()").text()
      time_s = res.xpath("td[3]/text()").text()
      if (time_s.match(/([0-9]+):([0-9]{2}):([0-9]{2})/)) then
        match = time_s.match(/([0-9]+):([0-9]{2}):([0-9]{2})/)
        time = Utils.strDurationToSec(match.captures[0], match.captures[1], match.captures[2])
      else
        #time = nil
      end
      if (pos == 1) then
        ref_time = time
        diff_time = 0
      else
        if (time != nil)
          diff_time = time
          ref_time += diff_time
        end
      end
      matches = infos.match(/(.*)\((.*)\)(.*)/)
      if (matches) then
        runner = matches.captures[0]
        nationality = matches.captures[1]
        nationality = NationalityUtils.normalizeNationality(nationality)
        team = matches.captures[2]
        puts "#{pos} #{runner} #{nationality} #{team} '#{diff_time}' (#{ref_time})"
        MySQLUtils.create_yj_stage_result(stage['year'], stage['id'], pos, runner, nationality, ref_time, diff_time)
      else
        puts "unable to parse result '#{infos}'"
      end
    end
  end

end

iu = ImportUtils.new
#iu.parse_result("http://www.cyclingnews.com/tour-de-france/stage-1/results", 2019, 1)
#iu.parse_result("http://www.cyclingnews.com/tour-de-france/stage-2/results", 2019, 2, true)
#iu.parse_result("http://www.cyclingnews.com/tour-de-france/stage-3/results", 2019, 3,)
#iu.parse_result("http://www.cyclingnews.com/tour-de-france/stage-4/results", 2019, 4)

iu.parse_result("http://www.cyclingnews.com/tour-de-france/stage-6/results", 2019, 6)
