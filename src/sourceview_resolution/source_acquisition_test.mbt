///|
// Reuse the existing authored numeric-parameter Catalog vector verbatim.
// Expectations below are independent literals, never derived from encoding.
fn source_acquisition_catalog() -> @environment.SourceRequestContracts {
  fixture_catalog(
    "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[{\"catalog_cid\":\"sha256:062ebace0f724a37a2593942fe42622382ce0a4b63bfbc0efa30032ec5081c4b\",\"commands\":[],\"connector_id\":\"crm/main\",\"connector_version\":\"fixture\",\"contracts\":[{\"body\":{\"additional_properties\":false,\"fields\":{\"id\":{\"nullable\":false,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"},\"cid\":\"sha256:19f617653f557bcc5e2d851a889101df45e60326a4192a6fe5b109ccef4d0a1e\",\"id\":\"fixture-1\",\"kind\":\"carrier_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{},\"cid\":\"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905\",\"id\":\"fixture-3\",\"kind\":\"carrier_facts\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"additional_properties\":false,\"fields\":{\"id\":{\"nullable\":false,\"type\":\"number\"},\"tenant\":{\"nullable\":true,\"type\":\"string\"}},\"nullable\":false,\"type\":\"object\"},\"cid\":\"sha256:9ed258994455d28e86f7029fa78995a4432882f346f46bbc25e5f7917ce7d1cf\",\"id\":\"fixture-0\",\"kind\":\"request_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{},\"cid\":\"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24\",\"id\":\"fixture-4\",\"kind\":\"pushdown\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"classification\":\"unknown\",\"source_ref\":\"connector://crm/main/r#v\",\"version\":\"actql-source-data-policy/0.1\"},\"cid\":\"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf\",\"id\":\"fixture-2\",\"kind\":\"data_policy\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"}],\"schema\":\"actql.connector_catalog/0.1\",\"source_views\":[{\"acquisition\":{\"authority\":\"read_metadata\",\"correlation\":{\"cardinality\":\"zero_or_many\",\"identity\":[\"id\"],\"request_fields\":[\"id\"],\"response_fields\":[\"id\"]},\"default_mode\":\"snapshot\",\"kind\":\"fetch\",\"modes\":[{\"bounded\":true,\"mode\":\"snapshot\"}],\"request_schema\":{\"cid\":\"sha256:9ed258994455d28e86f7029fa78995a4432882f346f46bbc25e5f7917ce7d1cf\",\"id\":\"fixture-0\",\"version\":\"fixture\"}},\"connector_id\":\"crm/main\",\"connector_version\":\"fixture\",\"contract_cid\":\"sha256:7caf1d5c064de1800f3e4d5dde94fb9dac6a2ec467c9fb822487ad01858810ee\",\"output\":{\"carrier\":\"relation\",\"data_policy\":{\"cid\":\"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf\",\"id\":\"fixture-2\",\"version\":\"fixture\"},\"facts\":{\"cid\":\"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905\",\"id\":\"fixture-3\",\"version\":\"fixture\"},\"schema\":{\"cid\":\"sha256:19f617653f557bcc5e2d851a889101df45e60326a4192a6fe5b109ccef4d0a1e\",\"id\":\"fixture-1\",\"version\":\"fixture\"}},\"pushdown\":{\"contract\":{\"cid\":\"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24\",\"id\":\"fixture-4\",\"version\":\"fixture\"},\"operations\":[]},\"request_processing\":{\"mutates_business_state\":false},\"resource_kind\":\"record\",\"schema\":\"actql.source_view/0.1\",\"view_id\":\"v\",\"view_version\":\"fixture\"}]}],\"contract_registry\":[{\"body\":{\"additional_properties\":false,\"fields\":{\"id\":{\"nullable\":false,\"type\":\"number\"},\"tenant\":{\"nullable\":true,\"type\":\"string\"}},\"nullable\":false,\"type\":\"object\"},\"cid\":\"sha256:9ed258994455d28e86f7029fa78995a4432882f346f46bbc25e5f7917ce7d1cf\",\"id\":\"fixture-0\",\"kind\":\"request_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{},\"cid\":\"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905\",\"id\":\"fixture-3\",\"kind\":\"carrier_facts\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{},\"cid\":\"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24\",\"id\":\"fixture-4\",\"kind\":\"pushdown\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"additional_properties\":false,\"fields\":{\"id\":{\"nullable\":false,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"},\"cid\":\"sha256:19f617653f557bcc5e2d851a889101df45e60326a4192a6fe5b109ccef4d0a1e\",\"id\":\"fixture-1\",\"kind\":\"carrier_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"classification\":\"unknown\",\"source_ref\":\"connector://crm/main/r#v\",\"version\":\"actql-source-data-policy/0.1\"},\"cid\":\"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf\",\"id\":\"fixture-2\",\"kind\":\"data_policy\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"}],\"evidence_bundle_cid\":\"sha256:487f8b3e5a6f590ce32c517a7a7b40df36ebb636d01034a5af23d50f4010f90f\",\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[{\"acquisition\":{\"authority\":\"read_metadata\",\"correlation\":{\"cardinality\":\"zero_or_many\",\"identity\":[\"id\"],\"request_fields\":[\"id\"],\"response_fields\":[\"id\"]},\"default_mode\":\"snapshot\",\"kind\":\"fetch\",\"modes\":[{\"bounded\":true,\"mode\":\"snapshot\"}],\"request_schema\":{\"cid\":\"sha256:9ed258994455d28e86f7029fa78995a4432882f346f46bbc25e5f7917ce7d1cf\",\"id\":\"fixture-0\",\"version\":\"fixture\"}},\"connector_id\":\"crm/main\",\"connector_version\":\"fixture\",\"contract_cid\":\"sha256:7caf1d5c064de1800f3e4d5dde94fb9dac6a2ec467c9fb822487ad01858810ee\",\"output\":{\"carrier\":\"relation\",\"data_policy\":{\"cid\":\"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf\",\"id\":\"fixture-2\",\"version\":\"fixture\"},\"facts\":{\"cid\":\"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905\",\"id\":\"fixture-3\",\"version\":\"fixture\"},\"schema\":{\"cid\":\"sha256:19f617653f557bcc5e2d851a889101df45e60326a4192a6fe5b109ccef4d0a1e\",\"id\":\"fixture-1\",\"version\":\"fixture\"}},\"pushdown\":{\"contract\":{\"cid\":\"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24\",\"id\":\"fixture-4\",\"version\":\"fixture\"},\"operations\":[]},\"request_processing\":{\"mutates_business_state\":false},\"resource_kind\":\"record\",\"schema\":\"actql.source_view/0.1\",\"view_id\":\"v\",\"view_version\":\"fixture\"}],\"version\":\"actql-check-environment/0.1\"}",
    "sha256:487f8b3e5a6f590ce32c517a7a7b40df36ebb636d01034a5af23d50f4010f90f",
  )
}

