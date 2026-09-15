///|
fn conversion_test_budget() -> IdentityBudget {
  { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, }
}

///|
fn conversion_test_units(text : String) -> Array[BuiltUnit] raise {
  let (_, _, _, _, original) = remote_construction_fixture(
    conversion_test_budget(),
  )
  let node = @source.parse_json(text, {
    max_input_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }).unwrap()
  let cursor = @decode.admit(node, {
    max_nodes: 10000,
    max_depth: 100,
    max_string_bytes: 100000,
    max_total_string_bytes: 100000,
  }).unwrap()
  let pipeline = @pipeline.check(cursor, [], None, None, {
    max_steps: 100,
    max_work: 1000000,
    max_text_bytes: 100000,
    max_nodes: 100000,
    max_tokens: 100000,
    max_depth: 100,
  })
  let pipeline = match pipeline {
    Ok(p) => p
    Err(e) => fail(@debug.to_string(e.kind))
  }
  // Isolates conversion of admitted bounds; this is not a fabricated successful
  // CheckedProgram. Formal construction is exercised separately.
  [{ ..original[0], pipeline, }]
}

///|
test "proof conversion shares every prefix across roots without changing wire identity" {
  let n = 24
  let units = conversion_test_units(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"seed\"}" +
    ",{\"take\":1}".repeat(n) +
    "]",
  )
  let bounds = [
    @step_bounds.check(units[0].pipeline, 0, keyed_sourceview_claim()).unwrap(),
  ]
  for i in 1..<(n + 1) {
    let child = bounds[i - 1]
    let cid = @wire.cid(
      @wire.program_proof_witness(@step_bounds.checked_proof(child)),
    )
    let proof = sequence_fixture_proof(
      "actql.bound.take",
      i,
      1,
      [cid],
      "{\"input\":\"\{cid}\",\"maximum\":1,\"op\":\"clamp\"}",
    )
    bounds.push(
      @step_bounds.check_with_inputs(units[0].pipeline, i, proof, [child]).unwrap(),
    )
  }
  for reverse in [false, true] {
    let calls : Array[@step_bounds.StepBound] = []
    let budget = conversion_test_budget()
    let session = proof_conversion(
      units,
      budget,
      on_construct=Some(v => calls.push(v)),
    )
    let converted : Array[ReidentifiedStep] = []
    for i in 0..<(n + 1) {
      let index = if reverse { n - i } else { i }
      converted.push(
        reidentify_step_graph(
          units,
          bounds[index],
          budget,
          conversion=Some(session),
        ),
      )
    }
    assert_eq(calls.length(), n + 1)
    let last = converted[if reverse { 0 } else { n }]
    let again = reidentify_step_graph(
      units,
      bounds[n],
      budget,
      conversion=Some(session),
    )
    assert_true(physical_equal(last, again))
    assert_eq(calls.length(), n + 1)
    let isolated = reidentify_step_graph(
      units,
      bounds[n],
      conversion_test_budget(),
    )
    assert_eq(
      @wire.cid(@wire.program_proof_witness(last.proof)),
      @wire.cid(@wire.program_proof_witness(isolated.proof)),
    )
    assert_eq(@wire.program_proof_input_count(last.proof), 1)
  }
  // Control matching the former root-local session lifetime. This measures
  // actual constructor calls, not a timing estimate or a model-only formula.
  let cold_calls = []
  let cold_budget = conversion_test_budget()
  for bound in bounds {
    let cold = proof_conversion(
      units,
      cold_budget,
      on_construct=Some(v => cold_calls.push(v)),
    )
    ignore(
      reidentify_step_graph(units, bound, cold_budget, conversion=Some(cold)),
    )
  }
  assert_eq(cold_calls.length(), (n + 1) * (n + 2) / 2)
}

