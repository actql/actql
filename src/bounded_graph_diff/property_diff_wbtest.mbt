///|
/// Authored outside the product from literal complete records. The SHA-256
/// constants were computed by Node crypto, not by graph_diff or snapshot output.
fn delta_fixture_schema() -> String {
  (
    #|{"domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","edge_definitions":[{"key_columns":[null],"key_contracts":[{"nullable":false,"type":"number"}],"labels":{"Link":[]},"name":"E","properties":{},"source_definition":"N","target_definition":"N"}],"identity_law_cid":"sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc","node_definitions":[{"key_columns":[null],"key_contracts":[{"nullable":false,"type":"number"}],"labels":{"Other":[]},"name":"M","properties":{}},{"key_columns":[null],"key_contracts":[{"nullable":false,"type":"number"}],"labels":{"Node":["score"]},"name":"N","properties":{"score":{"nullable":true,"type":"number"}}}],"value_law_cid":"sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc","version":"actql-property-graph-contract/0.1"}
  )
}

///|
fn delta_fixture_expected() -> String {
  (
    #|{"base_graph_cid":"sha256:c50c44bfeaa72f109a02dd512b22c031c9cd7d9e503fa474a7320e863300e4a8","edges":{"add":[{"dst":{"definition":"N","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[3],"key_types":[{"kind":"number"}]},"id":{"definition":"E","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[12],"key_types":[{"kind":"number"}]},"key":[12],"props":{},"src":{"definition":"N","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[1],"key_types":[{"kind":"number"}]}}],"remove":[{"dst":{"definition":"N","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[2],"key_types":[{"kind":"number"}]},"id":{"definition":"E","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[11],"key_types":[{"kind":"number"}]},"key":[11],"props":{},"src":{"definition":"N","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[1],"key_types":[{"kind":"number"}]}}],"update":[{"after":{"dst":{"definition":"N","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[3],"key_types":[{"kind":"number"}]},"id":{"definition":"E","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[10],"key_types":[{"kind":"number"}]},"key":[10],"props":{},"src":{"definition":"N","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[1],"key_types":[{"kind":"number"}]}},"before":{"dst":{"definition":"N","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[2],"key_types":[{"kind":"number"}]},"id":{"definition":"E","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[10],"key_types":[{"kind":"number"}]},"key":[10],"props":{},"src":{"definition":"N","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[1],"key_types":[{"kind":"number"}]}}}]},"graph_contract_cid":"sha256:a8248c5cd6d92997c058bdb9794747453581acd6336746b92b1779290e544443","nodes":{"add":[{"id":{"definition":"N","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[3],"key_types":[{"kind":"number"}]},"key":[3],"props":{"score":9}}],"remove":[{"id":{"definition":"N","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[2],"key_types":[{"kind":"number"}]},"key":[2],"props":{"score":null}}],"update":[{"after":{"id":{"definition":"N","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[1],"key_types":[{"kind":"number"}]},"key":[1],"props":{"score":null}},"before":{"id":{"definition":"N","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[1],"key_types":[{"kind":"number"}]},"key":[1],"props":{"score":7}}}]},"target_graph_cid":"sha256:84a3ee72261465a8864d987b0215329de2222270827c7f0436a449ec55ac1e3f","version":"actql-graph-delta/0.1"}
  )
}

///|
fn delta_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    }).unwrap(),
    {
      max_nodes: 10000,
      max_depth: 100,
      max_string_bytes: 100000,
      max_total_string_bytes: 100000,
    },
  ).unwrap()
}

///|
fn delta_fixture_contract() -> @graph_contract.CheckedContract raise {
  let checked = @graph_contract.read_cursor(
    delta_cursor(delta_fixture_schema()),
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
  ).unwrap()
  assert_eq(
    @graph_contract.cid(checked),
    "sha256:a8248c5cd6d92997c058bdb9794747453581acd6336746b92b1779290e544443",
  )
  checked
}

