require 'csv'

module CyclistAliasName

  @cyclist_mapping = {}

  CSV.foreach("cyclist_alias_name.csv") do |row|
    cyclist_canonical_name = row[0]
    alternate_names = row.drop(1)
    alternate_names.each {|alias_name|
      @cyclist_mapping[alias_name] = cyclist_canonical_name
    }

  end

  puts "Now we have this hash: " + @cyclist_mapping.inspect

  def self.getCanonicalName(alias_name)
    result = @cyclist_mapping[alias_name.strip]
    if (!result) then
      result = alias_name
    else
      puts "#{alias_name} alias is a known alias of #{result}"
    end
    return result
  end

end