///|
test "proof conversion shares diamond dependencies and invalidates a failed attempt" {
  let units = conversion_test_units(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]} ,\"as\":\"seed\"},{\"take\":1,\"from\":\"seed\",\"as\":\"left\"},{\"take\":1,\"from\":\"seed\",\"as\":\"right\"},{\"append\":{\"with\":\"right\"},\"from\":\"left\"}]",
  )
  let seed = @step_bounds.check(units[0].pipeline, 0, keyed_sourceview_claim()).unwrap()
  let seed_cid = @wire.cid(
    @wire.program_proof_witness(@step_bounds.checked_proof(seed)),
  )
  let children = []
  for i in 1..<3 {
    let proof = sequence_fixture_proof(
      "actql.bound.take",
      i,
      1,
      [seed_cid],
      "{\"input\":\"\{seed_cid}\",\"maximum\":1,\"op\":\"clamp\"}",
    )
    children.push(
      @step_bounds.check_with_inputs(units[0].pipeline, i, proof, [seed]).unwrap(),
    )
  }
  let a = @wire.cid(
    @wire.program_proof_witness(@step_bounds.checked_proof(children[0])),
  )
  let b = @wire.cid(
    @wire.program_proof_witness(@step_bounds.checked_proof(children[1])),
  )
  let added = sequence_fixture_proof(
    "actql.bound.append",
    3,
    2,
    [a, b],
    "{\"left\":\"\{a}\",\"op\":\"add\",\"right\":\"\{b}\"}",
  )
  let root = @step_bounds.check_with_inputs(
    units[0].pipeline,
    3,
    added,
    children,
  ).unwrap()
  let calls = []
  let budget = conversion_test_budget()
  let session = proof_conversion(
    units,
    budget,
    on_construct=Some(v => calls.push(v)),
  )
  let before_root = budget.work
  let output = reidentify_step_graph(
    units,
    root,
    budget,
    conversion=Some(session),
  )
  let root_work = before_root - budget.work
  assert_eq(calls.length(), 4)
  assert_true(
    physical_equal(output.inputs[0].inputs[0], output.inputs[1].inputs[0]),
  )
  for child in children {
    ignore(
      reidentify_step_graph(units, child, budget, conversion=Some(session)),
    )
  }
  assert_eq(calls.length(), 4)
  // A fresh admission with identical body/CID is not a cache hit.
  let other = @step_bounds.check(units[0].pipeline, 0, keyed_sourceview_claim()).unwrap()
  let separately = reidentify_step_graph(
    units,
    other,
    budget,
    conversion=Some(session),
  )
  assert_eq(calls.length(), 5)
  assert_false(physical_equal(separately, output.inputs[0].inputs[0]))
  let exact_session = proof_conversion(units, budget)
  let exact = IdentityBudget::{ ..conversion_test_budget(), work: root_work, }
  ignore(
    reidentify_step_graph(units, root, exact, conversion=Some(exact_session)),
  )
  assert_eq(exact.work, 0)
  let late_session = proof_conversion(units, budget)
  let late = IdentityBudget::{
    ..conversion_test_budget(),
    work: root_work - 1,
  }
  try
    reidentify_step_graph(units, root, late, conversion=Some(late_session))
  catch {
    UnitBuildFailure::BudgetExceeded => ()
    e => raise e
  } noraise {
    _ => fail("late incomplete conversion escaped")
  }
  assert_eq(late.work, root_work - 1)
  assert_true(late_session.failed)
  assert_true(late_session.cache.get(seed_cid) is Some(_))
  let failed = proof_conversion(units, budget)
  let short = IdentityBudget::{
    work: 1,
    bytes: 100000,
    nodes: 10000,
    depth: 100,
  }
  try reidentify_step_graph(units, root, short, conversion=Some(failed)) catch {
    UnitBuildFailure::BudgetExceeded => ()
    e => raise e
  } noraise {
    _ => fail("insufficient work accepted")
  }
  assert_eq(short.work, 1)
  assert_true(failed.failed)
  try
    reidentify_step_graph(units, seed, budget, conversion=Some(failed))
  catch {
    UnitBuildFailure::UnconvertedProofInput => ()
    e => raise e
  } noraise {
    _ => fail("failed session reused")
  }
}

///|
test "proof conversion session is consumed by publication construction across roots" {
  let programs : Array[CheckedProgram] = []
  ignore(
    remote_construction_fixture(
      conversion_test_budget(),
      through_check=true,
      checked_results=programs,
    ),
  )
  let units = programs[0].units
  let calls = []
  let budget = conversion_test_budget()
  let session = proof_conversion(
    units,
    budget,
    on_construct=Some(v => calls.push(v)),
  )
  let first = prepare_publication_execution(
    units[0],
    0,
    budget,
    units=Some(units),
    conversion=Some(session),
  )
  let built = calls.length()
  assert_true(built > 0)
  let second = prepare_publication_execution(
    units[0],
    0,
    budget,
    units=Some(units),
    conversion=Some(session),
  )
  assert_eq(calls.length(), built)
  assert_eq(first.proofs.length(), second.proofs.length())
  for i in 0..<first.proofs.length() {
    assert_true(physical_equal(first.proofs[i], second.proofs[i]))
  }
  assert_eq(@wire.limit_cid(first.rows), @wire.limit_cid(second.rows))
}

///|
test "formal construction shares original row proofs between aggregate limits" {
  let programs : Array[CheckedProgram] = []
  ignore(
    local_construction_fixture(
      conversion_test_budget(),
      generated_proofs=[keyed_sourceview_claim()],
      second_stage=true,
      through_check=true,
      checked_results=programs,
      second_steps="[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"value\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1,\"value\":2}]},\"as\":\"seed\"},{\"assert_rows\":{\"unique_by\":[\"id\"]}},{\"group\":{\"by\":[\"id\"],\"aggregates\":{\"other\":{\"fn\":\"array_agg\",\"field\":\"id\",\"order_by\":[{\"id\":\"asc\"}],\"max_items\":2},\"value\":{\"fn\":\"array_agg\",\"field\":\"value\",\"order_by\":[{\"id\":\"asc\"}],\"max_items\":2}}},\"as\":\"selected\"}]",
      second_result_from="selected",
      extra_step_budget=5,
    ),
  )
  let program = programs[0]
  assert_eq(program.group_limits[1].length(), 2)
  let first = program.group_limits[1][0].proofs
  let second = program.group_limits[1][1].proofs
  assert_true(first.length() > 0)
  assert_eq(first.length(), second.length())
  for i in 0..<first.length() {
    assert_true(physical_equal(first[i].input, second[i].input))
    assert_false(
      @wire.cid(@wire.program_proof_witness(first[i].proof)) ==
      @wire.cid(@wire.program_proof_witness(second[i].proof)),
    )
  }
}
