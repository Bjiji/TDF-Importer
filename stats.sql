select *
from mountain_stage_results
limit 2;

select distinct leader_id, leader_s
from mountain_stage_results msr
where msr.year < 1920;

select *
from race_runners
where year = 0;

desc ig_stage_results;

select ig.stage_winner_s, s.*
from stages s
         left join ig_stage_results ig on ig.stage_id = s.id
where ig.stage_winner_id is null
  and NOT (s.stage_type like "ITT%" or s.stage_type like "TTT%");

/* villes étapes nouvelles par édition */
select count(1), res.year, group_concat(res.name)
from (select s.year as year, group_concat(s0.year) as bef, sl.name as name
      from stages s
               join stage_locations sl on (s.start_location = sl.id or s.finish_location = sl.id)
               left join stages s0 on ((s0.start_location = sl.id or s0.finish_location = sl.id) and s.year > s0.year)
      group by s.year, sl.id
      having bef is null) as res
group by year;

/* Arrivée dans des villes étapes nouvelles par édition */
select count(1), res.year, group_concat(res.name)
from (select s.year as year, group_concat(s0.year) as bef, sl.name as name
      from stages s
               join stage_locations sl on (s.finish_location = sl.id)
               left join stages s0 on ((s0.start_location = sl.id or s0.finish_location = sl.id) and s.year > s0.year)
      group by s.year, sl.id
      having bef is null) as res
group by year;


delete ysr
from yj_stage_results ysr
         join stages s on s.id = ysr.stage_id
where s.is_last
  and s.year = 1978
  and race_runner_id is null;
-- limit 10

delete ysr
from yj_stage_results ysr
         join stages s on s.id = ysr.stage_id
where s.is_last
  and s.year = 1978
  and pos > 78;

delete ysr
from yj_stage_results ysr
         join stages s on s.id = ysr.stage_id
where s.is_last
  and s.year = 2001
  and pos > 144;
-- limit 10

delete ysr.*
from yj_stage_results ysr
         join stages s on s.id = ysr.stage_id
where s.is_last
  and s.year in (1981, 1978, 1999, 2009)
  and race_runner_id is null
-- limit 10


select ysr.year, ysr.pos, ysr.runner_s, ysr2.runner_s, ysr2.id
from yj_stage_results ysr
         join stages s on s.id = ysr.stage_id
         join yj_stage_results ysr2 on ysr2.stage_id = ysr.stage_id and ysr.pos = ysr2.pos and ysr.id < ysr2.id
where s.is_last
  and ysr.year = 1999;

start transaction;
delete ysr2
from yj_stage_results ysr
         join stages s on s.id = ysr.stage_id
         join yj_stage_results ysr2 on ysr2.stage_id = ysr.stage_id and ysr.pos = ysr2.pos and ysr.id < ysr2.id
where s.is_last
  and ysr.year > 1999;
commit;

delete ysr2
from yj_stage_results ysr
         join stages s on s.id = ysr.stage_id
         join yj_stage_results ysr2 on ysr2.stage_id = ysr.stage_id and ysr.pos = ysr2.pos and ysr.id < ysr2.id
where s.is_last
  and ysr2.race_runner_id is null
  and ysr.year > 1999;

delete ysr2
from yj_stage_results ysr
         join stages s on s.id = ysr.stage_id
         join yj_stage_results ysr2 on ysr2.stage_id = ysr.stage_id and ysr.pos = ysr2.pos and ysr.id < ysr2.id
where s.is_last
  and ysr2.race_runner_id is null
  and ysr.year > 1945;

delete ysr2
from yj_stage_results ysr
         join stages s on s.id = ysr.stage_id
         join yj_stage_results ysr2 on ysr2.stage_id = ysr.stage_id and ysr.pos = ysr2.pos and ysr.id < ysr2.id
where s.is_last
--  and ysr2.race_runner_id is null
  and ysr.year = 2001;

select sum(r.distance)
from races r;

/* nombre de difficulté par édition */
select r.year, count(*)
from mountain_stage_results msr
         join stages s on s.id = msr.stage_id
         join races r on r.id = s.race_id
group by r.id;

/* nombre de difficulté > 2eme catégorie par par édition */
select r.year, count(*)
from mountain_stage_results msr
         join stages s on s.id = msr.stage_id
         join races r on r.id = s.race_id
where msr.category_s in ("HC", "1", "2")
group by r.id;

/* nombre d'étape sans difficulté par édition */
select r.year, count(distinct msr.stage_id), group_concat(msr.stage_id)
from stages s
         join races r on r.id = s.race_id
         left join mountain_stage_results msr on msr.stage_id = s.id
group by r.id;

select msr.name, msr.category_s, count(1), count(distinct rr.nationality), group_concat(rr.nationality) from mountain_stage_results msr
join race_runners rr on msr.leader_id = rr.id
group by msr.name
having (count(distinct rr.nationality) < 2)
;

select count(1), sl.name, group_concat(r.year) from stage_locations sl
join stages s on sl.id = s.finish_location
join races r on s.race_id = r.id
where (s.stage_type like ('ITT%') or s.stage_type like ('TTT%'))
and s.start_location = s.finish_location
and sl.country NOT LIKE 'France'
group by sl.name;

select count(1), sl.name, group_concat(r.year) from stage_locations sl
                                                        join stages s on sl.id = s.start_location
                                                        join races r on s.race_id = r.id
where s.ordinal = 1
  and sl.country NOT LIKE 'France'
group by sl.name;


select s.ordinal, start.name, finish.name, start.country as finish from stages s
join stage_locations finish on s.finish_location = finish.id
join stage_locations  start on s.start_location = start.id
where year = 2019;