///|
fn source_acquisition_fixture(
  steps : String,
  result : String,
  supplied : String,
  branch? : Bool = false,
  reverse_request_fields? : Bool = false,
) -> PipelineRequests {
  let input = if reverse_request_fields {
    "{\"connector\":\"crm/main\",\"resource\":\"r\",\"request\":{\"tenant\":null,\"id\":{\"$param\":\"p\"}}}"
  } else {
    "{\"connector\":\"crm/main\",\"resource\":\"r\",\"request\":{\"id\":{\"$param\":\"p\"},\"tenant\":null}}"
  }
  let body = "{\"id\":\"a\",\"inputs\":{\"remote\":" +
    input +
    "},\"steps\":" +
    steps +
    ",\"results\":{\"r\":{\"from\":\"" +
    result +
    "\",\"fields\":[\"id\"]}" +
    (if branch {
      ",\"whole\":{\"from\":\"remote\",\"fields\":[\"id\"]}"
    } else {
      ""
    }) +
    "}}"
  let inputs = fixture_inputs(
    input,
    declarations="\"params\":{\"p\":{\"type\":\"number\"}},",
    stage_bodies=Some(body),
  )
  let source = @inputs.source(inputs)
  let resolved = resolve(inputs, source_acquisition_catalog(), caps()).unwrap()
  let prepared = prepare_pipeline_inputs(resolved, 1000000).unwrap()
  let stage = registered_stage(source, [
    pipeline_input_at(prepared, 0, 0).unwrap(),
  ])
  let operations = @stages.collect_operations(
    source,
    [@collection.pipeline(@stages.collection(stage))],
    {
      max_work: 1000000,
      max_slots: 1000,
      max_references: 1000,
      max_pointer_units: 1000000,
      max_direct_text_bytes: 1000000,
    },
  ).unwrap()
  let attachment = attach_pipeline_inputs(
    prepared,
    @stages.operations_stage_at(operations, 0).unwrap(),
    1000000,
  ).unwrap()
  let results = @stage_results.check(operations, {
    max_results: 100,
    max_work: 1000000,
    max_nodes: 100000,
    max_text_bytes: 1000000,
    max_depth: 100,
  }).unwrap()
  let uses = collect_pipeline_uses(attachment, results, 1000000).unwrap()
  let context = prepare_requests(resolved, request_slots(inputs), 1000000).unwrap()
  let parameters = prepare_request_parameters(
    context,
    supplied_values(inputs, supplied),
    1000000,
  ).unwrap()
  check_pipeline_requests(uses, parameters, request_caps()).unwrap()
}

