require 'fileutils'
require 'zip/zipfilesystem'

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
        File.open(outfile, 'w') {|f| f.write(entry.get_input_stream.read) }
      end
      puts "wrote: #{entries.size} valuesets."

      entries = zip.glob(File.join('sources','**','**','hqmf1.xml'))
      entries.each do |entry|
        measure_id = entry.name.split('/')[-2]
        outfile = File.join(outpath,'measures','hqmf',"#{measure_id}.xml")
        File.open(outfile, 'w') {|f| f.write(entry.get_input_stream.read) }
      end
      puts "wrote: #{entries.size} hqmf meausres."

      entries = zip.glob(File.join('sources','**','**','hqmf_model.json'))
      entries.each do |entry|
        measure_id = entry.name.split('/')[-2]
        outfile = File.join(outpath,'measures','json',"#{measure_id}.json")
        File.open(outfile, 'w') {|f| f.write(entry.get_input_stream.read) }
      end
      puts "wrote: #{entries.size} json meausres."

      outfile = File.join(outpath,'results', 'by_patient.json')
      File.open(outfile, 'w') {|f| f.write(zip.read(File.join('results','by_patient.json'))) }
      puts "wrote patient results."
      

    end


    puts "Bundle loaded"
  end
end
    