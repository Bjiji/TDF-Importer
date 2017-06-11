require 'mysql2'
require 'chronic_duration'

class Normalizer

  @@client = Mysql2::Client.new(:host => "localhost", :username => "root", :password => "root", :database => "tdf")

  def self.enforcePreviousStageInfos(year, conflict_mode = "overwrite")
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

  def self.updateStagePreviousInfos(stage_id, previousInfos)
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

  def self.getStages(year)
    @@client.query("SELECT s.* from stages s where s.year = #{year}")
  end

  def self.getPreviousStageInfo(stage_id)
    res = @@client.query("SELECT isr.stage_winner_id, isr.leader_id, isr.sprinter_id, isr.climber_id, isr.team_id, isr.young_id, isr.combine_id, isr.stage_combat_id, isr.overall_combat_id from ig_stage_results isr left join stages s on s.id = isr.stage_id left join stages s2 on s2.race_id = s.race_id and s2.ordinal = s.ordinal + 1 left join ig_stage_results isr2 on isr2.stage_id = s2.id where s2.id = #{stage_id};")
    if (res != nil && res.size > 0) then
      res.first
    else
      nil
    end
  end

  def self.getCurrentStageInfo(stage_id)
    res = @@client.query("SELECT isr.previous_stage_winner, isr.previous_leader, isr.previous_sprinter, isr.previous_climber, isr.previous_team, isr.previous_young, isr.previous_combine, isr.previous_stage_combat, isr.previous_overall_combat from ig_stage_results isr left join stages s on s.id = isr.stage_id where s.id = #{stage_id};")
    if (res != nil && res.size > 0) then
      res.first
    else
      nil
    end
  end

  def self.guessStageType(stage)
    if (stage['distance'] < 70) then
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

  def self.updateIgRaceResult(year)
    last_stage = @@client.query("SELECT s.* from stages s where s.year = #{year} and is_last = 1").first
    if (last_stage == nil) then
      raise "no last stage for year #{year}"
    else
      result = @@client.query("DELETE from ig_race_results where year = #{last_stage['race_id']}")
      result = @@client.query("SELECT #{year}, #{last_stage['race_id']}, leader_id, sprinter_id, climber_id, team_id, young_id, combine_id, overall_combat_id from ig_stage_results ite where ite.stage_id = #{last_stage['id']}").first
      MySQLUtils.create_IG_race_result_ids(*result.values)
    end

    # 2) use result as ig race result
  end

  def self.updateFirstLastStage(year)
    first_stage = @@client.query("SELECT s.* from stages s where s.year = #{year} and ordinal = '1'").first()
    last_stage = MySQLUtils.getLastStage(year)
    if (first_stage != nil) then
      @@client.query("update stages set is_first = '1' where id = #{first_stage['id']}")
    end
    if (last_stage != nil) then
      @@client.query("update stages set is_last = '1' where id = #{last_stage['id']}")
    end
  end

  def self.updateStageType(year)
    stages = getStages(year);
    stages.each do |stage|
      stage_id = stage['id']
      stage_type = nil #guessStageType(stage)
      current_type = @@client.query("select stage_type from stages where id  = '#{stage_id}'").first['stage_type']
      if stage_type != nil then
        @@client.query("update stages set stage_type = '#{stage_type}' where id = #{stage_id}")
      end
    end
  end

  def self.updateDistanceSpeed(year)
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


end
