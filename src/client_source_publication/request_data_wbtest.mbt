///|
// Independent ASCII preimages are pinned with Python hashlib, not product output.
fn publication_request_environment() -> @program_check.CheckEnvironment {
  let body =
    #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:d9dea9f5c7de6a8b98b44908feb04bfc2144841367de6c427b4e999d5bfd8b95","commands":[],"connector_id":"crm/main","connector_version":"fixture","contracts":[{"body":{},"cid":"sha256:013b48b152bc91b471ab1d8f07eac6673a9e9c0a69fe15d684380fb39dc27bf7","id":"member-2","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:4865d8d5fedb0d1cf12f78e31bfc23fef1d487ebbaf9ea0778adc171df0bfbbc","id":"member-3","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"glob":{"nullable":true,"type":"string"},"paths":{"items":{"nullable":false,"type":"string"},"nullable":true,"type":"array"},"region":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:7d12104e6e0846b4389a80dcfec7921f718caff0b061fb8d4cb4d1202ba3155e","id":"member-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/records#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:87ee88c2e3c1afb3af1db36ec6a57cb43bb161b1e39c113cd523ac6451a6847b","id":"member-4","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:918902ad5507c91441bf69c097259f7f3498aa1046161b5eba1f433550ed7759","id":"member-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"}],"schema":"actql.connector_catalog/0.1","source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:7d12104e6e0846b4389a80dcfec7921f718caff0b061fb8d4cb4d1202ba3155e","id":"member-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:b844b32f283ef6077deb9ffd906da53679dd41f46607dbb3e0c8a48502164e75","output":{"carrier":"relation","data_policy":{"cid":"sha256:87ee88c2e3c1afb3af1db36ec6a57cb43bb161b1e39c113cd523ac6451a6847b","id":"member-4","version":"fixture"},"facts":{"cid":"sha256:013b48b152bc91b471ab1d8f07eac6673a9e9c0a69fe15d684380fb39dc27bf7","id":"member-2","version":"fixture"},"schema":{"cid":"sha256:918902ad5507c91441bf69c097259f7f3498aa1046161b5eba1f433550ed7759","id":"member-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:4865d8d5fedb0d1cf12f78e31bfc23fef1d487ebbaf9ea0778adc171df0bfbbc","id":"member-3","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}]}],"contract_registry":[{"body":{},"cid":"sha256:013b48b152bc91b471ab1d8f07eac6673a9e9c0a69fe15d684380fb39dc27bf7","id":"member-2","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:918902ad5507c91441bf69c097259f7f3498aa1046161b5eba1f433550ed7759","id":"member-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"glob":{"nullable":true,"type":"string"},"paths":{"items":{"nullable":false,"type":"string"},"nullable":true,"type":"array"},"region":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:7d12104e6e0846b4389a80dcfec7921f718caff0b061fb8d4cb4d1202ba3155e","id":"member-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:4865d8d5fedb0d1cf12f78e31bfc23fef1d487ebbaf9ea0778adc171df0bfbbc","id":"member-3","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/records#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:87ee88c2e3c1afb3af1db36ec6a57cb43bb161b1e39c113cd523ac6451a6847b","id":"member-4","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"}],"evidence_bundle_cid":"sha256:e7667ed7b3fbc887713dc45b63b96660ad8c73bb2b4808d866c831e840b835e1","host_policy_profile":{},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:7d12104e6e0846b4389a80dcfec7921f718caff0b061fb8d4cb4d1202ba3155e","id":"member-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:b844b32f283ef6077deb9ffd906da53679dd41f46607dbb3e0c8a48502164e75","output":{"carrier":"relation","data_policy":{"cid":"sha256:87ee88c2e3c1afb3af1db36ec6a57cb43bb161b1e39c113cd523ac6451a6847b","id":"member-4","version":"fixture"},"facts":{"cid":"sha256:013b48b152bc91b471ab1d8f07eac6673a9e9c0a69fe15d684380fb39dc27bf7","id":"member-2","version":"fixture"},"schema":{"cid":"sha256:918902ad5507c91441bf69c097259f7f3498aa1046161b5eba1f433550ed7759","id":"member-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:4865d8d5fedb0d1cf12f78e31bfc23fef1d487ebbaf9ea0778adc171df0bfbbc","id":"member-3","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}],"version":"actql-check-environment/0.1"}
  let wire = @check_environment.read(
    @utf8.encode(body),
    "sha256:e7667ed7b3fbc887713dc45b63b96660ad8c73bb2b4808d866c831e840b835e1",
    { max_bytes: 1048576, max_nodes: 16384, max_depth: 32, max_members: 32768, },
  ).unwrap()
  @program_check.checking_environment(
    wire,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
}

///|
fn publication_request_wire(
  environment : @program_check.CheckEnvironment,
  request : String?,
) -> String {
  prepared_publication_source_wire(environment)
  .replace(
    old="sha256:78cffc445d46c9bcd0d7d5b7223332587fab9fedbc69f85c88cb6588ff554143",
    new="sha256:b844b32f283ef6077deb9ffd906da53679dd41f46607dbb3e0c8a48502164e75",
  )
  .replace(
    old="}]}",
    new=match request {
      None => "}]}"
      Some(value) => ",\"request\":" + value + "}]}"
    },
  )
}

///|
fn publication_request_check(
  environment : @program_check.CheckEnvironment,
  request : String?,
) -> Result[@sourceviews.DirectRequest, @sourceviews.RequestIssue] {
  let prepared = prepare_published_query_environment(
    environment,
    publication_request_wire(environment, request),
  ).unwrap()
  let (lowered, catalog) = lower_prepared_published_query(
    prepared,
    environment,
    "SELECT id FROM records",
    @source_frontend.Sql,
    None,
  ).unwrap()
  let program = lowered.program.unwrap()
  let source = @stages.prepare(program, {
    max_parameters: 100,
    max_nodes: 1000,
    max_depth: 32,
    max_text_bytes: 65536,
  }).unwrap()
  let inputs = @inputs.collect(source, {
    max_work: 1000000,
    max_order_keys: 100,
  }).unwrap()
  let resolved = @sourceviews.resolve(
    inputs,
    @program_check.source_catalog_contracts(catalog),
    { max_work: 1000000, max_inputs: 1000, max_views: 1000, },
  ).unwrap()
  let bindings = @bindings.prepare(program, {
    max_bindings: 100,
    max_work: 1000000,
  }).unwrap()
  let slots = @slots.collect(source, bindings, {
    max_work: 1000000,
    max_slots: 10000,
  }).unwrap()
  let context = @sourceviews.prepare_requests(resolved, slots, 1000000).unwrap()
  @sourceviews.check_direct_request(
    context,
    @sourceviews.at(resolved, 0).unwrap(),
    {
      max_work: 1000000,
      max_pairs: 10000,
      values: { max_nodes: 10000, max_depth: 32, max_text_bytes: 65536, },
    },
  )
}

///|
test "published literal Request preserves explicit nulls and generic required values" {
  let environment = publication_request_environment()
  let request = "{\"paths\":null,\"glob\":null,\"region\":\"europe\"}"
  let checked = publication_request_check(environment, Some(request)).unwrap()
  assert_eq(@sourceviews.request_field_count(checked), 3)
  for index in 0..<3 {
    assert_true(
      @sourceviews.request_field_at(checked, index).unwrap().value
      is @sourceviews.LiteralValue(_),
    )
  }
  let prepared = prepare_published_query_environment(
    environment,
    publication_request_wire(environment, Some(request)),
  ).unwrap()
  assert_eq(
    prepared_published_request_copy_geometry(prepared, environment).unwrap(),
    (4, 21L),
  )
  for _ in 0..<2 {
    let context = prepared_published_query_context(prepared, environment, None).unwrap()
    guard context.inputs[0].source is @query_program.Captured(input) else {
      fail("published literal lost its original Captured input")
    }
    let body = source_publication_field(input, "request") catch {
      _ => fail("request missing")
    }
    let writer = @encode.writer(65536, 1000, 32)
    @stage_syntax.emit_admitted_source_value(body, writer)
    assert_eq(@encode.finish(writer), request)
  }
}

///|
test "published literal Request leaves missing unknown and type checks with Request owner" {
  let environment = publication_request_environment()
  for request in [None, Some("{\"paths\":null,\"glob\":null}")] {
    assert_true(
      publication_request_check(environment, request) is Err(issue) &&
      issue.kind is @sourceviews.MissingField(_),
    )
  }
  assert_true(
    publication_request_check(
      environment,
      Some("{\"paths\":null,\"glob\":null,\"region\":\"europe\",\"extra\":0}"),
    )
    is Err(issue) &&
    issue.kind is @sourceviews.UnknownField("extra"),
  )
  for value in ["null", "7", "[]", "{}"] {
    assert_true(
      publication_request_check(
        environment,
        Some("{\"paths\":null,\"glob\":null,\"region\":" + value + "}"),
      )
      is Err(issue) &&
      issue.kind is @sourceviews.Literal(_),
    )
  }
}

///|
test "publication Request root and authority forms are literal-only while nested data stays literal" {
  let environment = prepared_publication_source_environment()
  let wire = prepared_publication_source_wire(environment)
  for
    invalid in [
      "null", "7", "true", "[]", "\"text\"", "{\"x\":{\"$param\":\"x\"}}", "{\"x\":{\"$binding\":\"x\"}}",
    ] {
    assert_true(
      prepare_published_query_environment(
        environment,
        wire.replace(old="}]}", new=",\"request\":" + invalid + "}]}"),
      )
      is Err(_),
    )
  }
  for literal in ["{}", "{\"nested\":{\"business\":{\"$param\":\"x\"}}}"] {
    assert_true(
      prepare_published_query_environment(
        environment,
        wire.replace(old="}]}", new=",\"request\":" + literal + "}]}"),
      )
      is Ok(_),
    )
  }
  let absent = prepare_published_query_environment(environment, wire).unwrap()
  assert_eq(
    prepared_published_request_copy_geometry(absent, environment).unwrap(),
    (0, 0L),
  )
}

///|
test "publication Request retains foreign Source alias and Environment refusals" {
  let environment = publication_request_environment()
  let wire = publication_request_wire(
    environment,
    Some("{\"paths\":null,\"glob\":null,\"region\":\"europe\"}"),
  )
  for
    changed in [
      wire.replace(
        old="connector://crm/main/records#v",
        new="connector://crm/main/foreign#v",
      ),
      wire.replace(old="\"name\":\"records\"", new="\"name\":\"\""),
    ] {
    assert_true(
      prepare_published_query_environment(environment, changed) is Err(_),
    )
  }
  let prepared = prepare_published_query_environment(environment, wire).unwrap()
  assert_true(
    prepared_published_request_copy_geometry(
      prepared,
      publication_request_environment(),
    )
    is Err(ForeignEnvironment),
  )
  assert_false(
    prepared_published_query_environment_publication_matches(
      prepared,
      environment,
      wire.replace(old="europe", new="changed"),
    ),
  )
}

///|
test "literal Request input copy measures its exact original before one-short construction" {
  let request = source_publication_cursor(
    "{\"paths\":null,\"glob\":null,\"region\":\"europe\"}",
  ) catch {
    _ => fail("fixture request")
  }
  let measure = @encode.measuring_writer(1048576, 16384, 32)
  emit_source_publication_input(
    measure,
    "crm/main",
    "records",
    "v",
    Some(request),
  )
  let (bytes, _, _) = @encode.finish_measurement_usage(measure)
  let exact = source_publication_input(
    "crm/main",
    "records",
    "v",
    Some(request),
    max_bytes=bytes,
  ) catch {
    _ => fail("exact constructor extent refused")
  }
  assert_true(@decode.object_length(exact) == Some(4))
  let short = try {
    source_publication_input(
      "crm/main",
      "records",
      "v",
      Some(request),
      max_bytes=bytes - 1,
    )
    |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(short)
}