///|
fn delta_number(value : Double) -> @value.CheckedValue {
  @value.recheck_runtime_value(
    @value.number_value(value).unwrap(),
    @contract.primitive(NumberType, nullable=false),
    { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
  ).unwrap()
}

///|
fn delta_score(value : Double?) -> @value.CheckedValue {
  @value.recheck_runtime_value(
    match value {
      Some(value) => @value.number_value(value).unwrap()
      None => @value.null_value()
    },
    @contract.primitive(NumberType, nullable=true),
    { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
  ).unwrap()
}

///|
fn delta_fixture_storage(target : Bool) -> @storage.Storage raise {
  let graph = @graph_contract.graph(delta_fixture_contract())
  let builder = @storage.prepare(
    @carrier.graph_carrier(graph),
    DeclaredNodes,
    storage_limits(),
  ).unwrap()
  // Noncanonical input order must not become Delta action order.
  let other = if target { 3.0 } else { 2.0 }
  @storage.append_property_node(builder, 1, [delta_number(other)], [
    delta_score(if target { Some(9.0) } else { None }),
  ]).unwrap()
  @storage.append_property_node(builder, 0, [delta_number(1.0)], []).unwrap()
  @storage.append_property_node(builder, 1, [delta_number(1.0)], [
    delta_score(if target { None } else { Some(7.0) }),
  ]).unwrap()
  // Same endpoints, independent edge keys; update 10's endpoints, not its ID.
  for key in (if target { [12.0, 10.0] } else { [11.0, 10.0] }) {
    @storage.append_property_edge(
      builder,
      0,
      [delta_number(key)],
      [delta_number(1.0)],
      [delta_number(other)],
      [],
    ).unwrap()
  }
  @storage.finish(builder).unwrap()
}

///|
fn delta_fixture_limits() -> Limits {
  {
    ..diff_limits(100000),
    max_output_nodes: 10000,
    max_output_text_bytes: 100000,
    max_output_depth: 100,
  }
}

///|
fn complete_diff(preparation : Preparation, quantum : Int) -> Delta raise {
  for _ in 0..<100000 {
    match advance(preparation, quantum).unwrap() {
      Continue(..) => ()
      Complete(result, ..) => return result
      Failed(issue, ..) => {
        debug_inspect(issue)
        fail("diff failed")
      }
    }
  }
  fail("diff did not complete")
}

///|
fn delta_wire(value : @value.CheckedValue) -> String raise {
  let writer = @encode.writer(100000, 10000, 100)
  @value.emit_checked_wire_value(value, writer) catch {
    _ => fail("wire")
  }
  @encode.finish(writer) catch {
    _ => fail("finish wire")
  }
}

///|
test "property delta preserves independent parallel keys, definitions, NULL and full before records" {
  let base = delta_fixture_storage(false)
  let target = delta_fixture_storage(true)
  let preparation = prepare(
    base,
    target,
    json_contract(),
    @graph_contract.cid(delta_fixture_contract()),
    delta_fixture_limits(),
  ).unwrap()
  let result = complete_diff(preparation, 1)
  assert_eq(
    base_cid(result),
    "sha256:c50c44bfeaa72f109a02dd512b22c031c9cd7d9e503fa474a7320e863300e4a8",
  )
  assert_eq(
    target_cid(result),
    "sha256:84a3ee72261465a8864d987b0215329de2222270827c7f0436a449ec55ac1e3f",
  )
  assert_eq(delta_wire(value(result)), delta_fixture_expected())
  assert_eq(@storage.node_count(base), 3)
  assert_eq(@storage.edge_count(base), 2)
  assert_true(cleanup(preparation))
  assert_true(cleanup(preparation))
  // Delta cleanup relinquishes only its own temporary state.
  assert_eq(@storage.node_count(target), 3)
  assert_eq(@storage.edge_count(target), 2)
}

///|
test "property delta quantum and self diff retain exact snapshot identity" {
  let base = delta_fixture_storage(false)
  let target = delta_fixture_storage(true)
  let prepare_diff = (left, right) => {
    prepare(
      left,
      right,
      json_contract(),
      @graph_contract.cid(delta_fixture_contract()),
      delta_fixture_limits(),
    ).unwrap()
  }
  let incremental = prepare_diff(base, target)
  let wider = prepare_diff(base, target)
  assert_eq(
    delta_wire(value(complete_diff(incremental, 1))),
    delta_wire(value(complete_diff(wider, 64))),
  )
  assert_true(cleanup(incremental))
  assert_true(cleanup(wider))
  let same = prepare_diff(base, base)
  let result = complete_diff(same, 1)
  assert_eq(base_cid(result), target_cid(result))
  let expected = "{\"base_graph_cid\":\"sha256:c50c44bfeaa72f109a02dd512b22c031c9cd7d9e503fa474a7320e863300e4a8\",\"edges\":{\"add\":[],\"remove\":[],\"update\":[]},\"graph_contract_cid\":\"sha256:a8248c5cd6d92997c058bdb9794747453581acd6336746b92b1779290e544443\",\"nodes\":{\"add\":[],\"remove\":[],\"update\":[]},\"target_graph_cid\":\"sha256:c50c44bfeaa72f109a02dd512b22c031c9cd7d9e503fa474a7320e863300e4a8\",\"version\":\"actql-graph-delta/0.1\"}"
  assert_eq(delta_wire(value(result)), expected)
  assert_true(cleanup(same))
}

///|
test "property delta cancellation retains input storage and refuses further advance" {
  let base = delta_fixture_storage(false)
  let target = delta_fixture_storage(true)
  let preparation = prepare(
    base,
    target,
    json_contract(),
    @graph_contract.cid(delta_fixture_contract()),
    delta_fixture_limits(),
  ).unwrap()
  assert_true(advance(preparation, 1) is Ok(Continue(..)))
  assert_true(cleanup(preparation))
  assert_true(advance(preparation, 1) is Err(Terminal))
  assert_true(cleanup(preparation))
  assert_eq(@storage.node_count(base), 3)
  assert_eq(@storage.edge_count(base), 2)
  assert_eq(@storage.node_count(target), 3)
  assert_eq(@storage.edge_count(target), 2)
}

///|
test "property delta rejects incompatible identity and untyped output contracts before allocation" {
  let base = delta_fixture_storage(false)
  let target = delta_fixture_storage(true)
  let cid = @graph_contract.cid(delta_fixture_contract())
  let limits = delta_fixture_limits()
  assert_true(
    prepare(base, target, json_contract(), "sha256:" + "0".repeat(64), limits)
    is Err(InvalidGraph),
  )
  for
    contract in [
      @contract.primitive(NumberType, nullable=false),
      @contract.primitive(JsonType, nullable=true),
    ] {
    assert_true(
      prepare(base, target, contract, cid, limits) is Err(InvalidDeltaContract),
    )
  }
  assert_true(
    prepare(base, target, json_contract(), cid, {
      ..limits,
      max_workspace_slots: 0,
    })
    is Err(WorkspaceLimit),
  )
  assert_true(
    prepare(base, target, json_contract(), cid, {
      ..limits,
      max_output_nodes: 0,
    })
    is Err(OutputLimit),
  )
  assert_eq(@storage.node_count(base), 3)
  assert_eq(@storage.edge_count(base), 2)
}

///|
test "property delta output exhaustion is terminal and cleanup remains available" {
  let base = delta_fixture_storage(false)
  let target = delta_fixture_storage(true)
  let preparation = prepare(
    base,
    target,
    json_contract(),
    @graph_contract.cid(delta_fixture_contract()),
    { ..delta_fixture_limits(), max_output_nodes: 20, },
  ).unwrap()
  let mut failed = false
  for _ in 0..<100000 {
    match advance(preparation, 1).unwrap() {
      Continue(..) => ()
      Failed(OutputLimit, ..) => {
        failed = true
        break
      }
      Failed(issue, ..) => {
        debug_inspect(issue)
        fail("diff failed")
      }
      Complete(_, ..) => fail("partial delta must not publish")
    }
  }
  assert_true(failed)
  assert_true(advance(preparation, 1) is Err(Terminal))
  assert_true(cleanup(preparation))
  assert_eq(@storage.edge_count(base), 2)
  assert_eq(@storage.edge_count(target), 2)
}

///|
test "property delta retains limit refusal independently of output schema" {
  let base = delta_fixture_storage(false)
  let cid = @graph_contract.cid(delta_fixture_contract())
  let limits = delta_fixture_limits()
  for
    invalid in [
      { ..limits, max_workspace_slots: -1, },
      { ..limits, max_output_nodes: -1, },
      { ..limits, max_output_text_bytes: -1, },
      { ..limits, max_output_depth: -1, },
      { ..limits, max_identity_bytes: -1, },
      { ..limits, max_identity_nodes: -1, },
      { ..limits, max_identity_depth: -1, },
      {
        ..limits,
        value_limits: { max_nodes: -1, max_depth: 1, max_text_bytes: 1, },
      },
    ] {
    assert_true(
      prepare(base, base, json_contract(), cid, invalid) is Err(InvalidLimits),
    )
  }
}
