class Utils

  def self.strDurationToSec(hours, mins, secs)
    hours.to_i * 3600 + mins.to_i * 60 + secs.to_i
  end

  def self.frenchToEnglishDate(date)
    date.downcase.gsub(/lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche/,
                       'lundi' => 'Monday',
                       'mardi' => 'Tuesday',
                       'mercredi' => 'Wednesday',
                       'jeudi' => 'Thursday',
                       'vendredi' => 'Friday',
                       'samedi' => 'Saturday',
                       'dimanche' => 'Sunday'
    ).gsub(/juin|juillet|aout|août/,
           'juin' => 'June',
           'juillet' => 'July',
           'aout' => 'August',
           'août' => 'August'
    )
  end

  puts strDurationToSec("1", "1", "")

end