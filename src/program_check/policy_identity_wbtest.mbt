///|
test "concrete Host ceilings do not enter static Unit or import identities" {
  let first_budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (first_identity, _, _, _, first) = local_construction_fixture(
    first_budget,
    second_stage=true,
    parameters=true,
    host_limit=1000,
  )
  let changed_budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (changed_identity, _, _, _, changed) = local_construction_fixture(
    changed_budget,
    second_stage=true,
    parameters=true,
    host_limit=2000,
  )
  // Both complete preparations independently admit the different policy values.
  // Their interpretation contract stays the same; neither envelope is a Unit root.
  assert_false(physical_equal(first_identity, changed_identity))
  assert_eq(
    @context.program_identity_definition_cid(first_identity),
    @context.program_identity_definition_cid(changed_identity),
  )
  assert_eq(first.length(), 2)
  assert_eq(changed.length(), 2)
  for i in 0..<2 {
    assert_eq(first[i].publication_rows.length(), 1)
    assert_eq(changed[i].publication_rows.length(), 1)
    assert_eq(first[i].publications.length(), 1)
    assert_eq(changed[i].publications.length(), 1)
    assert_eq(first[i].publications.length(), 1)
    assert_eq(changed[i].publications.length(), 1)
    let byte_claim = first[i].publications[0].bytes
    assert_eq(
      @wire.limit_subject(byte_claim),
      "unit:" + first[i].definition_cid + "#/results/out/bytes",
    )
    assert_false(
      @wire.limit_cid(byte_claim) ==
      @wire.limit_cid(first[i].publications[0].rows),
    )
    assert_false(
      @wire.limit_cid(byte_claim) ==
      @wire.limit_cid(changed[i].publications[0].bytes),
    )
    let writer = @encode.writer(10000, 1000, 100)
    @wire.emit_limit(byte_claim, writer)
    let body = @decode.admit(
      @source.parse_json(@encode.finish(writer), {
        max_input_bytes: 10000,
        max_nodes: 1000,
        max_depth: 100,
      }).unwrap(),
      {
        max_nodes: 1000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 10000,
      },
    ).unwrap()
    assert_eq(
      @decode.text(
        @decode.required(@decode.open_object(body).unwrap(), "unit").unwrap(),
      ).unwrap(),
      "bytes",
    )
    assert_eq(
      @wire.limit_subject(first[i].publications[0].rows),
      publication_result_subject(first[i].definition_cid, "out"),
    )
    assert_eq(
      @wire.limit_subject(changed[i].publications[0].rows),
      @wire.limit_subject(first[i].publications[0].rows),
    )
    assert_false(
      @wire.limit_cid(first[i].publications[0].rows) ==
      @wire.limit_cid(changed[i].publications[0].rows),
    )
    assert_eq(
      @context.publication_row_limit_maximum(first[i].publication_rows[0]),
      1000L,
    )
    assert_eq(
      @context.publication_row_limit_maximum(changed[i].publication_rows[0]),
      2000L,
    )
    assert_eq(first[i].contracts_cid, changed[i].contracts_cid)
    assert_eq(first[i].definition_cid, changed[i].definition_cid)
    assert_eq(first[i].imports, changed[i].imports)
    assert_eq(first[i].gates, changed[i].gates)
  }
  assert_eq(first[1].imports.length(), 2)
  assert_eq(first[1].gates.length(), 1)
}

///|
test "publication artifact preparation is atomic across stages" {
  let initial = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (_, _, _, _, units) = local_construction_fixture(
    initial,
    second_stage=true,
  )
  let first_budget = IdentityBudget::{
    work: 1000000,
    bytes: 100000,
    nodes: 10000,
    depth: 100,
  }
  let first = prepare_unit_publications([units[0]], first_budget)
  assert_eq(first[0].publications.length(), 1)
  let first_bytes = 100000 - first_budget.bytes
  let limited = IdentityBudget::{
    work: 1000000,
    bytes: first_bytes,
    nodes: 10000,
    depth: 100,
  }
  // The first Unit fits exactly; the second cannot construct even its Host
  // witness. No first-stage success or aggregate budget mutation escapes.
  try prepare_unit_publications(units, limited) catch {
    UnitBuildFailure::PublicationHost(_)
    | UnitBuildFailure::Encoding(_)
    | UnitBuildFailure::BudgetExceeded => ()
    e => raise e
  } noraise {
    _ => fail("second publication exceeded metadata allowance")
  }
  assert_eq(limited.bytes, first_bytes)
  assert_eq(limited.nodes, 10000)
  assert_eq(limited.work, 1000000)
}
