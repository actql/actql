///|
fn numeric_prefix_program(profile : Bool, mixed : Bool) -> CheckedProgram raise {
  let checked : Array[CheckedProgram] = []
  ignore(
    local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      second_stage=true,
      through_check=true,
      checked_results=checked,
      numeric_profile=if profile {
        Some(numeric_profile_fixture())
      } else {
        None
      },
      analytic_limit=if mixed { Some(1000) } else { None },
      producer_suffix=if mixed {
        ",{\"group\":{\"by\":[\"id\"],\"aggregates\":{\"value\":{\"fn\":\"sum\",\"field\":\"value\"}}}},{\"analytic\":{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"frame\":{\"start\":\"unbounded_preceding\",\"end\":\"current_row\"},\"functions\":{\"total\":{\"fn\":\"sum\",\"field\":\"value\"}}}},{\"derive\":{\"kind\":{\"literal\":\"a\"}}},{\"pivot\":{\"index\":[\"id\"],\"column\":\"kind\",\"values\":[\"a\"],\"value\":\"total\",\"aggregate\":\"sum\",\"fill\":0}},{\"select\":[\"id\",{\"value\":\"a\"}],\"as\":\"final\"}"
      } else {
        ""
      },
      producer_result_from=if mixed { "final" } else { "derived" },
      extra_step_budget=6,
    ) catch {
      Closure(UnresolvedOperation(site)) =>
        match site.requirement {
          @pipeline.RelationRequirement(pending) =>
            fail(@debug.to_string(pending.kind))
          _ => fail("non-relation numeric prefix requirement")
        }
      error => raise error
    },
  )
  checked[0]
}

///|
test "formal closure composes incremental collection with numeric preparation once" {
  let cases = [
    (numeric_prefix_program(false, false), false),
    (numeric_prefix_program(true, false), true),
    (pivot_program_fixture(empty=true), true),
    (pivot_program_fixture(), true),
    (numeric_prefix_program(true, true), true),
  ]
  for (program, enabled) in cases {
    let profile = if enabled { Some(numeric_profile_fixture()) } else { None }
    let budget = IdentityBudget::{
      work: 10000000,
      bytes: 1000000,
      nodes: 100000,
      depth: 100,
    }
    let (requirements, gates, contracts) = prepare_owned_closure(
      program.identity,
      budget,
      numeric_profile=profile,
    )
    // Independent phase accounting: use each retained preparation's own prefix
    // and suffix, not the aggregate remaining budget as the expected value.
    let phases : Array[(Int, Int)] = []
    if @context.core_contract_numeric_slots(contracts) is Some(slots) {
      phases.push(
        (
          @context.operation_requirements_work(
            @context.numeric_slots_requirements(slots),
          ),
          @context.numeric_slots_work(slots),
        ),
      )
    }
    if @context.core_contract_analytic_numeric_slots(contracts) is Some(slots) {
      phases.push(
        (
          @context.operation_requirements_work(
            @context.analytic_numeric_slots_requirements(slots),
          ),
          @context.analytic_numeric_slots_work(slots),
        ),
      )
    }
    if @context.core_contract_pivot_numeric_slots(contracts) is Some(slots) {
      phases.push(
        (
          @context.operation_requirements_work(
            @context.pivot_numeric_slots_requirements(slots),
          ),
          @context.pivot_numeric_slots_work(slots),
        ),
      )
    }
    assert_eq(phases.length(), if enabled { 3 } else { 0 })
    let profiles = @context.core_contract_profile_checks(contracts).unwrap()
    let mut shared = @context.operation_calendar_work(profiles)
    for (base, total) in phases {
      shared = Int::max(shared, base) + (total - base)
    }
    let requirement_work = @context.stage_requirement_usage(requirements).0
    assert_true(shared <= requirement_work)
    let owner_work = @context.incoming_links_work(
      @context.stage_requirement_owner(requirements),
    )
    let gate_work = @context.program_incoming_gates_usage(gates).0
    let contract_work = @context.core_contract_usage(contracts).0
    let expected = requirement_work + gate_work - owner_work + contract_work
    assert_eq(10000000 - budget.work, expected)
    let exact = IdentityBudget::{
      work: expected,
      bytes: 1000000,
      nodes: 100000,
      depth: 100,
    }
    let (_, _, repeated) = prepare_owned_closure(
      program.identity,
      exact,
      numeric_profile=profile,
    )
    assert_eq(exact.work, 0)
    assert_eq((exact.bytes, exact.nodes), (budget.bytes, budget.nodes))
    assert_eq(
      @context.core_contract_root_count(repeated),
      @context.core_contract_root_count(contracts),
    )
    let short = IdentityBudget::{
      work: expected - 1,
      bytes: 1000000,
      nodes: 100000,
      depth: 100,
    }
    let before = (short.work, short.bytes, short.nodes)
    let failed = try {
      ignore(
        prepare_owned_closure(program.identity, short, numeric_profile=profile),
      )
      false
    } catch {
      _ => true
    }
    assert_true(failed)
    assert_eq((short.work, short.bytes, short.nodes), before)
  }
}

///|
test "empty prepared numeric inventories do not recharge collection prerequisites" {
  let program = numeric_prefix_program(true, false)
  let budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (_, _, prepared) = prepare_owned_closure(
    program.identity,
    budget,
    numeric_profile=Some(numeric_profile_fixture()),
  )
  let plain = @context.collect_core_contracts(program.identity, {
    max_work: 1000000,
    max_roots: 10000,
    max_bodies: 10000,
    max_edges: 10000,
  }).unwrap()
  // The selected profile was prepared, but there is no numeric operation to
  // interpret. Both collections do the same work and select the same bodies;
  // the independent numeric preparation belongs to its own caller's accounting.
  assert_eq(
    @context.core_contract_usage(prepared),
    @context.core_contract_usage(plain),
  )
  assert_eq(
    @context.core_contract_hash_usage(prepared),
    @context.core_contract_hash_usage(plain),
  )
  let count = @context.core_contract_body_count(plain)
  assert_eq(@context.core_contract_body_count(prepared), count)
  for i in 0..<count {
    assert_eq(
      @context.core_contract_body_at(prepared, i),
      @context.core_contract_body_at(plain, i),
    )
  }
  let exact : @context.CoreContractLimits = {
    max_work: @context.core_contract_usage(plain).0,
    max_roots: @context.core_contract_root_count(plain),
    max_bodies: count,
    max_edges: @context.core_contract_usage(plain).1,
  }
  for short in [false, true] {
    let result = @context.collect_core_contracts(
      program.identity,
      { ..exact, max_work: exact.max_work - (if short { 1 } else { 0 }), },
      profile_checks=@context.core_contract_profile_checks(prepared),
      numeric_slots=@context.core_contract_numeric_slots(prepared),
      analytic_numeric_slots=@context.core_contract_analytic_numeric_slots(
        prepared,
      ),
      pivot_numeric_slots=@context.core_contract_pivot_numeric_slots(prepared),
    )
    if short {
      assert_true(result is Err(@context.CoreContractIssue::BudgetExceeded))
    } else {
      assert_true(result is Ok(_))
    }
  }
}
