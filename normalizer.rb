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
            if ( currentInfos[index] != nil && val != previousInfos[index]) then # conflict solver
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

  for i in 2013..2016
    enforcePreviousStageInfos(i)
  end


end
