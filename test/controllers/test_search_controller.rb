require_relative '../test_case'

class TestSearchController < TestCase

  def self.before_suite
     count, acronyms, bro = LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
      process_submission: true,
      acronym: "BROSEARCHTEST",
      name: "BRO Search Test",
      file_path: "./test/data/ontology_files/BRO_v3.2.owl",
      ont_count: 1,
      submission_count: 1,
      ontology_type: "VALUE_SET_COLLECTION"
    })

    count, acronyms, mccl = LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
      process_submission: true,
      acronym: "MCCLSEARCHTEST",
      name: "MCCL Search Test",
      file_path: "./test/data/ontology_files/CellLine_OWL_BioPortal_v1.0.owl",
      ont_count: 1,
      submission_count: 1
    })

    @@ontologies = bro.concat(mccl)

    @@test_user = LinkedData::Models::User.new(
        username: "test_search_user",
        email: "ncbo_search_user@example.org",
        password: "test_user_password"
    )
    @@test_user.save

    # Create a test ROOT provisional class
    @@test_pc_root = LinkedData::Models::ProvisionalClass.new({
      creator: @@test_user,
      label: "Provisional Class - ROOT",
      synonym: ["Test synonym for Prov Class ROOT", "Test syn ROOT provisional class"],
      definition: ["Test definition for Prov Class ROOT"],
      ontology: @@ontologies[0]
    })
    @@test_pc_root.save

    @@cls_uri = RDF::URI.new("http://bioontology.org/ontologies/ResearchArea.owl#Area_of_Research")
    # Create a test CHILD provisional class
    @@test_pc_child = LinkedData::Models::ProvisionalClass.new({
      creator: @@test_user,
      label: "Provisional Class - CHILD",
      synonym: ["Test synonym for Prov Class CHILD", "Test syn CHILD provisional class"],
      definition: ["Test definition for Prov Class CHILD"],
      ontology: @@ontologies[0],
      subclassOf: @@cls_uri
    })
    @@test_pc_child.save
  end

  def self.after_suite
    @@test_pc_root.delete
    @@test_pc_child.delete
    LinkedData::SampleData::Ontology.delete_ontologies_and_submissions
    @@test_user.delete
    LinkedData::Models::Ontology.indexClear
    LinkedData::Models::Ontology.indexCommit
  end

  def test_search
    get '/search?q=ontology'
    assert last_response.ok?

    acronyms = @@ontologies.map {|ont|
      ont.bring_remaining
      ont.acronym
    }
    results = MultiJson.load(last_response.body)

    results["collection"].each do |doc|
      acronym = doc["links"]["ontology"].split('/')[-1]
      assert acronyms.include? (acronym)
    end
  end

  def test_search_ontology_filter
    acronym = "MCCLSEARCHTEST-0"
    get "/search?q=cell%20li*&ontologies=#{acronym}"
    assert last_response.ok?
    results = MultiJson.load(last_response.body)
    doc = results["collection"][0]
    assert_equal "cell line", doc["prefLabel"]
    assert doc["links"]["ontology"].include? acronym
    results["collection"].each do |doc|
      acr = doc["links"]["ontology"].split('/')[-1]
      assert_equal acr, acronym
    end
  end

  def test_search_other_filters
    acronym = "MCCLSEARCHTEST-0"
    get "/search?q=receptor%20antagonists&ontologies=#{acronym}&require_exact_match=true"
    assert last_response.ok?
    results = MultiJson.load(last_response.body)
    assert_equal 1, results["collection"].length

    get "search?q=data&require_definitions=true"
    assert last_response.ok?
    results = MultiJson.load(last_response.body)
    assert_equal 26, results["collection"].length

    get "search?q=data&require_definitions=false"
    assert last_response.ok?
    results = MultiJson.load(last_response.body)
    assert results["collection"].length > 26

    # testing "also_search_obsolete" flag
    acronym = "BROSEARCHTEST-0"

    get "search?q=Integration%20and%20Interoperability&ontologies=#{acronym}"
    results = MultiJson.load(last_response.body)
    assert_equal 22, results["collection"].length
    get "search?q=Integration%20and%20Interoperability&ontologies=#{acronym}&also_search_obsolete=false"
    results = MultiJson.load(last_response.body)
    assert_equal 22, results["collection"].length
    get "search?q=Integration%20and%20Interoperability&ontologies=#{acronym}&also_search_obsolete=true"
    results = MultiJson.load(last_response.body)
    assert_equal 29, results["collection"].length

    # testing "subtree_root_id" parameter
    get "search?q=training&ontologies=#{acronym}"
    results = MultiJson.load(last_response.body)
    assert_equal 3, results["collection"].length
    get "search?q=training&ontology=#{acronym}&subtree_root_id=http%3A%2F%2Fbioontology.org%2Fontologies%2FActivity.owl%23Activity"
    results = MultiJson.load(last_response.body)
    assert_equal 1, results["collection"].length

    # testing cui and semantic_types flags
    get "search?q=Funding%20Resource&ontologies=#{acronym}&include=prefLabel,synonym,definition,notation,cui,semanticType"
    results = MultiJson.load(last_response.body)
    assert_equal 35, results["collection"].length
    assert_equal "Funding Resource", results["collection"][0]["prefLabel"]
    assert_equal "T028", results["collection"][0]["semanticType"][0]
    assert_equal "X123456", results["collection"][0]["cui"][0]

    get "search?q=Funding&ontologies=#{acronym}&include=prefLabel,synonym,definition,notation,cui,semanticType&cui=X123456"
    results = MultiJson.load(last_response.body)
    assert_equal 1, results["collection"].length
    assert_equal "X123456", results["collection"][0]["cui"][0]

    get "search?q=Funding&ontologies=#{acronym}&include=prefLabel,synonym,definition,notation,cui,semanticType&semantic_types=T028"
    results = MultiJson.load(last_response.body)
    assert_equal 1, results["collection"].length
    assert_equal "T028", results["collection"][0]["semanticType"][0]
  end

  def test_subtree_search
    acronym = "BROSEARCHTEST-0"
    class_id = RDF::IRI.new "http://bioontology.org/ontologies/Activity.owl#Activity"
    pc1 = LinkedData::Models::ProvisionalClass.new({label: "Test Provisional Parent for Training", subclassOf: class_id, creator: @@test_user, ontology: @@ontologies[0]})
    pc1.save
    pc2 = LinkedData::Models::ProvisionalClass.new({label: "Test Provisional Leaf for Training", subclassOf: pc1.id, creator: @@test_user, ontology: @@ontologies[0]})
    pc2.save

    get "search?q=training&ontology=#{acronym}&subtree_root_id=#{CGI.escape(class_id.to_s)}"
    results = MultiJson.load(last_response.body)
    assert_equal 1, results["collection"].length

    get "search?q=training&ontology=#{acronym}&subtree_root_id=#{CGI.escape(class_id.to_s)}&also_search_provisional=true"
    results = MultiJson.load(last_response.body)
    assert_equal 3, results["collection"].length

    pc2.delete
    pc2 = LinkedData::Models::ProvisionalClass.find(pc2.id).first
    assert_nil pc2
    pc1.delete
    pc1 = LinkedData::Models::ProvisionalClass.find(pc1.id).first
    assert_nil pc1
  end

  def test_wildcard_search
    get "/search?q=lun*"
    assert last_response.ok?
    results = MultiJson.load(last_response.body)
    coll = results["collection"]
  end

  def test_search_provisional_class
    acronym = "BROSEARCHTEST-0"
    ontology_type = "VALUE_SET_COLLECTION"
    # roots only with provisional class test
    get "search?also_search_provisional=true&valueset_roots_only=true&ontology_types=#{ontology_type}&ontologies=#{acronym}"
    results = MultiJson.load(last_response.body)
    assert_equal 10, results["collection"].length
    provisional = results["collection"].select {|res| assert_equal ontology_type, res["ontologyType"]; res["provisional"]}
    assert_equal 1, provisional.length
    assert_equal @@test_pc_root.label, provisional[0]["prefLabel"]

    # subtree root with provisional class test
    get "search?ontology=#{acronym}&subtree_root_id=#{CGI::escape(@@cls_uri.to_s)}&also_search_provisional=true"
    results = MultiJson.load(last_response.body)
    assert_equal 20, results["collection"].length

    provisional = results["collection"].select {|res| res["provisional"]}
    assert_equal 1, provisional.length
    assert_equal @@test_pc_child.label, provisional[0]["prefLabel"]
  end

  def test_search_obo_id
    ncit_acronym = 'NCIT'
    ogms_acronym = 'OGMS'
    cno_acronym = 'CNO'

    begin
      LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
        process_submission: true,
        acronym: ncit_acronym,
        acronym_suffix: '',
        name: "NCIT Search Test",
        pref_label_property: "http://ncicb.nci.nih.gov/xml/owl/EVS/Thesaurus.owl#P108",
        synonym_property: "http://ncicb.nci.nih.gov/xml/owl/EVS/Thesaurus.owl#P90",
        definition_property: "http://ncicb.nci.nih.gov/xml/owl/EVS/Thesaurus.owl#P97",
        file_path: "./test/data/ontology_files/ncit_test.owl",
        ontology_format: 'OWL',
        ont_count: 1,
        submission_count: 1
      })
      LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
        process_submission: true,
        acronym: ogms_acronym,
        acronym_suffix: '',
        name: "OGMS Search Test",
        file_path: "./test/data/ontology_files/ogms_test.owl",
        ontology_format: 'OWL',
        ont_count: 1,
        submission_count: 1
      })
      LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
        process_submission: true,
        acronym: cno_acronym,
        acronym_suffix: '',
        name: "CNO Search Test",
        file_path: "./test/data/ontology_files/CNO_05.owl",
        ontology_format: 'OWL',
        ont_count: 1,
        submission_count: 1
      })
      get "/search?q=OGMS:0000071"
      assert last_response.ok?
      results = MultiJson.load(last_response.body)
      docs = results["collection"]
      assert_equal 3, docs.size
      assert_equal ogms_acronym, LinkedData::Utils::Triples.last_iri_fragment(docs[0]["links"]["ontology"])

      get "/search?q=CNO:0000002"
      assert last_response.ok?
      results = MultiJson.load(last_response.body)
      docs = results["collection"]
      assert_equal 3, docs.size
      assert_equal cno_acronym, LinkedData::Utils::Triples.last_iri_fragment(docs[0]["links"]["ontology"])

      get "/search?q=Thesaurus:C20480"
      assert last_response.ok?
      results = MultiJson.load(last_response.body)
      docs = results["collection"]
      assert_equal 1, docs.size
      assert_equal 'Cellular Process', docs[0]["prefLabel"]

      get "/search?q=NCIT:C20480"
      assert last_response.ok?
      results = MultiJson.load(last_response.body)
      docs = results["collection"]
      assert_equal 1, docs.size
      assert_equal 'Cellular Process', docs[0]["prefLabel"]

      get "/search?q=Leukocyte Apoptotic Process&ontologies=#{ncit_acronym}"
      assert last_response.ok?
      results = MultiJson.load(last_response.body)
      docs = results["collection"]
      assert_equal 'Leukocyte Apoptotic Process', docs[0]["prefLabel"]
    ensure
      ont = LinkedData::Models::Ontology.find(ncit_acronym).first
      ont.delete if ont
      ont = LinkedData::Models::Ontology.find(ncit_acronym).first
      assert ont.nil?

      ont = LinkedData::Models::Ontology.find(ogms_acronym).first
      ont.delete if ont
      ont = LinkedData::Models::Ontology.find(ogms_acronym).first
      assert ont.nil?

      ont = LinkedData::Models::Ontology.find(cno_acronym).first
      ont.delete if ont
      ont = LinkedData::Models::Ontology.find(cno_acronym).first
      assert ont.nil?
    end
  end

  def test_search_short_id
    vario_acronym = 'VARIO'

    begin
      LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
        process_submission: true,
        acronym: vario_acronym,
        acronym_suffix: "",
        name: "VARIO OBO Search Test",
        file_path: "./test/data/ontology_files/vario_test.obo",
        ontology_format: 'OBO',
        ont_count: 1,
        submission_count: 1
      })
      get "/search?q=VariO:0012&ontologies=#{vario_acronym}"
      assert last_response.ok?
      results = MultiJson.load(last_response.body)
      docs = results["collection"]
      assert_equal 1, docs.size

      get "/search?q=Blah:0012&ontologies=#{vario_acronym}"
      assert last_response.ok?
      results = MultiJson.load(last_response.body)
      docs = results["collection"]
      assert_equal 0, docs.size

      get "/search?q=Vario:12345&ontologies=#{vario_acronym}"
      assert last_response.ok?
      results = MultiJson.load(last_response.body)
      docs = results["collection"]
      assert_equal 0, docs.size
    ensure
      ont = LinkedData::Models::Ontology.find(vario_acronym).first
      ont.delete if ont
      ont = LinkedData::Models::Ontology.find(vario_acronym).first
      assert ont.nil?
    end
  end

end
