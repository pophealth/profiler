require 'fileutils'
require 'zip/zipfilesystem'
require 'json'
require 'hqmf-parser'
require 'hqmf2js'

namespace :profiler do
  desc 'Load a bundle into the profiler'
  task :load_bundle, [:bundle_path] do |t, args|

    SOURCE_ROOTS = {bundle: 'bundle.json', 
                    libraries: File.join('library_functions','*.js'), 
                    measures: 'measures', results: 'results', 
                    valuesets: File.join('value_sets','json','*.json'), 
                    patients: 'patients'}

    outpath = File.join('tmp','bundle')
    if File.exists?(outpath)
      FileUtils.rm_r outpath
      puts "Deleted: #{outpath}"
    end

    FileUtils.mkdir_p File.join(outpath,'patients')
    FileUtils.mkdir_p File.join(outpath,'measures','json')
    FileUtils.mkdir_p File.join(outpath,'measures','hqmf')
    FileUtils.mkdir_p File.join(outpath,'results')
    FileUtils.mkdir_p File.join(outpath,'value_sets')
    FileUtils.mkdir_p File.join(outpath,'libraries')

    bundle = File.open(args.bundle_path)

    Zip::ZipFile.open(bundle.path) do |zip|
      entries = zip.glob(File.join(SOURCE_ROOTS[:patients],'**','json','*.json'))
      entries.each do |entry|
        outfile = File.join(outpath,'patients',File.basename(entry.name))
        File.open(outfile, 'w') {|f| f.write(entry.get_input_stream.read) }
      end
      puts "wrote: #{entries.size} patients."

      entries = zip.glob(File.join(SOURCE_ROOTS[:valuesets]))
      entries.each do |entry|
        outfile = File.join(outpath,'value_sets',File.basename(entry.name))
        write_to_file(outfile, entry.get_input_stream.read)
      end
      puts "wrote: #{entries.size} valuesets."

      entries = zip.glob(File.join('sources','**','**','hqmf_model.json'))
      entries.each do |entry|
        measure_id = entry.name.split('/')[-2]
        outfile = File.join(outpath,'measures','json',"#{measure_id}.json")
        write_to_file(outfile, entry.get_input_stream.read)
      end
      puts "wrote: #{entries.size} json meausres."

      entries = zip.glob(File.join('library_functions','*.js'))
      entries.each do |entry|
        outfile = File.join(outpath,'libraries',File.basename(entry.name))
        File.open(outfile, 'w') {|f| f.write(entry.get_input_stream.read) }
      end
      puts "wrote: #{entries.size} javascript libraries."

      outfile = File.join(outpath,'results', 'by_patient.json')
      File.open(outfile, 'w') {|f| f.write(zip.read(File.join('results','by_patient.json'))) }
      puts "wrote patient results."
      

    end


    puts "Bundle loaded"
  end

  def write_to_file(outfile, contents)
    begin
      File.open(outfile, 'w') {|f| f.write(contents) }
    rescue
      File.open(outfile, 'w') {|f| f.write(JSON.parse(contents).to_json) }
    end
  end

  desc 'Export definitions for all measures'
  task :export_measure_js, [] do |t, args|

    outpath = File.join(".", "tmp", "measures", "js")
    FileUtils.rm_r outpath if File.exists?(outpath)
    FileUtils.mkdir_p outpath

    measures_dir = File.join('tmp','bundle','measures','json')
    measure_files = Dir.glob(File.join(measures_dir,'**','*.json'))

    sub_ids = ('a'..'zz').to_a
    index = 0;
    measure_files.each do |measure_file| 
      measure_json = JSON.parse(File.read(measure_file))
      hqmf_measure = HQMF::Document.from_json(measure_json)
      measure = Measures::Loader.load_hqmf_json(measure_json, nil, hqmf_measure.all_code_set_oids)
      measure.as_hqmf_model = hqmf_measure

      ValueSetHelper.add_value_sets(measure)
      index += 1

      measure.populations.each_with_index do |population, population_index|
        sub_id = ''
        sub_id = sub_ids[population_index] if measure.populations.count > 1

        measure_id = "#{measure.measure_id}#{sub_id}"
        outfile = File.join(outpath, "#{measure_id}.js")

        js = Measures::Calculator.execution_logic(measure, population_index, true)

        File.open(outfile, 'w') {|f| f.write(js) }
        puts "(#{index}/#{measure_files.size}) wrote js for: #{measure_id}"

      end

    end

    puts "Exported javascript for #{measure_files.size} measures to #{outpath}"

  end

  desc 'ReWrite hqmf_utils.js'
  task :export_library_js, [] do |t, args|
    require 'rails'
    require 'hquery-patient-api'

    hqmf_utils_path = File.join('tmp','bundle','libraries','hqmf_utils.js')
    contents = HQMF2JS::Generator::JS.library_functions(APP_CONFIG['check_crosswalk'])
    File.open(hqmf_utils_path, 'w') {|f| f.write(contents) }
    puts "Exported javascript for #{hqmf_utils_path}"
  end

  desc 'Calculate Measures'
  task :calculate, [:show_measure_times] do |t, args|

    require 'v8'

    show_measure_times = true if args.show_measure_times == 'true'

    @context = V8::Context.new

    Dir.glob(File.join('tmp','bundle','libraries','*.js')).each do |js_library|
      @context.eval(File.read(js_library))
    end
    @context.eval("
      var patient = {}; 
      var ObjectId = ObjectId ||  function(id, value) { return 1; };
      var emitted = emitted || []
      var emit = emit || function(id, value) { emitted.push(value) };
      var effective_date = effective_date || 1356998340;
      var enable_logging = false;
      var enable_rationale = false;
    ")


    patients_by_measure = {'eh'=>[], 'ep'=>[]}
    Dir.glob(File.join('tmp','bundle','patients','*.json')).each do |patient|
      patient_json = File.read(patient);
      patient = Record.new(JSON.parse(patient_json))

      patients_by_measure[patient.type] <<  "patient = #{patient.to_json};"
    end

    measures_dir = File.join('tmp','bundle','measures','json')
    measure_files = Dir.glob(File.join(measures_dir,'**','*.json'))

    sub_ids = ('a'..'zz').to_a

    measures = []
    measure_files.each do |measure_file| 
      measure_json = JSON.parse(File.read(measure_file))
      measure = Measures::Loader.load_hqmf_json(measure_json, nil, nil)
      measures << measure
    end

    patient_results = {}
    results = JSON.parse(File.read(File.join('tmp','bundle','results','by_patient.json')))
    results.each do |result|
      value = result['value']
      patient_results["#{value['nqf_id']}#{value['sub_id']}_#{value['medical_record_id']}"] = value;
    end

    measures.sort! do |l,r| 
      result = r.type <=> l.type
      result = l.measure_id <=> r.measure_id if result == 0
      result
    end

    measures = measures.select {|m| ['0018','0022','0028','0034','0059','0064','0418','0419','0421'].include? m.measure_id}
#    measures = measures.select {|m| m.type == 'ep'}

    start_all = Time.now.to_i
    checked = 0
    measures.each do |measure|
      measure.populations.each_with_index do |population, population_index|
        sub_id = ''
        sub_id = sub_ids[population_index] if measure.populations.count > 1

        measure_id = "#{measure.measure_id}#{sub_id}"

        measure_js = File.read(File.join('tmp','measures','js',"#{measure_id}.js"))

        start = Time.now.to_f
        patients = patients_by_measure[measure.type]
#        (1..100).each do |i|
          @context.eval("emitted=[];")
          patients.each do |patient|
            @context.eval(patient);
            @context.eval(measure_js)
          end
#        end

        puts "#{measure.type} #{measure_id} on #{patients.size} patients, took #{Time.now.to_f - start}" if show_measure_times

        results = JSON.parse(@context.eval("JSON.stringify(emitted)"))
        @context.eval("emitted=[]; hqmfjs={}; ")
        results.each do |actual|
          checked += 1
          expected = patient_results["#{measure_id}_#{actual['medical_record_id']}"]

          HQMF::PopulationCriteria::ALL_POPULATION_CODES.each do |pop_code|
            if (expected[pop_code] != actual[pop_code])
              puts "#{measure_id}: #{actual['last']},#{actual['first']} (#{pop_code}) => expected: #{expected[pop_code]}, actual: #{actual[pop_code]}"
            end
          end
        end

      end

    end
    puts "ALL took #{Time.now.to_f - start_all}"
    puts "Checked: #{checked}"


  end


end
    