require 'sinatra/base'

module Sinatra
  module Helpers
    module SearchHelper
      ONTOLOGIES_PARAM = "ontologies"
      ONTOLOGY_PARAM = "ontology"
      EXACT_MATCH_PARAM = "exact_match"
      INCLUDE_VIEWS_PARAM = "include_views"
      REQUIRE_DEFINITIONS_PARAM = "require_definition"
      INCLUDE_PROPERTIES_PARAM = "include_properties"
      SUBTREE_ID_PARAM = "subtree_root"  # NCBO-603
      OBSOLETE_PARAM = "obsolete"

      def get_edismax_query(text, params={})
        validate_params_solr_population()
        raise error 400, "The search query must be provided via /search?q=<query>[&page=<pagenum>&pagesize=<pagesize>]" if text.nil? || text.strip.empty?
        query = ""
        params["defType"] = "edismax"
        params["stopwords"] = "true"
        params["lowercaseOperators"] = "true"
        params["fl"] = "*,score"

        if (params[EXACT_MATCH_PARAM] == "true")
          query = "\"#{RSolr.escape(text)}\""
          params["qf"] = "prefLabelExact synonymExact"
        elsif (text[-1] == '*')
          text = text[0..-2]
          query = "\"#{RSolr.escape(text)}\""
          params["qt"] = "/suggest"
          params["qf"] = "prefLabelSuggestEdge^50 synonymSuggestEdge"
          params["pf"] = "prefLabelSuggest^50"
          params["sort"] = "score desc, prefLabelExact asc"
        else
          query = RSolr.escape(text)
          params["qf"] = "prefLabelExact^100 synonymExact^70 prefLabel^50 synonym^10 notation resource_id"
          params["qf"] << " property" if params[INCLUDE_PROPERTIES_PARAM] == "true"
        end

        subtree_ids = get_subtree_ids(params)
        acronyms = params["ontology_acronyms"] || restricted_ontologies_to_acronyms(params)
        filter_query = get_quoted_field_query_param(acronyms, "OR", "submissionAcronym")
        ids_clause = (subtree_ids.nil? || subtree_ids.empty?)? "" : get_quoted_field_query_param(subtree_ids, "OR", "resource_id")

        if (!ids_clause.empty?)
          filter_query = "#{filter_query} AND #{ids_clause}"
        end

        if params[REQUIRE_DEFINITIONS_PARAM] == "true"
          filter_query << " AND definition:[* TO *]"
        end

        if ["true", "false"].include? params[OBSOLETE_PARAM]
          filter_query << " AND obsolete:#{params[OBSOLETE_PARAM]}"
        end

        params["fq"] = filter_query
        params["q"] = query

        return query
      end

      def escape_text(text)
        text.gsub(/([:\[\]\{\}])/, '\\\\\1')
      end

      def get_subtree_ids(params)
        subtree_ids = nil

        # NCBO-603: switch to 'subtree_root', but allow 'subtree_id'.
        subtree_cls = params[SUBTREE_ID_PARAM] || params['subtree_id'] || nil
        if subtree_cls
          ontology = params[ONTOLOGY_PARAM].split(",")

          if (ontology.nil? || ontology.empty? || ontology.length > 1)
            raise error 400, "A subtree search requires a single ontology: /search?q=<query>&ontology=CNO&subtree_id=http%3a%2f%2fwww.w3.org%2f2004%2f02%2fskos%2fcore%23Concept"
          end

          ont, submission = get_ontology_and_submission
          params[:cls] = subtree_cls
          params[ONTOLOGIES_PARAM] = params[ONTOLOGY_PARAM]

          cls = get_class(submission, load_attrs={descendants: true})
          subtree_ids = cls.descendants.map {|d| d.id.to_s}
          subtree_ids.push(subtree_cls)
        end

        return subtree_ids
      end

      def get_tokenized_standard_query(text, params)
        words = text.split
        query = "("
        query << get_non_quoted_field_query_param(words, "prefLabel")
        query << " OR "
        query << get_non_quoted_field_query_param(words, "synonym")

        if params[INCLUDE_PROPERTIES_PARAM] == "true"
          query << " OR "
          query << get_non_quoted_field_query_param(words, "property")
        end
        query << ")"

        return query
      end

      def get_quoted_field_query_param(words, clause, fieldName="")
        query = fieldName.empty? ? "" : "#{fieldName}:"

        if (words.length > 1)
          query << "("
        end
        query << "\"#{words[0]}\""

        if (words.length > 1)
          words[1..-1].each do |word|
            query << " #{clause} \"#{word}\""
          end
        end

        if (words.length > 1)
          query << ")"
        end

        return query
      end

      def get_non_quoted_field_query_param(words, fieldName="")
        query = fieldName.empty? ? "" : "#{fieldName}:"
        query << words.join(" ")

        return query
      end

      def set_page_params(params={})
        pagenum, pagesize = page_params(params)
        params["page"] = pagenum
        params["pagesize"] = pagesize
        params.delete("q")
        params.delete("ontologies")

        unless params["start"]
          if pagenum <= 1
            params["start"] = 0
          else
            params["start"] = pagenum * pagesize - pagesize
          end
        end
        params["rows"] ||= pagesize
      end

      ##
      # Populate an array of classes. Returns a hash where the key is ontology_uri + class_id:
      # "http://data.bioontology.org/ontologies/ONThttp://ont.org/class1" => cls
      def populate_classes_from_search(classes, ontology_acronyms=nil)
        class_ids = []
        acronyms = (ontology_acronyms.nil?) ? [] : ontology_acronyms
        classes.each {|c| class_ids << c.id.to_s; acronyms << c.submission.ontology.acronym.to_s unless ontology_acronyms}
        acronyms.uniq!
        old_classes_hash = Hash[classes.map {|cls| [cls.submission.ontology.id.to_s + cls.id.to_s, cls]}]
        params = {"ontology_acronyms" => acronyms}

        # Use a fake phrase because we want a normal wildcard query, not the suggest.
        # Replace this with a wildcard below.
        get_edismax_query("avoid_search_mangling", params)
        params.delete("ontology_acronyms")
        params.delete("q")
        params["qf"] = "resource_id"
        params["fq"] << " AND #{get_quoted_field_query_param(class_ids, "OR", "resource_id")}"
        params["rows"] = 99999
        # Replace fake query with wildcard
        resp = LinkedData::Models::Class.search("*:*", params)

        classes_hash = {}
        resp["response"]["docs"].each do |doc|
          doc = doc.symbolize_keys
          resource_id = doc[:resource_id]
          doc.delete :resource_id
          doc[:id] = resource_id
          ontology_uri = doc[:ontologyId].first.sub(/\/submissions\/.*/, "")
          ont_uri_class_uri = ontology_uri + resource_id
          old_class = old_classes_hash[ont_uri_class_uri]
          next unless old_class
          doc[:submission] = old_class.submission
          instance = LinkedData::Models::Class.read_only(doc)
          classes_hash[ont_uri_class_uri] = instance
        end

        classes_hash
      end

    end
  end
end

helpers Sinatra::Helpers::SearchHelper