///|
test "Source acquisition retains unfiltered select sort original request before computation" {
  let requests = source_acquisition_fixture(
    "[{\"select\":[\"id\"],\"as\":\"selected\"},{\"sort\":[{\"id\":\"asc\"}],\"as\":\"sorted\"}]",
    "sorted", "{\"p\":7}",
  )
  assert_true(
    derive_query_acquisition(requests, 0, 1000000) is Err(UnsupportedShape),
  )
  let acquisition = derive_source_acquisition(requests, 0, 1000000).unwrap()
  assert_true(physical_equal(source_acquisition_owner(acquisition), requests))
  assert_eq(source_acquisition_input(acquisition), @pipeline.Input(0))
  assert_eq(source_acquisition_source_index(acquisition), 0)
  guard pipeline_request_at(requests, 0) is Some(Direct(mode, request)) else {
    fail("expected original Direct request")
  }
  assert_true(physical_equal(source_acquisition_mode(acquisition), mode))
  assert_true(physical_equal(source_acquisition_request(acquisition), request))
  assert_true(
    physical_equal(
      source_acquisition_pipeline(acquisition),
      @collection.pipeline(
        @stages.collection(
          attached_pipeline_stage(
            pipeline_uses_attachment(pipeline_requests_uses(requests)),
          ),
        ),
      ),
    ),
  )
  assert_eq(
    parameterized_request_wire(
      source_acquisition_request(acquisition),
      1000,
      100,
      10,
    ).unwrap(),
    "{\"id\":7,\"tenant\":null}",
  )
  let changed = source_acquisition_fixture(
    "[{\"select\":[\"id\"],\"as\":\"selected\"}]", "selected", "{\"p\":8}",
  )
  let changed_acquisition = derive_source_acquisition(changed, 0, 1000000).unwrap()
  assert_false(
    physical_equal(source_acquisition_owner(changed_acquisition), requests),
  )
  assert_false(
    physical_equal(source_acquisition_request(changed_acquisition), request),
  )
  assert_eq(
    parameterized_request_wire(
      source_acquisition_request(changed_acquisition),
      1000,
      100,
      10,
    ).unwrap(),
    "{\"id\":8,\"tenant\":null}",
  )
}

