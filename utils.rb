class Utils

  def self.stripNonAlphaNum(str)
    res = str
    if (res != nil) then
      res = res.gsub(/\s+/, ' ')
      res = res.gsub(/[^\-.,\/'A-zÀ-ÿ0-9\s]+/, '')
      res = res.strip
    end
    return res
  end

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

end