///|
fn values_publication_index(rows : String) -> ProgramOperationResolutionIndex {
  let queries = cells_fixture(
    "{\"type\":\"number\",\"nullable\":false}", "{\"type\":\"number\",\"default\":1}",
    rows,
  )
  values_publication_queries_index(queries)
}

///|
fn values_publication_queries_index(
  queries : ProgramOperationQueries,
) -> ProgramOperationResolutionIndex {
  let requirements = operation_orders_requirements(
    operation_scalars_orders(
      operation_frames_scalars(
        operation_fills_frames(
          operation_ranges_fills(operation_queries_ranges(queries)),
        ),
      ),
    ),
  )
  index_program_operation_resolutions(
    resolution_profiles(requirements),
    10000000,
    1000,
  ).unwrap()
}

///|
fn values_publication_limits() -> ValuesPublicationLimits {
  {
    max_work: 10000000,
    max_values: 3,
    max_payload_bytes: 10000,
    max_payload_nodes: 10000,
    max_depth: 20,
    metadata: {
      max_bytes: 4000,
      max_nodes: 1000,
      max_depth: 20,
      max_candidates: 2,
    },
  }
}

///|
// Independent wire inventory: no product emitter, reservation counter or CID
// computation supplies the expected accounting. All identities have fixed width.
fn expected_values_metadata(
  rows : Int,
  wire_bytes : Int,
  recursive : Bool,
) -> (Int, Int) {
  let cid = "sha256:" + "a".repeat(64)
  fn proof(law : String, unit : String, value : Int) -> String {
    "{\"inputs\":[],\"law_id\":\"" +
    law +
    "\",\"semantic_ref\":\"checked-step:0\",\"unit\":\"" +
    unit +
    "\",\"value\":" +
    value.to_string() +
    ",\"version\":\"actql-bound-proof/0.1\"}"
  }
  fn witness(law : String, unit : String, value : Int) -> String {
    "{\"dependencies\":[\"" +
    cid +
    "\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"" +
    law +
    "\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"" +
    cid +
    "\",\"semantic_ref\":\"checked-step:0\"},\"unit\":\"" +
    unit +
    "\",\"value\":" +
    value.to_string() +
    ",\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"" +
    cid +
    "\"}"
  }
  fn host(field : String, law : String, unit : String, value : Int) -> String {
    "{\"dependencies\":[\"" +
    cid +
    "\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"" +
    law +
    "\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"" +
    field +
    "\",\"kind\":\"host_policy\",\"policy_cid\":\"" +
    cid +
    "\"},\"unit\":\"" +
    unit +
    "\",\"value\":" +
    value.to_string() +
    ",\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"" +
    cid +
    "\"}"
  }
  fn limit(
    candidates : String,
    suffix : String,
    unit : String,
    value : Int,
  ) -> String {
    "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[" +
    candidates +
    "],\"effective_max\":" +
    value.to_string() +
    ",\"enforcement\":\"engine_atomic\",\"resolved_limit_cid\":\"" +
    cid +
    "\",\"subject_ref\":\"values:checked-step:0:" +
    suffix +
    "\",\"unit\":\"" +
    unit +
    "\",\"version\":\"actql-resolved-limit/0.1\"}"
  }
  let wire = witness("actql.bound.values-wire", "bytes", wire_bytes)
  let row = witness("actql.bound.values", "rows", rows)
  let ceiling = host(
    "max_relation_output_rows", "actql.host.relation-output", "rows", 1,
  )
  let artifacts = [
    proof("actql.bound.values-wire", "bytes", wire_bytes),
    wire,
    limit(wire, "wire", "bytes", wire_bytes),
    proof("actql.bound.values", "rows", rows),
    row,
    ceiling,
    limit(row + "," + ceiling, "rows", "rows", rows),
  ]
  if recursive {
    let ceiling = host(
      "max_nested_value_bytes", "actql.host.nested-value-bytes", "bytes", 5,
    )
    artifacts.push(ceiling)
    artifacts.push(limit(ceiling, "recursive", "bytes", 5))
  }
  let mut bytes = 0
  let mut nodes = 0
  for text in artifacts {
    bytes += text.length() // These fixtures are ASCII, including the CID padding.
    let pending = [
      @source.parse_json(text, {
        max_input_bytes: 10000,
        max_nodes: 1000,
        max_depth: 20,
      }).unwrap(),
    ]
    while pending.pop() is Some(node) {
      nodes += 1
      match node.value {
        @source.Array(items) =>
          for item in items {
            pending.push(item)
          }
        @source.Object(fields) =>
          for field in fields {
            pending.push(field.value)
          }
        _ => ()
      }
    }
  }
  (bytes, nodes)
}