///|
test "Source acquisition captures direct and shared input without changing Query exclusivity" {
  let direct = source_acquisition_fixture("[]", "remote", "{\"p\":7}")
  assert_eq(
    source_acquisition_input(
      derive_source_acquisition(direct, 0, 1000000).unwrap(),
    ),
    @pipeline.Input(0),
  )
  assert_true(
    derive_query_acquisition(direct, 0, 1000000) is Err(UnsupportedShape),
  )
  let shared = source_acquisition_fixture(
    "[{\"filter\":{\"literal\":true},\"as\":\"filtered\"},{\"select\":[\"id\"],\"as\":\"selected\"}]",
    "selected",
    "{\"p\":7}",
    branch=true,
  )
  assert_eq(pipeline_use_count(pipeline_requests_uses(shared), 0), Some(2))
  assert_true(
    derive_query_acquisition(shared, 0, 1000000) is Err(UnsupportedShape),
  )
  assert_true(derive_source_acquisition(shared, 0, 1000000) is Ok(_))
  let query = source_acquisition_fixture(
    "[{\"filter\":{\"literal\":true},\"as\":\"filtered\"},{\"select\":[\"id\"],\"as\":\"selected\"}]",
    "selected", "{\"p\":7}",
  )
  assert_true(derive_query_acquisition(query, 0, 1000000) is Ok(_))
  assert_eq(
    source_acquisition_input(
      derive_source_acquisition(query, 0, 1000000).unwrap(),
    ),
    @pipeline.Input(0),
  )
}

///|
test "Source acquisition charges exact original input lookup and refuses missing source" {
  let requests = source_acquisition_fixture("[]", "remote", "{\"p\":7}")
  let acquisition = derive_source_acquisition(requests, 0, 1000000).unwrap()
  let work = source_acquisition_work(acquisition)
  assert_eq(work, 14)
  assert_true(derive_source_acquisition(requests, 0, work) is Ok(_))
  assert_true(
    derive_source_acquisition(requests, 0, work - 1) is Err(WorkLimit),
  )
  assert_true(derive_source_acquisition(requests, 0, 0) is Err(WorkLimit))
  assert_true(derive_source_acquisition(requests, 0, -1) is Err(InvalidLimits))
  assert_true(
    derive_source_acquisition(requests, -1, work) is Err(UnsupportedMode),
  )
  assert_true(
    derive_source_acquisition(requests, 1, work) is Err(UnsupportedMode),
  )
}

///|
test "Source original Request document retains its exact writer bytes without reparsing" {
  let requests = source_acquisition_fixture(
    "[{\"select\":[\"id\"],\"as\":\"selected\"}]", "selected", "{\"p\":7}",
  )
  let source = derive_source_acquisition(requests, 0, 1000000).unwrap()
  let request = source_acquisition_request(source)
  let expected = "{\"id\":7,\"tenant\":null}"
  let document = parameterized_request_document(
    request,
    expected.length(),
    100,
    20,
  ).unwrap()
  assert_eq(@encode.document_text(document), expected)
  assert_eq(@encode.document_bytes(document), expected.length())
  assert_true(
    parameterized_request_document(request, expected.length() - 1, 100, 20)
    is Err(Encoding(_)),
  )
  assert_eq(
    parameterized_request_wire(request, 1000, 100, 20).unwrap(),
    expected,
  )
}

///|
test "Source publication Request preimage uses canonical fields without changing original binding indices" {
  let requests = source_acquisition_fixture(
    "[]",
    "remote",
    "{\"p\":7}",
    reverse_request_fields=true,
  )
  let source = derive_source_acquisition(requests, 0, 1000000).unwrap()
  let request = source_acquisition_request(source)
  let first = parameterized_request_field_at(request, 0).unwrap()
  let second = parameterized_request_field_at(request, 1).unwrap()
  let expected = "{\"id\":7,\"tenant\":null}"
  let document = parameterized_request_canonical_document(
    request, 1000, 100, 20,
  ).unwrap()
  assert_eq(@encode.document_text(document), expected)
  assert_eq(
    parameterized_request_wire(request, 1000, 100, 20).unwrap(),
    "{\"tenant\":null,\"id\":7}",
  )
  assert_true(
    @publication.admit_hashed_effect_dependency_body(
      "request_values",
      "sha256:ecbbecd3d50bdf5a5cfe70acaa9668975f6f44900a081d94633e4e11968f4b1e",
      @encode.document_text(document),
      1000,
      100,
      20,
    )
    is Ok(_),
  )

  assert_true(
    physical_equal(first, parameterized_request_field_at(request, 0).unwrap()),
  )
  assert_true(
    physical_equal(second, parameterized_request_field_at(request, 1).unwrap()),
  )
}
