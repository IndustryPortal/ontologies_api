
require 'ncbo_resource_index'

class ResourceIndexController < ApplicationController

  # Note: methods from resource_index_helper.rb :
  #  -  get_options(params)
  #  -  get_ontology_virtual_id(ontology_acronym)

  namespace "/resource_index" do

    get '/search' do
      #ranked_elements = false
      options = get_options(params)
      classes = get_classes(params)
      if classes.empty?
        #
        # TODO: reply with syntax error message?
        #
      else
        options[:elementDetails] = true
        result = NCBO::ResourceIndex.find_by_concept(classes, options)
        # TODO: massage the result format
        #binding.pry
        #result.each do |annotations|
        #  annotations.each do |annotation|
        #    # TODO: massage annotation.concept - change ontology version ID to virtual ID and acronym
        #    # TODO: massage annotation.context ?
        #    elements = massage_elements([annotation.element])
        #    annotation.element = elements[0]
        #  end
        #end
        # TODO: Restructure the output
        # use annotation.context[:contextType] to group element annotations
        reply result
      end
    end

    get '/ranked_elements' do
      ranked_elements = true
      options = get_options(params)
      classes = get_classes(params)
      if classes.empty?
        #
        # TODO: reply with syntax error message?
        #
      else
        result = NCBO::ResourceIndex.ranked_elements(classes, options)
        result.resources.each do |r|
          r[:elements] = massage_elements(r[:elements], ranked_elements)
        end
        reply result
      end
    end

    # Return all resources
    get "/resources" do
      options = get_options(params)
      result = NCBO::ResourceIndex.resources(options)
      reply massage_resources(result)
    end

    # Return specific resources
    get "/resources/:resources" do
      options = get_options(params)
      result = NCBO::ResourceIndex.resources(options)
      reply massage_resources(result)
    end

    # Return specific elements from specific resources
    get "/resources/:resources/elements/:elements" do
      options = get_options(params)
      result = NCBO::ResourceIndex.resources(options)
      # TODO: Use the element method instead (Paul is fixing bug)
      #result = NCBO::ResourceIndex.element(params["element_id"], params["resource_id"], options)
      #binding.pry
      reply massage_resources(result)
    end

    #
    # TODO: enable POST methods?
    #

    def massage_elements(element_array, ranked=true)
      elements = []
      element_array.each do |e|
        element = {
            "id" => e[:localElementId],
            "fields" => {}
        }
        e[:text].each do |name, description|
          ontID = [e[:ontoIds][name]].compact  # Wrap Fixnum or Array into Array
          element["fields"][name] = {
                  "text" => description,
                  "associatedOntologies" => ontID
          }
          if ranked
            weight = 0.0
            e[:weights].each {|hsh| weight = hsh[:weight] if hsh[:name] == name}
            element["fields"][name]["weight"] = weight
          end
        end
        elements.push element
      end
      return elements
    end

    def massage_resources(resource_array)
      # Remove resource content
      resource_array.each do |r|
        r.delete :workflowCompletedDate
        r.delete :contexts
      end
      return resource_array
    end

  end # namespace "/resource_index"

end # class ResourceIndexController
