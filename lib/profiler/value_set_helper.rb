class ValueSetHelper

  def self.add_value_sets(measure) 
  	value_sets_dir = File.join('tmp','bundle','value_sets')

  	measure.value_sets = []
  	measure.value_set_oids.each do |value_set_oid|
  		measure.value_sets << HealthDataStandards::SVS::ValueSet.new(JSON.parse(File.read(File.join(value_sets_dir,"#{value_set_oid}.json"))))
  	end
  end

end