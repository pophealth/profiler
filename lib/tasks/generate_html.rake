namespace :generator do
  desc 'generate html for the measures'
  task :generate_html, [] do |t, args|

    class RenderingContext < OpenStruct

      attr_accessor :template_dir

      def my_binding
        binding
      end
  
      def template(template_name)
        File.read(File.join(@template_dir, "#{template_name}.html.erb"))
      end

      def partial(partial_name)
        template("_#{partial_name}")
      end
  
      def render(params)
        erb = partial(params[:partial])
        locals = params[:locals] || {}
        rendering_context = RenderingContext.new(locals)
        rendering_context.template_dir = self.template_dir
        eruby = Erubis::EscapedEruby.new(erb)
        eruby.result(rendering_context.my_binding)
      end

    end

    outpath = File.join('tmp','html')
    if File.exists?(outpath)
      FileUtils.rm_r outpath
      puts "Deleted: #{outpath}"
    end

    FileUtils.mkdir_p File.join(outpath)

    patients_by_measure = {'eh'=>[], 'ep'=>[]}
    Dir.glob(File.join('tmp','bundle','patients','*.json')).each do |patient|
      patient_json = File.read(patient);
      patient = Record.new(JSON.parse(patient_json))

      patients_by_measure[patient.type] <<  "#{patient.to_json}"
    end

    File.open(File.join(outpath,'patients.js'), 'w') {|f| f.write("var patients = [#{patients_by_measure['ep'].join(",\n")}]") }
    FileUtils.cp_r(File.join('tmp','bundle','libraries'), outpath)

    FileUtils.mkdir_p File.join(outpath,'js')
    Dir.glob(File.join('tmp','measures','js',"*.js")).each do |js_file|
      measure_id = File.basename(js_file, '.*')
      contents = File.read(js_file)
      File.open(File.join(outpath,'js',"#{measure_id}.js"), 'w') {|f| f.write("function calculate_#{measure_id}(patient) {\n\n#{contents}\n\n}") }

      locals ||= {}
      locals[:measure_id] = measure_id
      rendering_context = RenderingContext.new(locals)
      rendering_context.template_dir = File.join("lib","templates","calculate")
      erb = rendering_context.template("measure")
      eruby = Erubis::EscapedEruby.new(erb)
      result = eruby.result(rendering_context.my_binding)
      outfile = File.join(outpath, "#{measure_id}.html")
      File.open(outfile, 'w') {|f| f.write(result) }

      puts "wrote: #{outfile}"
    end

  end


end