require 'fileutils'
require 'zip/zipfilesystem'
require 'json'
require 'hqmf-parser'
require 'hqmf2js'

namespace :profiler do
  desc 'Load a bundle into the profiler'
  task :load_bundle, [:bundle_path, :rebuild_library] do |t, args|

    require 'rails'
    require 'hquery-patient-api'

    SOURCE_ROOTS = {bundle: 'bundle.json', 
                    libraries: File.join('library_functions','*.js'), 
                    measures: 'measures', results: 'results', 
                    valuesets: File.join('value_sets','json','*.json'), 
                    patients: 'patients'}

    rebuild_library = true unless args.rebuild_library == 'true'

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
        basename = File.basename(entry.name)
        outfile = File.join(outpath,'libraries',basename)

        if (basename == 'hqmf_utils.js' && rebuild_library)
          puts "writing rebuilt #{basename}"
          contents = HQMF2JS::Generator::JS.library_functions(APP_CONFIG['check_crosswalk'])
        else
          contents = entry.get_input_stream.read
        end
        
        File.open(outfile, 'w') {|f| f.write(contents) }
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
  task :export_js, [] do |t, args|

    outpath = File.join(".", "tmp", "measures", "js")
    FileUtils.rm_r outpath if File.exists?(outpath)
    FileUtils.mkdir_p outpath

    measures_dir = File.join('tmp','bundle','measures','json')
    measure_files = Dir.glob(File.join(measures_dir,'**','*.json'))

    sub_ids = ('a'..'zz').to_a
    measure_files.each do |measure_file| 
      measure_json = JSON.parse(File.read(measure_file))
      hqmf_measure = HQMF::Document.from_json(measure_json)
      measure = Measures::Loader.load_hqmf_json(measure_json, nil, hqmf_measure.all_code_set_oids)
      measure.as_hqmf_model = hqmf_measure

      ValueSetHelper.add_value_sets(measure)

      measure.populations.each_with_index do |population, population_index|
        sub_id = ''
        sub_id = sub_ids[population_index] if measure.populations.count > 1

        measure_id = "#{measure.measure_id}#{sub_id}"
        outfile = File.join(outpath, "#{measure_id}.js")

        js = Measures::Calculator.execution_logic(measure, population_index, true)

        File.open(outfile, 'w') {|f| f.write(js) }
        puts "wrote js for: #{measure_id}"

      end

    end

    puts "Exported javascript for #{measures.size} measures to #{outpath}"
  end

  desc 'Calculate Measures'
  task :calculate, [] do |t, args|

    require 'v8'

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


    patients = []
    Dir.glob(File.join('tmp','bundle','patients','*.json')).each do |patient|
      patients << "patient = #{File.read(patient)};"
    end


    start_all = Time.now.to_i
    Dir.glob(File.join('tmp','measures','js','*.js')).each do |measure_js|
      
      start = Time.now.to_f
      patients.each do |patient| 
        @context.eval(patient);
        @context.eval(File.read(measure_js))
      end

      puts "#{measure_js} took #{Time.now.to_f - start}"

      results = JSON.parse(@context.eval("JSON.stringify(emitted)"))
      binding.pry

    end
    puts "ALL took #{Time.now.to_f - start_all}"



  end


end
    