///|
test "array item proofs preserve row bounds and reject foreign aggregate ownership" {
  let programs : Array[CheckedProgram] = []
  let _ = local_construction_fixture(
    { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
    generated_proofs=[keyed_sourceview_claim()],
    second_stage=true,
    through_check=true,
    checked_results=programs,
    second_steps="[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"value\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1,\"value\":2}]},\"as\":\"seed\"},{\"assert_rows\":{\"unique_by\":[\"id\"]}},{\"group\":{\"by\":[\"id\"],\"aggregates\":{\"value\":{\"fn\":\"array_agg\",\"field\":\"value\",\"order_by\":[{\"id\":\"asc\"}],\"max_items\":2}}},\"as\":\"selected\"}]",
    second_result_from="selected",
    extra_step_budget=5,
  )
  let program = programs[0]
  let source = unit_group_aggregate_source_at(program, 1, 2, 0).unwrap()
  let resolved = unit_group_array_limit(
    program,
    1,
    2,
    0,
    max_work=100000000,
    max_bytes=10000000,
    max_nodes=1000000,
    max_depth=100,
  )
  assert_true(group_limit_proof_count(resolved) > 0)
  let out = @encode.writer(100000, 10000, 100)
  @wire.emit_limit(group_limit_claim(resolved), out)
  let text = @encode.finish(out)
  assert_true(text.contains("\"effective_max\":1,"))
  assert_true(
    text.contains("\"author_guard_binding\":\"currently_non_binding\""),
  )
  assert_true(text.contains("\"role\":\"author_guard\""))
  assert_true(text.contains("\"role\":\"host_ceiling\""))
  assert_true(text.contains("\"role\":\"proven_upper_bound\""))
  let closure = @context.stage_requirement_operations(requirements(program))
  let mut converted_count = 0
  for i in 0..<@context.operation_closure_count(closure) {
    guard @context.operation_closure_at(closure, i)
      is Some(ExecutionCheck(GroupExecution(check))) &&
      check.rule is EnforceArrayItems(limit) else {
      continue
    }
    for candidate in 0..<@context.group_array_limit_candidate_count(limit) {
      let budget = IdentityBudget::{
        work: 100000000,
        bytes: 10000000,
        nodes: 1000000,
        depth: 100,
      }
      let before = IdentityBudget::{ ..budget, }
      let converted = group_input_proof(
        program.units,
        source,
        limit,
        candidate,
        budget,
      )
      let used = before.work - budget.work
      let exact = IdentityBudget::{ ..before, work: used, }
      let repeated = group_input_proof(
        program.units,
        source,
        limit,
        candidate,
        exact,
      )
      assert_eq(exact.work, 0)
      assert_eq(
        @wire.cid(@wire.program_proof_witness(repeated.proof)),
        @wire.cid(@wire.program_proof_witness(converted.proof)),
      )
      let public_result = unit_group_input_proof(
        program,
        1,
        2,
        0,
        candidate,
        max_work=100000000,
        max_bytes=10000000,
        max_nodes=1000000,
        max_depth=100,
      )
      assert_eq(
        @wire.cid(
          @wire.program_proof_witness(group_input_proof_claim(public_result)),
        ),
        @wire.cid(@wire.program_proof_witness(converted.proof)),
      )
      // Synthetic identity namespace for independently fixed canonical bytes;
      // the underlying pipeline, selected call and membership remain owned.
      let fixed_unit = {
        ..program.units[1],
        definition_cid: "sha256:" + "0".repeat(64),
      }
      let fixed_source = unit_group_aggregate_source(
        fixed_unit,
        fixed_unit.pipeline,
        2,
        0,
      ).unwrap()
      let fixed = group_input_proof(
        [program.units[0], fixed_unit],
        fixed_source,
        limit,
        candidate,
        budget,
      )
      assert_true(
        @wire.source(@wire.program_proof_witness(fixed.proof))
        is Program(_, cid) &&
        cid ==
        "sha256:d4f8db495b4dfc61b30455f8cef8a38320ab1afcd7ca9a7640e9eb2fff77d6a9",
      )
      let input = @wire.program_proof_witness(converted.input.proof)
      let output = @wire.program_proof_witness(converted.proof)
      assert_true(physical_equal(converted.source.call, source.call))
      assert_true(
        physical_equal(
          converted.membership,
          @context.group_array_limit_candidate_at(limit, candidate).unwrap(),
        ),
      )
      assert_true(@wire.unit(input) is Rows)
      assert_true(@wire.unit(output) is ArrayItems)
      assert_eq(@wire.value(output), @wire.value(input))
      assert_eq(@wire.value(output), 1L)
      assert_false(@wire.cid(input) == @wire.cid(output))
      assert_eq(@wire.program_proof_input_count(converted.proof), 1)
      assert_eq(
        @wire.program_proof_input_at(converted.proof, 0),
        Some(@wire.cid(input)),
      )
      assert_eq(
        converted.input.location.unit_definition_cid,
        program.units[1].definition_cid,
      )
      let claims = publication_proof_claims([converted.input], budget)
      claims.push(output)
      assert_true(
        @wire.check_arithmetic_claims(claims, {
          max_witnesses: 1000,
          max_references: 10000,
        })
        is Ok(_),
      )
      let short = IdentityBudget::{ ..before, work: used - 1, }
      try
        group_input_proof(program.units, source, limit, candidate, short)
      catch {
        BudgetExceeded => ()
        error => raise error
      } noraise {
        _ => fail("insufficient conversion budget accepted")
      }
      assert_eq(short.work, used - 1)
      assert_eq(short.bytes, before.bytes)
      assert_eq(short.nodes, before.nodes)
      assert_true(used > 0)
      let foreign = {
        ..source,
        operation: {
          ..source.operation,
          unit_definition_cid: program.units[0].definition_cid,
        },
      }
      try
        group_input_proof(program.units, foreign, limit, candidate, before)
      catch {
        ForeignOwner => ()
        error => raise error
      } noraise {
        _ => fail("foreign aggregate Unit accepted")
      }
      converted_count += 1
    }
  }
  assert_true(converted_count > 0)
}
