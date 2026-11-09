///|
test "Observed property projection counts objects while full JSON admission counts every node" {
  let limits : PropertyLimits = {
    max_bytes: 524288,
    max_nodes: 65536,
    max_depth: 32,
    max_properties: 256,
    max_name_units: 6003,
  }
  // Authored independent input: ignored scalar leaves belong to full JSON
  // parsing/admission, never another PropertyMetadata/option projection.
  let properties = Array::makei(245, index => {
    "{\"name\":\"field_" +
    index.to_string() +
    "\",\"type\":\"string\",\"fieldType\":\"text\",\"description\":\"" +
    String::make(1050, 'x') +
    "\",\"shape\":[" +
    Array::make(11, "{\"a\":0,\"b\":0,\"c\":0,\"d\":0,\"e\":0}").join(",") +
    "]}"
  })
  let body = @utf8.encode("{\"results\":[" + properties.join(",") + "]}")
  let original = prepare_property_response_source(
    body, "/properties", "companies", limits,
  )
  let data = property_response_source_geometry_data(original)
  let geometry = property_response_geometry_data(data, body.length())
    .unwrap()
    .unwrap()
  let quote = effect_metadata_observed_construction_capacity(
    body.length(),
    9,
    limits,
    data,
  ).unwrap()
  let retained = @execution.execution_capacity_retained_bytes(quote)
  let execution = @execution.execution_capacity_execution_bytes(quote)
  // This fixed pre-change component result is independent of product output.
  // Retained Catalog/body ownership is deliberately unchanged by this cut.
  assert_eq(retained, 2873924L)
  let all_node_projection = data.copy()
  all_node_projection[2] = data[11]
  let previous_bound = effect_metadata_observed_construction_capacity(
    body.length(),
    9,
    limits,
    all_node_projection,
  ).unwrap()
  assert_true(
    execution < @execution.execution_capacity_execution_bytes(previous_bound),
  )
  let parsed = property_response_observed_construction(
    geometry,
    Int::min(geometry.node_upper, limits.max_nodes),
    Int::min(geometry.depth_upper, limits.max_depth),
  ).unwrap()
  assert_true(
    execution >= @execution.preparation_representation_cost(parsed).unwrap(),
  )
  println(
    "Object projection body=\{body.length()} allNodes=\{geometry.node_upper} objects=\{geometry.objects} fields=\{geometry.fields} R=\{retained} E=\{execution} allNodeProjectionE=\{@execution.execution_capacity_execution_bytes(previous_bound)}",
  )
  // Real original Ledger: same observed 512MiB policy and remaining E, with
  // an independent representative constructor. This is not whole-Run proof.
  let ledger = @resources.create_ledger({
    planning_work: 1000000,
    attempts: 16,
    holdings: 16,
    transfer_bytes: 10000000L,
    retained_bytes: 536870912L,
    execution_bytes: 536870912L,
  }).unwrap()
  let initial = effect_metadata_construction_capacity(0, 9, limits).unwrap()
  let old_execution = @execution.execution_capacity_execution_bytes(initial)
  let token = @resources.reserve_capacity(
    ledger,
    @execution.execution_capacity_retained_bytes(initial),
    old_execution,
  ).unwrap()
  let other = @resources.reserve_capacity(
    ledger,
    0L,
    536870912L - 37357858L - old_execution,
  ).unwrap()
  @resources.grow_capacity_reservation(ledger, token, retained, execution).unwrap()
  let current = consume_property_response_source(original, "/properties", body).unwrap()
  assert_eq(current.properties.length(), 245)
  assert_eq(current.properties[244].name, "field_244")
  recheck_property_catalog(current, current, limits.max_properties).unwrap()
  retire_property_response_source(original)
  @resources.settle_capacity(ledger, token).unwrap()
  @resources.settle_capacity(ledger, other).unwrap()
  let short = @resources.create_ledger({
    planning_work: 1000000,
    attempts: 16,
    holdings: 16,
    transfer_bytes: 10000000L,
    retained_bytes: 536870912L,
    execution_bytes: execution - 1L,
  }).unwrap()
  assert_true(
    @resources.reserve_capacity(short, retained, execution)
    is Err(ExecutionLimit),
  )
}

///|
test "Observed object projection preserves malformed prefixes options and complete unknown-data validation" {
  let limits : PropertyLimits = {
    max_bytes: 8192,
    max_nodes: 1024,
    max_depth: 16,
    max_properties: 8,
    max_name_units: 128,
  }
  // ObjectView Map width is independent of its number of object wrappers.
  // Unknown scalar keys remain funded even when there are few objects.
  let narrow = property_projection_construction_extent(2, 1, object_fields=4).unwrap()
  let wide = property_projection_construction_extent(2, 1, object_fields=1000).unwrap()
  assert_true(
    @execution.preparation_representation_cost(
      initialization_collection_units(wide),
    ).unwrap() >
    @execution.preparation_representation_cost(
      initialization_collection_units(narrow),
    ).unwrap(),
  )
  for
    body in [
      b"{\"results\":[{\"name\":\"kind\",\"type\":\"enumeration\",\"fieldType\":\"select\",\"options\":[{\"value\":\"one\"},{\"value\":\"two\"}],\"modificationMetadata\":{\"readOnlyValue\":false}}]}",
      b"{\"results\":[{\"name\":\"kind\",\"type\":\"enumeration\",\"fieldType\":\"select\",\"options\":[0]}]}",
      b"{\"results\":[0]}", b"{\"results\":[],\"ignored\":{\"x\":0,\"x\":1}}", b"{\"results\":[],\"ignored\":NaN}",
    ] {
    let original = prepare_property_response_source(
      body, "/properties", "companies", limits,
    )
    let data = property_response_source_geometry_data(original)
    let quote = effect_metadata_observed_construction_capacity(
      body.length(),
      9,
      limits,
      data,
    ).unwrap()
    let full = effect_metadata_construction_capacity(body.length(), 9, limits).unwrap()
    assert_eq(
      @execution.execution_capacity_retained_bytes(quote),
      @execution.execution_capacity_retained_bytes(full),
    )
    let staged = consume_property_response_source(original, "/properties", body)
    let direct = project_properties(body, "companies", limits)
    match (staged, direct) {
      (Ok(left), Ok(right)) => {
        assert_eq(left.properties.length(), 1)
        recheck_property_catalog(left, right, 8).unwrap()
      }
      (Err(left), Err(right)) => assert_eq(left, right)
      _ => fail("Same original full validator changed its refusal")
    }
    retire_property_response_source(original)
  }
}
