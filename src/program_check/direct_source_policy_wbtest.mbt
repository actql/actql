///|
fn direct_policy_fixture(
  defaulted? : Bool = false,
) -> (@sourceviews.ParameterizedRequest, SourceResponsePolicy) raise {
  let text =
    #|{"version":"actql/0.1","id":"direct","stages":[{"id":"s","inputs":{"remote":{"connector":"crm/main","resource":"r","request":{"id":1,"tenant":null}}},"steps":[],"results":{"out":{}}}],"results":{"out":{"from":{"stage":"s","result":"out"}}}}
  let program = @syntax.parse(
    if defaulted {
      text
      .replace(
        old="\"stages\":",
        new="\"params\":{\"key\":{\"type\":\"number\",\"default\":1}},\"stages\":",
      )
      .replace(old="\"id\":1", new="\"id\":{\"$param\":\"key\"}")
    } else {
      text
    },
    {
      source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      tree: {
        max_nodes: 1000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 10000,
      },
      max_stages: 10,
    },
    format=Json,
  ).unwrap()
  let source = @stages.prepare(program, {
    max_parameters: 10,
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }).unwrap()
  let (views, _) = @context.prepare_source_registrations(
    source,
    catalog_fixture(keyed_sourceview_environment()),
    {
      max_work: 1000000,
      max_nodes: 100000,
      max_depth: 100,
      max_text_bytes: 1000000,
    },
    max_inputs=10,
    max_views=100,
    max_order_keys=100,
  ).unwrap()
  let declarations = @bindings.prepare(program, {
    max_bindings: 10,
    max_work: 10000,
  }).unwrap()
  let slots = @slots.collect(source, declarations, {
    max_work: 10000,
    max_slots: 100,
  }).unwrap()
  let context = @sourceviews.prepare_requests(
    @sourceviews.pipeline_resolution(views),
    slots,
    10000,
  ).unwrap()
  let input = @sourceviews.pipeline_input_source(views, 0, 0).unwrap()
  let direct = @sourceviews.check_direct_request(context, input, {
    max_work: 10000,
    max_pairs: 100,
    values: { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
  }).unwrap()
  guard @parameters.bind(@stages.declarations(source), None, {
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    }).unwrap()
    is @parameters.Ready(values) else {
    fail("fixture bindings incomplete")
  }
  let bound = @sourceviews.prepare_request_parameters(context, values, 10000).unwrap()
  (
    @sourceviews.bind_request_parameters(bound, direct, 10000).unwrap(),
    prepare_source_response_policy(input),
  )
}

///|
test "defaulted request Parameters retain origin without implying public policy" {
  let (request, response) = direct_policy_fixture(defaulted=true)
  let writer = @encode.hashing_writer(10000, 100, 10)
  emit_source_response_policy(response, writer)
  let policy = prepare_direct_source_policy(
    request,
    response,
    "sha256:" + @encode.finish_hash(writer),
  )
  assert_true(policy.unknown_provenance)
  assert_eq(policy.classification, @environment.Unknown)
  let mut defaults = 0
  for i in 0..<@sourceviews.parameterized_request_field_count(policy.request) {
    let value = @sourceviews.parameterized_request_field_at(policy.request, i).unwrap()
    match value.value {
      @sourceviews.BoundParameter(parameter) => {
        assert_eq(parameter.name, "key")
        assert_true(parameter.origin is @parameters.Default)
        defaults += 1
      }
      _ => ()
    }
  }
  assert_eq(defaults, 1)
}

///|
test "direct policy retains owned request occurrences and rejects foreign response" {
  let (request, response) = direct_policy_fixture()
  let writer = @encode.hashing_writer(10000, 100, 10)
  emit_source_response_policy(response, writer)
  let cid = "sha256:" + @encode.finish_hash(writer)
  let policy = prepare_direct_source_policy(request, response, cid)
  assert_true(physical_equal(policy.request, request))
  assert_true(physical_equal(policy.response, response))
  assert_true(policy.unknown_provenance)
  assert_eq(policy.classification, @environment.Unknown)
  assert_eq(@sourceviews.parameterized_request_field_count(policy.request), 2)
  let (_, foreign) = direct_policy_fixture()
  try prepare_direct_source_policy(request, foreign, cid) catch {
    ForeignOwner => ()
    _ => fail("unexpected ownership diagnostic")
  } noraise {
    _ => fail("foreign response admitted")
  }
  let text = @encode.writer(10000, 8, 2)
  emit_direct_source_policy(policy, text)
  let actual = @encode.finish(text)
  let expected = "{\"classification\":\"unknown\",\"source_data_policy_cids\":[\"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf\"],\"source_response_policy_cids\":[\"" +
    cid +
    "\"],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}"
  assert_eq(actual, expected)
  let bytes = @utf8.encode(expected)
  let hash = @encode.hashing_writer(bytes.length(), 8, 2)
  emit_direct_source_policy(policy, hash)
  assert_eq(@encode.finish_hash(hash), @sha.hex(bytes))
  for
    (cap, nodes, depth) in [
      (bytes.length() - 1, 8, 2),
      (bytes.length(), 7, 2),
      (bytes.length(), 8, 1),
    ] {
    let short = @encode.hashing_writer(cap, nodes, depth)
    try emit_direct_source_policy(policy, short) catch {
      _ => ()
    } noraise {
      _ => fail("policy escaped sink budget")
    }
    try @encode.finish_hash(short) catch {
      _ => ()
    } noraise {
      _ => fail("partial policy hash escaped")
    }
  }
}
