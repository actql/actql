///|
test "formal nest retains four persistent limit sites and producer input proofs" {
  let checked : Array[CheckedProgram] = []
  let _ = local_construction_fixture(
    { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
    through_check=true,
    checked_results=checked,
    second_stage=true,
    nested_depth=Some(2),
    generated_rows=Some("[{\"id\":1}]"),
    generated_proofs=[keyed_sourceview_claim()],
    generated_proof_stage=0,
    producer_expression="id",
    second_steps="[{\"nest\":{\"with\":\"again\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"into\":\"items\",\"fields\":[\"id\",\"value\"],\"max_items\":20},\"as\":\"selected\"}]",
    second_result_from="selected",
    extra_step_budget=1,
  )
  let program = checked[0]
  assert_eq(unit_nest_limit_count(program, 0), Some(0))
  assert_eq(unit_nest_limit_count(program, 1), Some(1))
  for invalid in [-1, 2, 2147483647] {
    assert_eq(unit_nest_limit_count(program, invalid), None)
    assert_true(unit_nest_limit_at(program, invalid, 0) is None)
  }
  assert_true(unit_nest_limit_at(program, 1, -1) is None)
  assert_true(unit_nest_limit_at(program, 1, 1) is None)
  let limits = unit_nest_limit_at(program, 1, 0).unwrap()
  assert_true(
    physical_equal(limits, unit_nest_limit_at(program, 1, 0).unwrap()),
  )
  assert_eq(limits.envelope.items.maximum, 1L)
  assert_eq(limits.envelope.items.guard_value, Some(20L))
  for
    (scope, expected) in [
      (ChildItems, 1L),
      (EmptyItems, 1L),
      (GroupedBytes, 1000L),
      (AttachedBytes, 1000L),
    ] {
    let claim = nest_limits_claim(limits, scope)
    assert_eq(
      @wire.limit_subject(claim),
      nest_resource_subject(limits.source, scope, 10000),
    )
    let writer = @encode.writer(100000, 10000, 100)
    @wire.emit_limit(claim, writer)
    let text = @encode.finish(writer)
    assert_true(text.contains("\"effective_max\":" + expected.to_string()))
    assert_true(text.contains("\"enforcement\":\"engine_atomic\""))
    if scope == ChildItems {
      assert_true(
        text.contains("\"author_guard_binding\":\"currently_non_binding\""),
      )
      assert_true(text.contains("$.steps[0].nest.max_items"))
    }
  }
  assert_true(
    @wire.limit_cid(nest_limits_claim(limits, GroupedBytes)) !=
    @wire.limit_cid(nest_limits_claim(limits, AttachedBytes)),
  )
  assert_true(nest_limits_input_count(limits) > 0)
  assert_true(nest_limits_parent_count(limits) > 0)
  assert_eq(
    nest_limits_parent_count(limits),
    @context.nest_parent_candidate_count(limits.envelope),
  )
  for i in 0..<nest_limits_parent_count(limits) {
    let parent = nest_limits_parent_at(limits, i).unwrap()
    assert_true(
      physical_equal(parent, nest_limits_parent_at(limits, i).unwrap()),
    )
    assert_true(
      physical_equal(
        parent.membership,
        @context.nest_parent_candidate_at(limits.envelope, i).unwrap(),
      ),
    )
    assert_eq(
      parent.input.location.unit_definition_cid,
      program.units[0].definition_cid,
    )
    assert_true(
      @wire.unit(@wire.program_proof_witness(parent.input.proof)) is Rows,
    )
  }
  assert_true(nest_limits_parent_at(limits, -1) is None)
  assert_true(
    nest_limits_parent_at(limits, nest_limits_parent_count(limits)) is None,
  )
  for i in 0..<nest_limits_input_count(limits) {
    let proof = nest_limits_input_at(limits, i).unwrap()
    assert_true(physical_equal(proof, nest_limits_input_at(limits, i).unwrap()))
    let parent = @wire.program_proof_witness(proof.input.proof)
    assert_true(@wire.unit(parent) is Rows)
    assert_true(
      @wire.unit(@wire.program_proof_witness(proof.proof)) is ArrayItems,
    )
    assert_eq(
      @wire.program_proof_input_at(proof.proof, 0),
      Some(@wire.cid(parent)),
    )
    let writer = @encode.writer(100000, 10000, 100)
    @wire.emit(parent, writer)
    assert_true(
      @encode.finish(writer).contains(
        "unit:" + program.units[0].definition_cid + "#/steps/",
      ),
    )
  }
  assert_true(nest_limits_input_at(limits, -1) is None)
  assert_true(
    nest_limits_input_at(limits, nest_limits_input_count(limits)) is None,
  )
  let empty = nest_limits_empty_proof(limits)
  assert_eq(@wire.program_proof_input_count(empty), 0)
  let subject = nest_resource_subject(limits.source, EmptyItems, 10000)
  let body = "{\"inputs\":[],\"law_id\":\"actql.bound.nest-empty-array\",\"semantic_ref\":\"" +
    subject +
    "\",\"unit\":\"array_items\",\"value\":1,\"version\":\"actql-bound-proof/0.1\"}"
  assert_eq(@wire.dependencies(@wire.program_proof_witness(empty)), [
    "sha256:" + @sha.text_hex(body).unwrap(),
  ])
  let budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let before = IdentityBudget::{ ..budget, }
  let _ = prepare_program_nest_limits(
    program.units,
    requirements(program),
    budget,
  )
  let used = (
    before.work - budget.work,
    before.bytes - budget.bytes,
    before.nodes - budget.nodes,
  )
  let exact = IdentityBudget::{
    work: used.0,
    bytes: used.1,
    nodes: used.2,
    depth: 100,
  }
  let repeated = prepare_program_nest_limits(
    program.units,
    requirements(program),
    exact,
  )
  assert_eq((exact.work, exact.bytes, exact.nodes), (0, 0, 0))
  assert_eq(
    @wire.limit_cid(nest_limits_claim(limits, ChildItems)),
    @wire.limit_cid(nest_limits_claim(repeated[1][0], ChildItems)),
  )
  for
    short in [
      IdentityBudget::{ ..before, work: used.0 - 1, },
      IdentityBudget::{ ..before, bytes: used.1 - 1, },
      IdentityBudget::{ ..before, nodes: used.2 - 1, },
    ] {
    let previous = (short.work, short.bytes, short.nodes)
    try
      prepare_program_nest_limits(program.units, requirements(program), short)
    catch {
      BudgetExceeded | Encoding(_) | PublicationHost(_) => ()
      ProofConversion(@encode.OutputLimit) => ()
      error => raise error
    } noraise {
      _ => fail("partial nest limits escaped shared preparation budget")
    }
    assert_eq((short.work, short.bytes, short.nodes), previous)
  }
}
