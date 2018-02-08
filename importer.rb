require_relative 'import_utils'
require_relative 'utils'
require_relative 'normalizer'
require 'I18n'

class Importer
  years = [1967,1969,1970,1972,1973,1974,1975,1976,1977,1978,1979,1980,1981,1982,1983,1984,1985,1986,1987,1989,1990,1991,1992,1993,1994,1995,1996,1997,1998,1999,2001,2002,2003,2004,2006,2007,2010,2012]
  years = [1982, 1983, 1978]
  iu = ImportUtils.new
  iu.retrieve_stage(2015, 9)
  # process_years([2017])
end

def process_years(years)
  for year in years
    iu.retrieve_year(year)
    Normalizer.enforcePreviousStageInfos(year)
    Normalizer.updateStageType(year)
    Normalizer.updateFirstLastStage(year)
    Normalizer.updateIgLastStageResult(year)
    Normalizer.updateDistanceSpeed(year)
  end
end
