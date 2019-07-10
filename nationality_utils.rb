class NationalityUtils

  @@nationality_mapping = {
      "fra" => "France",
      "all" => "Germany",
      "ger" => "Germany",
      "esp" => "Spain",
      "gbr" => "Great Britain",
      "ita" => "Italy",
      "aut" => "Austria",
      "aus" => "Australia",
      "usa" => "United States",
      "rus" => "Russia",
      "nor" => "Norway",
      "let" => "Latvia",
      "slo" => "Slovenia",
      "pol" => "Poland",
      "dan" => "Denmark",
      "den" => "Denmark",
      "por" => "Portugal",
      "irl" => "Ireland",
      "ukr" => "Ukraine",
      "kaz" => "Kazakhstan",
      "est" => "Estonia",
      "hol" => "Netherlands",
      "ned" => "Netherlands",
      "svq" => "Slovakia",
      "svk" => "Slovakia",
      "lux" => "Luxembourg",
      "nzl" => "New Zealand",
      "lit" => "Lithuania",
      "cro" => "Croatia",
      "arg" => "Argentina",
      "col" => "Columbia",
      "sui" => "Switzerland",
      "can" => "Canada",
      "blr" => "Belarus",
      "bre" => "Brasil",
      "ouz" => "Uzbebistan",
      "tch" => "Czech Republic",
      "cze" => "Czech Republic",
      "crc" => "Costa Rica",
      "bel" => "Belgium",
      "lat" => "Latvia",
      "eri" => "Eritrea",
      "rsa" => "South Africa"
  }

  def self.normalizeNationality(nationality)
    res = nationality
    if (nationality != nil) then
      res = @@nationality_mapping[nationality.to_s.downcase]
    end
    if (res == nil) then
      res = nationality
    end
    res
  end
end