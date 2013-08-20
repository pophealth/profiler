module Measures
  class Calculator

    
    def self.quoted_string_array_or_null(arr)
      if arr
        quoted = arr.map {|e| "\"#{e}\""}
        "[#{quoted.join(',')}]"
      else
        "null"
      end
    end

    def self.measure_codes(measure)
      HQMF2JS::Generator::CodesToJson.from_value_sets(measure.value_sets)
    end

    def self.execution_logic(measure, population_index=0, load_codes=false)
      gen = HQMF2JS::Generator::JS.new(measure.as_hqmf_model)
      codes = measure_codes(measure) if load_codes
      force_sources = measure.force_sources

      if APP_CONFIG['check_crosswalk']
        crosswalk_check = "result = hqmf.SpecificsManager.maintainSpecifics(new Boolean(result.isTrue() && patient_api.validateCodeSystems()), result);"
        crosswalk_instrument = "instrumentTrueCrosswalk(hqmfjs);"
      end

      
      "
      var patient_api = new hQuery.Patient(patient);

      #{gen.to_js(population_index, codes, force_sources)}
      
      var occurrenceId = #{quoted_string_array_or_null(measure.episode_ids)};

      hqmfjs.initializeSpecifics(patient_api, hqmfjs)
      
      var population = function() {
        return executeIfAvailable(hqmfjs.#{HQMF::PopulationCriteria::IPP}, patient_api);
      }
      var denominator = function() {
        return executeIfAvailable(hqmfjs.#{HQMF::PopulationCriteria::DENOM}, patient_api);
      }
      var numerator = function() {
        return executeIfAvailable(hqmfjs.#{HQMF::PopulationCriteria::NUMER}, patient_api);
      }
      var exclusion = function() {
        return executeIfAvailable(hqmfjs.#{HQMF::PopulationCriteria::DENEX}, patient_api);
      }
      var denexcep = function() {
        return executeIfAvailable(hqmfjs.#{HQMF::PopulationCriteria::DENEXCEP}, patient_api);
      }
      var msrpopl = function() {
        return executeIfAvailable(hqmfjs.#{HQMF::PopulationCriteria::MSRPOPL}, patient_api);
      }
      var observ = function(specific_context) {
        #{Measures::Calculator.observation_function(measure, population_index)}
      }
      
      var executeIfAvailable = function(optionalFunction, patient_api) {
        if (typeof(optionalFunction)==='function') {
          result = optionalFunction(patient_api);
          #{crosswalk_check}
          return result;
        } else {
          return false;
        }
      }

      #{crosswalk_instrument}
      if (typeof Logger != 'undefined') {
        // clear out logger
        Logger.logger = [];
        Logger.rationale={};
      
        // turn on logging if it is enabled
        if (enable_logging || enable_rationale) {
          injectLogger(hqmfjs, enable_logging, enable_rationale);
        }
      }

      map(patient, population, denominator, numerator, exclusion, denexcep, msrpopl, observ, occurrenceId,#{measure.continuous_variable});
      "
    end

    def self.observation_function(measure, population_index)

      result = "
        var observFunc = hqmfjs.#{HQMF::PopulationCriteria::OBSERV}
        if (typeof(observFunc)==='function')
          return observFunc(patient_api, specific_context);
        else
          return [];"

      if (measure.custom_functions && measure.custom_functions[HQMF::PopulationCriteria::OBSERV])
        result = "return #{measure.custom_functions[HQMF::PopulationCriteria::OBSERV]}(patient_api, hqmfjs)"
      end

      result

    end

  end
end