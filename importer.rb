require_relative 'import_utils'
require_relative 'utils'
require 'I18n'

class Importer
  iu = ImportUtils.new
  iu.retrieve_year(2013)
  iu.retrieve_year(2014)
  iu.retrieve_year(2015)
  iu.retrieve_year(2016)
end