///|
test "values metadata uses an independent complete artifact inventory and shared total caps" {
  for empty in [true, false] {
    let index = values_publication_index(
      if empty {
        "[]"
      } else {
        "[{\"x\":1}]"
      },
    )
    let limits = values_publication_limits()
    let resolved = resolve_program_values_resources(index, limits).unwrap()
    let (one_bytes, one_nodes) = expected_values_metadata(
      if empty {
        0
      } else {
        1
      },
      if empty {
        2
      } else {
        9
      },
      false,
    )
    // The fixture contains three separately prepared occurrences, including imports.
    let expected = (one_bytes * 3, one_nodes * 3)
    assert_eq(operation_resolution_values_metadata_usage(resolved), expected)
    let (payload_bytes, payload_nodes) = operation_resolution_values_usage(
      resolved,
    )
    let total : @wire.Limits = {
      max_bytes: expected.0 + payload_bytes,
      max_nodes: expected.1 + payload_nodes,
      max_depth: 20,
    }
    assert_true(
      resolve_program_values_resources(index, limits, total_limits=Some(total))
      is Ok(_),
    )
    for
      short in [
        { ..total, max_bytes: total.max_bytes - 1, },
        { ..total, max_nodes: total.max_nodes - 1, },
        { ..total, max_bytes: one_bytes + payload_bytes, },
      ] {
      assert_true(
        resolve_program_values_resources(
          index,
          limits,
          total_limits=Some(short),
        )
        is Err(_),
      )
      assert_eq(operation_resolution_values_metadata_usage(index), (0, 0))
    }
    // Aggregate work includes artifact nodes, independently of payload usage.
    assert_eq(
      operation_resolution_work(resolved) - operation_resolution_work(index),
      operation_resolution_count(index) + 3 + payload_nodes + expected.1,
    )
  }
}

///|
test "values resources close exact operation requirements as future execution checks" {
  let index = values_publication_index("[{\"x\":{\"$param\":\"n\"}}]")
  let before = operation_resolution_unresolved_count(index)
  let limits = values_publication_limits()
  let resolved = resolve_program_values_resources(index, limits).unwrap()
  assert_true(
    physical_equal(
      operation_resolution_requirements(index),
      operation_resolution_requirements(resolved),
    ),
  )
  assert_eq(operation_resolution_unresolved_count(resolved), before - 3)
  assert_eq(operation_resolution_unresolved_count(index), before)
  let closed = close_program_operations(resolved, 10000000, 1000).unwrap()
  let mut found = 0
  for i in 0..<operation_closure_count(closed) {
    if operation_closure_at(closed, i)
      is Some(ExecutionCheck(ValuesPublication(check))) {
      found += 1
      assert_true(
        physical_equal(
          check.site,
          operation_requirements_at(operation_resolution_requirements(index), i).unwrap(),
        ),
      )
      assert_true(
        physical_equal(check.recursive.rows.wire.bound.site, check.site),
      )
      assert_true(check.recursive_limit is None)
      assert_eq(
        operation_execution_phase(ValuesPublication(check)),
        BeforeOperationOutput,
      )
      assert_eq(
        operation_execution_failure(ValuesPublication(check)),
        RejectOperationOutput,
      )
    }
  }
  assert_eq(found, 3)
  let (payload_bytes, payload_nodes) = operation_resolution_values_usage(
    resolved,
  )
  assert_eq(payload_bytes, 27)
  assert_true(
    resolve_program_values_resources(index, {
      ..limits,
      max_payload_bytes: payload_bytes,
      max_payload_nodes: payload_nodes,
    })
    is Ok(_),
  )
  assert_true(
    resolve_program_values_resources(index, {
      ..limits,
      max_payload_nodes: payload_nodes - 1,
    })
    is Err(_),
  )
  assert_true(
    resolve_program_values_resources(index, {
      ..limits,
      max_work: operation_resolution_work(resolved),
    })
    is Ok(_),
  )
  assert_true(
    resolve_program_values_resources(index, {
      ..limits,
      max_work: operation_resolution_work(resolved) - 1,
    })
    is Err(_),
  )
  for
    short in [
      { ..limits, max_values: 2, },
      { ..limits, max_payload_bytes: 26, },
      { ..limits, max_payload_nodes: 1, },
      { ..limits, max_depth: 1, },
      { ..limits, max_values: -1, },
    ] {
    assert_true(resolve_program_values_resources(index, short) is Err(_))
    assert_eq(operation_resolution_unresolved_count(index), before)
  }
  assert_true(resolve_program_values_resources(index, limits) is Ok(_))
}

