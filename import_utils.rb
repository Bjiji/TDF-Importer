require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'chronic_duration'

class ImportUtils

  def get_resource(url)
    uri = URI(url)
    path = uri.path
    filename = 'cache' + path
    if File.exist?(filename) then
      puts 'using cache for resource'
      html = File.open(filename, 'r:UTF-8').read
    else
      begin
        print 'downloading resource... '
        html = open(url, 'r:binary', :http_basic_authentication => ['lafay', 'patr75']).read.encode('iso-8859-1', 'iso-8859-1')
        dirname = File.dirname(filename)
        unless File.directory?(dirname)
          FileUtils.mkdir_p(dirname)
        end
        File.open(filename, 'a:UTF-8').puts html
        puts 'done'
      rescue OpenURI::HTTPError => e
        puts url + ': ' + e.message
        return nil
      end
    end
    return html
  end

  def parse_result(url, prefix)
    puts 'working on ' + url
    html = get_resource(url)
    doc = Nokogiri::HTML(html)
    doc.encoding = 'utf-8'
    doc.css('script, link', 'img').each { |node| node.remove }
    doc.css('br').each { |node| node.replace('µµ') }
    result = ''
    valid = false
    ref_time=0
    res_pos = []
    res_num = []
    res_time = []
    j = 0
    #doc.xpath('//td[@class='center']/a[following::tr[@class='strong'] and preceding::a[@name='ITE'] and not(preceding::a[@name='ITG']) and starts-with(@href,'/HISTO')]')
    tmp = doc.xpath("//td[@class='texte']")
    output = File.open('stage_results-etapes-mdc2.txt', 'a:UTF-8')
    last_dif = ''
    last_pos = '?'
    tmp.each do |node|
      val=node.text.to_s.gsub('\n', '')
      val.strip
      tmp = val.split('µµ')

      tmp.each do |line|
        line.strip!
        line = line.gsub(/[[:space:]]/, ' ')
        if (line.include?('Classement')) then
          output.flush()
          output.close()
          output = File.open('stage_results-general-mdc.txt', 'a:UTF-8')
        elsif (line =~ /^([0-9]+)\. ([^à]+) à ([0-9]+.*)/) then
          tmp = line.gsub(/^([0-9]+)\. ([^à]+) à ([0-9]+.*)/, '\1;\2;;\3;')
          last_pos = tmp.split(';')[0]
          last_dif = tmp.split(';')[3]
          output.puts prefix + tmp
          puts 'set last_pos to à >' + last_pos + '<'
        elsif (line =~ /^([0-9]+)\. ([^à]+) en ([0-9]+.*)/) then
          tmp = line.gsub(/^([0-9]+)\. ([^à]+) en ([0-9]+.*)/, '\1;\2;\3;;')
          last_pos = tmp.split(';')[0]
          last_dif = ''
          output.puts prefix + tmp
          puts 'set last_pos to en >' + last_pos + '<'
        elsif (line =~ /^([0-9]+)\. (.*)/) then
          tmp = line.gsub(/^([0-9]+)\. (.*)/, '\1;\2;;' + last_dif)
          last_pos = tmp.split(';')[0]
          output.puts prefix + tmp
          puts 'set last_pos to >' + last_pos + '<'
        elsif (line =~ /^[ ][ ]+(.*)/) then
          output.puts prefix + line.gsub(/^[ ][ ]+(.*)/, last_pos + ';\1;;' + last_dif)
        else
          puts 'unable to parse: ' + '>' + line + '<'
        end
      end
      #puts '!!' + val + '!!'
      j=j+1
    end
    j=j+1


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
    output.flush()
    output.close()
  end

  def retrieve_stage()


  end

  def retrieve_year(year)
    file = File.open('stage_results-misssing-hugo.txt', 'a:UTF-8')
    file.puts('name;year;firstname;lastname;team;distance;averageSpeed;winnerPrize;poolPrize;')
    year = 1981
    stage=1
    sub=0
    remaining_stage=true
    while (stage < 5 && remaining_stage) do
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
        url = 'http://www.memoire-du-cyclisme.eu/eta_tdf_1978_2005/tdf1981_' + stage_str + '.php'
        #	url = 'http://www.memoire-du-cyclisme.net/eta_tdf_1978_2005/Mémoire du cyclisme_files/tdf1981_7.htm'

        #url = 'http://www.letour.fr/HISTO/fr/TDF/' + year.to_s + '/' + stage.to_s+'0'+sub.to_s+'/etape.html'

        result = parse_result(url, year.to_s + ';' + stage.to_s + '.' + sub.to_s + ';')
        if (result != nil) then
          file.puts(result)
          file.flush
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
        sleep(1.0/8.0)

      end
    end
  end

  ImportUtils.new.retrieve_year(1981)

end