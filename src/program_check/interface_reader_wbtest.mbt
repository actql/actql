///|
test "interface consumer reads names types and producer identities without source reconstruction" {
  let budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (_, requirements, _, _, units) = local_construction_fixture(
    budget,
    second_stage=true,
  )
  let owner = @context.stage_requirement_owner(requirements)
  assert_eq(units[0].interfaces.length(), 0)
  assert_eq(units[1].interfaces.length(), 2)
  let expected_names = ["again", "rows"]
  for i in 0..<2 {
    let value = units[1].interfaces[i]
    assert_eq(value.input_name, expected_names[i])
    assert_eq(value.producer_program_id, "local")
    assert_eq(value.producer_node_id, "first")
    assert_eq(value.producer_unit_definition_cid, units[0].definition_cid)
    assert_eq(value.result_name, "out")
    assert_eq(value.cid, units[1].imports[i])
    assert_true(
      physical_equal(@context.result_import_type_incoming(value.row), owner),
    )
    let site = @context.result_import_type_site(value.row)
    assert_eq(site.stage, 1)
    guard site.requirement is @context.Result(name, producer, _) else {
      fail("lost Result interface occurrence")
    }
    assert_eq(name, value.input_name)
    assert_true(physical_equal(producer, units[0].source))
    // Round-trip the retained semantic material, not source/lookup/re-inference.
    let writer = @encode.hashing_writer(10000, 100, 10)
    emit_result_interface(
      value.input_name,
      value.producer_program_id,
      value.producer_node_id,
      value.producer_unit_definition_cid,
      value.result_name,
      @context.result_import_type_cid(value.row),
      writer,
    )
    assert_eq("sha256:" + @encode.finish_hash(writer), value.cid)
  }
  assert_eq(
    @context.result_import_type_cid(units[1].interfaces[0].row),
    @context.result_import_type_cid(units[1].interfaces[1].row),
  )
  assert_false(
    physical_equal(
      @context.result_import_type_site(units[1].interfaces[0].row),
      @context.result_import_type_site(units[1].interfaces[1].row),
    ),
  )
}