///|
test "statically excessive values rows cannot be deferred as successful resource closure" {
  let index = values_publication_index("[{\"x\":1},{\"x\":1}]")
  assert_true(
    resolve_program_values_resources(index, values_publication_limits())
    is Err(RowsExceeded(0)),
  )
  assert_true(operation_resolution_at(index, 0) is Some(Unresolved))
}

///|
test "recursive values execution checks expose selected fields and canonical scoped limits" {
  let rows = recursive_values_rows(
    "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}",
    "{\"type\":\"array\",\"items\":{\"type\":\"number\"},\"default\":[1,2]}", "[{\"x\":{\"$param\":\"n\"}}]",
    5, 1,
  )
  let index = values_publication_queries_index(
    operation_cells_queries(rows.wire.bound.cells),
  )
  let resolved = resolve_program_values_resources(
    index,
    values_publication_limits(),
  ).unwrap()
  let (bytes, nodes) = expected_values_metadata(1, 13, true)
  assert_eq(
    operation_resolution_values_metadata_usage(resolved),
    (3 * bytes, 3 * nodes),
  )
  let (payload_bytes, payload_nodes) = operation_resolution_values_usage(
    resolved,
  )
  let total : @wire.Limits = {
    max_bytes: 3 * bytes + payload_bytes,
    max_nodes: 3 * nodes + payload_nodes,
    max_depth: 20,
  }
  assert_true(
    resolve_program_values_resources(
      index,
      values_publication_limits(),
      total_limits=Some(total),
    )
    is Ok(_),
  )
  assert_true(
    resolve_program_values_resources(
      index,
      values_publication_limits(),
      total_limits=Some({ ..total, max_bytes: total.max_bytes - 1, }),
    )
    is Err(_),
  )
  assert_true(
    resolve_program_values_resources(
      index,
      values_publication_limits(),
      total_limits=Some({ ..total, max_nodes: total.max_nodes - 1, }),
    )
    is Err(_),
  )
  let closed = close_program_operations(resolved, 10000000, 1000).unwrap()
  let mut found = 0
  for i in 0..<operation_closure_count(closed) {
    if operation_closure_at(closed, i)
      is Some(ExecutionCheck(ValuesPublication(check))) {
      found += 1
      let limit = check.recursive_limit.unwrap()
      assert_eq(
        @wire.limit_cid(limit),
        "sha256:072cdb04cb8725d28e0ecd2ec618a02becb30ddcdac814284b8c0ade55f6ee00",
      )
      assert_eq(check.recursive.bytes, 5)
      assert_eq(check.recursive.type_depth, 1)
      assert_eq(values_recursive_field_at(check.recursive, 0), Some(0))
      assert_eq(values_recursive_field_at(check.recursive, -1), None)
      assert_eq(values_recursive_field_at(check.recursive, 1), None)
      assert_eq(@wire.limit_subject(limit), "values:checked-step:0:recursive")
      assert_eq(@derivation.minimum_value(@wire.limit_minimum(limit)), 5L)
      assert_eq(@wire.limit_enforcement(limit), @wire.EngineAtomic)
      assert_eq(@wire.claim_count(@wire.limit_claims(limit)), 1)
    }
  }
  assert_eq(found, 3)
}
