
namespace :qme_profiler do
  desc 'Load a bundle into the profiler'
  task :load_bundle, [:bundle_path] do |t, args|

    Rake::Task["bundle:import"] rescue begin
      Profiler::Application.load_tasks  

      MONGO_DB.drop
		  Rake::Task["bundle:import"].invoke(args.bundle_path,'true','true','ep','false')
    end

  end

  desc 'calculate the measures'
  task :calculate, [:output_diffs] do |t, args|

    output_diffs = (args.output_diffs != 'false')

    MONGO_DB['query_cache'].drop
    MONGO_DB['patient_cache'].drop
    measures = MONGO_DB['measures'].find({}).to_a
    measures = measures.select {|m| ['0018','0022','0028','0034','0059','0064','0418','0419','0421'].include? m['nqf_id']}
#    measures = measures.select {|m| m['type'] == 'ep' }
    measures.map! {|m| QME::QualityMeasure.new(m['id'], m['sub_id'])}

    report_map = {}
    measures.each do |measure|
      definition = measure.definition
      oid_dictionary = OidHelper.generate_oid_dictionary(definition)
      report_map["#{definition['id']}#{definition['sub_id']}"] = QME::QualityReport.new(definition['id'], definition['sub_id'], 'effective_date' => 1356998340, 'oid_dictionary' => oid_dictionary)
    end

    start_all = Time.now.to_i
    measures.each do |measure|
      definition = measure.definition
      report = report_map["#{definition['id']}#{definition['sub_id']}"]
      report.calculate(false)
    end
    puts "ALL took #{Time.now.to_f - start_all}"

    patient_results = {}
    results = JSON.parse(File.read(File.join('tmp','bundle','results','by_patient.json')))
    results.each do |result|
      value = result['value']
      patient_results["#{value['nqf_id']}#{value['sub_id']}_#{value['medical_record_id']}"] = value;
    end

    checked = 0
    if output_diffs
      HealthDataStandards::CQM::PatientCache.all.each do |actual| 
        checked += 1
        expected = patient_results["#{actual.value.nqf_id}#{actual.value.sub_id}_#{actual.value.medical_record_id}"]

        HQMF::PopulationCriteria::ALL_POPULATION_CODES.each do |pop_code|
          if (expected[pop_code] != actual.value[pop_code])
            puts "#{actual.value.nqf_id}#{actual.value.sub_id}: #{actual.value['last']},#{actual.value['first']} (#{pop_code}) => expected: #{expected[pop_code]}, actual: #{actual.value[pop_code]}"
          end
        end

      end
    end


  end

  desc 'rebuild javascript libraries and measures'
  task :rebuild_js, [:bundle_path] do |t, args|
    require 'rails'
    require 'hquery-patient-api'

    unless File.exist?(File.join('.','tmp','bundle'))
      puts "Extracting bundle"
      raise "bundle needs to be extracted to disk, but bundle path was not provided" unless args.bundle_path
      Rake::Task["profiler:load_bundle"].invoke(args.bundle_path)
    end

    def library_functions
      library_functions = {}
      library_functions['map_reduce_utils'] = HQMF2JS::Generator::JS.map_reduce_utils
      library_functions['hqmf_utils'] = HQMF2JS::Generator::JS.library_functions
      library_functions
    end    

    def refresh_js_libraries
      MONGO_DB['system.js'].find({}).remove_all
      library_functions.each do |name, contents|
        HealthDataStandards::Import::Bundle::Importer.save_system_js_fn(name, contents)
      end
    end

    refresh_js_libraries

    measures_dir = File.join('tmp','bundle','measures','json')
    measure_files = Dir.glob(File.join(measures_dir,'**','*.json'))

    mongo_measure_map = {}
    HealthDataStandards::CQM::Measure.all.each { |m| mongo_measure_map["#{m['hqmf_id']}#{m['sub_id']}"] = m}

    sub_ids = ('a'..'zz').to_a
    index = 0;

    measures = []
    measure_files.each do |measure_file| 
      measure_json = JSON.parse(File.read(measure_file))
      if ['0018','0022','0028','0034','0059','0064','0418','0419','0421'].include? measure_json['id']
        hqmf_measure = HQMF::Document.from_json(measure_json)
        measure = Measures::Loader.load_hqmf_json(measure_json, nil, hqmf_measure.all_code_set_oids)
      #if measure.type == 'ep'
        measure.as_hqmf_model = hqmf_measure
        ValueSetHelper.add_value_sets(measure)
        measures << measure
      #end
      end
    end

    measures.each do |measure|
      index += 1

      measure.populations.each_with_index do |population, population_index|
        sub_id = ''
        sub_id = sub_ids[population_index] if measure.populations.count > 1
        measure_id = "#{measure.measure_id}#{sub_id}"
        js = HQMF2JS::Generator::Execution.measure_js(measure, population_index)

        mongo_measure = mongo_measure_map["#{measure.id}#{sub_id}"]
        mongo_measure.map_fn = js
        mongo_measure.save!
        puts "(#{index}/#{measure_files.size}) wrote js for: #{measure_id}"

      end

    end

  end

  desc 'insert patients'
  task :insert_patients, [:patient_path, :num_copies] do |t, args|
    MONGO_DB['records'].drop
    patients_json = File.readlines(args.patient_path)
    iterations = 1;
    iterations = args.num_copies.to_i if args.num_copies
    count = 0
    (1..iterations).each do |i|
      patients_json.each do |patient_json|
        count += 1
        patient = Record.new(JSON.parse(patient_json))
        patient.save!
      end
    end
    puts "inserted #{count} patients"
  end


end
