class NationalityUtils

  @@nationality_mapping = {
      "fra" => "France",
      "all" => "Germany",
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
      "por" => "Portugal",
      "irl" => "Ireland",
      "ukr" => "Ukraine",
      "kaz" => "Kazakhstan",
      "est" => "Estonia",
      "hol" => "Netherlands",
      "svq" => "Slovakia",
      "lux" => "Luxembourg",
      "nzl" => "New Zealand",
      "lit" => "Lithuania",
      "cro" => "Croatia",
      "arg" => "Argentina",
      "col" => "Columbia",
      "sui" => "Swiss",
      "can" => "Canada",
      "blr" => "Belarus",
      "bre" => "Brasil",
      "ouz" => "Uzbebistan",
      "tch" => "Czech Republic",
      "bel" => "Belgium"
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