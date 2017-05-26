require_relative 'import_utils'
require_relative 'utils'
require_relative 'normalizer'
require 'I18n'

class Importer
  iu = ImportUtils.new
  for year in 2000..2000
   iu.retrieve_year(year)
   Normalizer.enforcePreviousStageInfos(year)
   Normalizer.updateStageType(year)
   Normalizer.updateFirstLastStage(year)
   Normalizer.updateDistanceSpeed(year)
  end
end
