class OntologiesController < ApplicationController
  namespace "/ontologies" do

    ##
    # Display all ontologies
    get do
      check_last_modified_collection(Ontology)
      onts = Ontology.where.filter(Goo::Filter.new(:viewOf).unbound).include(Ontology.goo_attrs_to_load(includes_param)).to_a
      reply onts
    end

    ##
    # Display the most recent submission of the ontology
    get '/:acronym' do
      ont = Ontology.find(params["acronym"]).first
      error 404, "You must provide a valid `acronym` to retrieve an ontology" if ont.nil?
      check_last_modified(ont)
      ont.bring(*Ontology.goo_attrs_to_load(includes_param))
      reply ont
    end

    ##
    # Ontology latest submission
    get "/:acronym/latest_submission" do
      ont = Ontology.find(params["acronym"]).first
      error 404, "You must provide a valid `acronym` to retrieve an ontology" if ont.nil?
      check_last_modified(ont)
      ont.bring(:acronym, :submissions)
      latest = ont.latest_submission
      if latest
        latest.bring(*OntologySubmission.goo_attrs_to_load(includes_param))
      end
      reply latest || {}
    end

    ##
    # Create an ontology
    post do
      create_ontology
    end

    ##
    # Create an ontology with constructed URL
    put '/:acronym' do
      create_ontology
    end

    ##
    # Update an ontology
    patch '/:acronym' do
      ont = Ontology.find(params["acronym"]).include(Ontology.attributes).first
      error 422, "You must provide an existing `acronym` to patch" if ont.nil?

      populate_from_params(ont, params)
      if ont.valid?
        ont.save
      else
        error 422, ont.errors
      end

      halt 204
    end

    ##
    # Delete an ontology and all its versions
    delete '/:acronym' do
      ont = Ontology.find(params["acronym"]).first
      error 422, "You must provide an existing `acronym` to delete" if ont.nil?
      ont.delete
      halt 204
    end

    ##
    # Download the latest submission for an ontology
    get '/:acronym/download' do
      ont = Ontology.find(params["acronym"]).first
      error 422, "You must provide an existing `acronym` to download" if ont.nil?
      #submission_attributes = [:submissionId, :submissionStatus, :uploadFilePath]
      #ont = Ontology.find(params["acronym"]).include(:submissions => submission_attributes).first
      # A list of submission arrays in order of most recent submission
      #submissions = ont.submissions.sort {|a,b| a.submissionId <=> b.submissionId}.reverse
      # check submission status?
      #submissions.each do |sub|
      #  sub.submissionStatus is OK?
      #end
      #latest_submission = submissions.first
      latest_submission = ont.latest_submission  # Should resolve to latest successfully loaded submission
      latest_submission.bring(:uploadFilePath)
      #binding.pry
      #file_path = '/data/src/ncbo/ontAPI/test/data/ontology_files/BRO_v3.1.owl'
      file_path = latest_submission.uploadFilePath
      send_file file_path, :filename => File.basename(file_path)
    end

    ##
    # Properties for given ontology
    # get '/:acronym/properties' do
    #   error 500, "Not implemented"
    # end

    private

    def create_ontology
      params ||= @params
      ont = Ontology.find(params["acronym"]).first
      if ont.nil?
        ont = instance_from_params(Ontology, params)
      else
        error 409, "Ontology already exists, to add a new submission, please POST to: /ontologies/#{params["acronym"]}/submission. To modify the resource, use PATCH."
      end

      if ont.valid?
        ont.save
      else
        error 422, ont.errors
      end

      reply 201, ont
    end
  end
end
