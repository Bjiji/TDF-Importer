require 'mysql2'
require 'chronic_duration'
require_relative 'utils'

class Normalizer

  @@client = Mysql2::Client.new(:host => "localhost", :username => "root", :password => "root", :database => "tdf")

  def enforcePreviousStageInfos(year, conflict_mode = "overwrite")
    stages = getStages(year);
    if (stages != nil && stages.size > 0) then
      stages.each do |stage|
        stage_id = stage['id']
        currentInfos = getCurrentStageInfo(stage_id)
        previousInfos = getPreviousStageInfo(stage_id)
        if (currentInfos != nil && previousInfos != nil) then
          currentInfos.each_with_index do |val, index|
            if (currentInfos[index] != nil && val != previousInfos[index]) then # conflict solver
              msg = "conflict between #{currentInfos[index]} and #{previousInfos[index]} for value #{val}, stage #{stage_id} (#{year})"
              if (conflict_mode == "error") then
                raise msg
              elsif (conflict_mode == "log") then
                previousInfos[index] = currentInfos[index] # keep old value, no overwrite
              end
              puts msg
            end
          end
          updateStagePreviousInfos(stage_id, previousInfos.values)
        end
      end
    end
  end

  def updateStagePreviousInfos(stage_id, previousInfos)
    query = "update ig_stage_results set previous_stage_winner = ?, previous_leader = ?, previous_sprinter = ?, previous_climber = ?, previous_team = ?, previous_young = ?, previous_combine = ?, previous_stage_combat = ?, previous_overall_combat = ? where stage_id = ?"
    begin
      statement = @@client.prepare(query)
      statement.execute(*previousInfos, stage_id)
    rescue Exception => e
      puts query
      puts e.message
      puts e.backtrace.inspect
    end
  end

  def getStages(year)
    @@client.query("SELECT s.* from stages s where s.year = #{year}")
  end

  def getPreviousStageInfo(stage_id)
    res = @@client.query("SELECT isr.stage_winner_id, isr.leader_id, isr.sprinter_id, isr.climber_id, isr.race_team_id, isr.young_id, isr.combine_id, isr.stage_combat_id, isr.overall_combat_id from ig_stage_results isr left join stages s on s.id = isr.stage_id left join stages s2 on s2.race_id = s.race_id and s2.ordinal = s.ordinal + 1 left join ig_stage_results isr2 on isr2.stage_id = s2.id where s2.id = #{stage_id};")
    if (res != nil && res.size > 0) then
      res.first
    else
      nil
    end
  end

  def getCurrentStageInfo(stage_id)
    res = @@client.query("SELECT isr.previous_stage_winner, isr.previous_leader, isr.previous_sprinter, isr.previous_climber, isr.previous_team, isr.previous_young, isr.previous_combine, isr.previous_stage_combat, isr.previous_overall_combat from ig_stage_results isr left join stages s on s.id = isr.stage_id where s.id = #{stage_id};")
    if (res != nil && res.size > 0) then
      res.first
    else
      nil
    end
  end

  def guessStageType(stage)
    if (stage['distance'] < 75) then
      "ITT"
    else
      res = @@client.query("select max(msr.finish) as finish, count(msr.id) as col_cnt,  IF(SUM(category_s = '1' OR category_s = 'HC' OR category_s = 'Cat.H.C' OR category_s = 'hGPM'), 'Yes', 'No') AS has1CatOrHarder, min(category_s) as min_cat
from stages s left join mountain_stage_results msr on s.id = msr.stage_id
where s.id = '#{stage['id']}' GROUP BY s.id;").first
      if (res != nil) then
        finish = res['finish'] == nil ? 0 : res['finish']
        col_cnt = res['col_cnt'] == nil ? 0 : res['col_cnt'].to_i
        isHard = res['has1CatOrHarder'] == nil ? false : res['has1CatOrHarder'] == "Yes"
        harderNumCat = res['min_cat'] == nil ? 0 : res['min_cat'].to_i
        if (finish > 0)
          if (isHard)
            "HMA"
          else
            "MMA"
          end
        else
          if (isHard && col_cnt > 1) then
            "HM"
          elsif (isHard && col_cnt == 1 || col_cnt >= 2 && harderNumCat < 3) then
            "MM"
          else
            "plaine"
          end
        end
      end
    end
  end

  def updateIgLastStageResult(year)
    puts year
    last_stage = @@client.query("SELECT s.* from stages s where s.year = #{year} and is_last = 1").first
    if (last_stage == nil) then
      raise "no last stage for year #{year}"
    else
      @@client.query("update ig_stage_results ig
      join stages s on s.id = ig.stage_id
      join ig_race_results ir on ir.year = s.year
      set ig.leader_id = ir.leader_id, ig.race_team_id = ir.race_team_id, ig.climber_id = ir.climber_id, ig.sprinter_id = ir.sprinter_id, ig.young_id = ir.young_id, ig.combine_id = ir.combine_id
      where s.year = #{year} and s.is_last");
    end
  end

  def updateIgRaceResult(year)
    raise "deprecated"
    last_stage = @@client.query("SELECT s.* from stages s where s.year = #{year} and is_last = 1").first
    if (last_stage == nil) then
      raise "no last stage for year #{year}"
    else
      result = @@client.query("DELETE from ig_race_results where year = #{year}")
      result = @@client.query("SELECT #{year}, #{last_stage['race_id']}, leader_id, sprinter_id, climber_id, race_team_id, young_id, combine_id, overall_combat_id from ig_stage_results ite where ite.stage_id = #{last_stage['id']}").first
      MySQLUtils.create_IG_race_result_ids(*result.values)
    end

    # 2) use result as ig race result
  end

  def updateFirstLastStage(year)
    first_stage = @@client.query("SELECT s.* from stages s where s.year = #{year} and ordinal = '1'").first()
    last_stage = MySQLUtils.getLastStage(year)
    if (first_stage != nil) then
      @@client.query("update stages set is_first = '1' where id = #{first_stage['id']}")
    end
    if (last_stage != nil) then
      @@client.query("update stages set is_last = '1' where id = #{last_stage['id']}")
    end
  end

  def updateStageType(year)
    stages = getStages(year);
    stages.each do |stage|
      stage_id = stage['id']
      stage_type = stage['stage_type']
      if (stage_type == nil || stage_type.include?("?")) then
      stage_type = guessStageType(stage)
      current_type = @@client.query("select stage_type from stages where id  = '#{stage_id}'").first['stage_type']
      if stage_type != nil then
        @@client.query("update stages set stage_type = '#{stage_type}' where id = #{stage_id}")
      end
      end
    end
  end

  def updateDistanceSpeed(year)
    stages = getStages(year);
    distance = 0
    stages.each do |stage|
      distance += stage['distance'].to_i
    end
    stage_id = MySQLUtils.getLastStage(year)['id']
    winner_res = @@client.query("select * from yj_stage_results where stage_id  = '#{stage_id}' and pos = 1").first
    if (winner_res != nil)
      time = winner_res['time_sec']
      averageSpeed = (distance * 1.0 / (time * 1.0 / 60 / 60)).round(3)
      @@client.query("update races set distance = '#{distance}', averageSpeed = '#{averageSpeed}' where year = #{year}")
    end

  end

  def enforce_entries_for_jersey_holders(year)
    enforce_entries_for_jersey_holder(year, "leader_id")
    enforce_entries_for_jersey_holder(year, "sprinter_id")
    enforce_entries_for_jersey_holder(year, "climber_id")
    enforce_entries_for_jersey_holder(year, "young_id")
    enforce_entries_for_jersey_holder(year, "previous_leader")
    enforce_entries_for_jersey_holder(year, "previous_sprinter")
    enforce_entries_for_jersey_holder(year, "previous_climber")
    enforce_entries_for_jersey_holder(year, "previous_young")
  end

  def enforce_entries_for_jersey_holder(year, jersey_column)

    missing_results = @@client.query("select s.id as stage_id,  ig.#{jersey_column} as runner_id, '800' as pos, s.year as year from ig_stage_results IG
    join stages s on s.id = ig.stage_id
    left join ite_stage_results ite on ite.stage_id = ig.stage_id and ite.race_runner_id = ig.#{jersey_column}
    where ig.year = #{year} and not(ig.#{jersey_column} is null) and ite.id is null")

    if (missing_results != nil && missing_results.size > 0) then

      missing_results.each do |mr|
        puts "fix #{jersey_column} for stage '#{mr["stage_id"]}'"
        query = "insert into ite_stage_results (stage_id, race_runner_id, pos, year) values (?,?,?,?)"
        begin
          statement = @@client.prepare(query)
          statement.execute(mr["stage_id"], mr["runner_id"], mr["pos"], mr["year"])
        rescue Exception => e
          puts e.message
          puts e.backtrace.inspect
          raise query
        end
      end
    end
  end

def cleanTeamName(year)
  race_teams = @@client.query("select rt.* from race_teams rt where year  = '#{year}'")
  race_teams.each do |rt|
    label = rt['label']
    team_id = rt['id']
    if (label != nil) then
    new_label = Utils.stripNonAlphaNum(label)
    end
    if (new_label != label) then
      @@client.query("update race_teams set label = '#{new_label}' where id = #{team_id}")
    end
  end
end

# n = Normalizer.new
# for year in 1947..2017
#   #iu.retrieve_year(year)
#
#   puts "clean #{year} year"
#   n.cleanTeamName(year)
#   #Normalizer.enforcePreviousStageInfos(year)
#   #Normalizer.enforce_entries_for_jersey_holders(year)
#   #Normalizer.enforcePreviousStageInfos(year)
#   #Normalizer.updateStageType(year)
#   #Normalizer.updateFirstLastStage(year)
#   #Normalizer.updateDistanceSpeed(year)
#   #Normalizer.updateIgLastStageResult(year)
# end

end

