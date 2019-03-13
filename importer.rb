require_relative 'import_utils'
require_relative 'utils'
require_relative 'normalizer'

class Importer


  def process_years(years)
    iu = ImportUtils.new
    normalizer = Normalizer.new
    for year in years
      iu.retrieve_year(year)
      normalizer.enforcePreviousStageInfos(year)
      normalizer.updateStageType(year)
      normalizer.updateFirstLastStage(year)
      normalizer.updateIgLastStageResult(year)
      normalizer.updateDistanceSpeed(year)
    end
  end
end

years = [1967,1969,1970,1972,1973,1974,1975,1976,1977,1978,1979,1980,1981,1982,1983,1984,1985,1986,1987,1989,1990,1991,1992,1993,1994,1995,1996,1997,1998,1999,2001,2002,2003,2004,2006,2007,2010,2012]
years = [1982, 1983, 1978]

importer = Importer.new
# iu.retrieve_stage(2015, 9)
importer.process_years([2018])
Normalizer.updateRunnerLinkage(2018)



