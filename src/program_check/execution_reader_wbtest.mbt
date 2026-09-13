///|
test "source construction exposes owned admission activation and publication decisions" {
  let budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let checked : Array[CheckedProgram] = []
  let _ = local_construction_fixture(
    budget,
    second_stage=true,
    through_check=true,
    checked_results=checked,
  )
  let program = checked[0]
  let identity = source_identity(program)
  let closed = requirements(program)
  let gates = incoming_gates(program)
  let contracts = contract_inventory(program)
  // This consumer receives construction output only. It neither reads source
  // text nor runs a resolver to reconstruct the decisions it consumes.
  let owner = @context.stage_requirement_owner(closed)
  let expressions = expression_closure(program).unwrap()
  assert_true(
    physical_equal(@context.expression_closure_identity(expressions), identity),
  )
  assert_eq(@context.expression_closure_count(expressions), 0)
  let modes = @context.stage_requirement_source_modes(closed)
  assert_true(physical_equal(@context.source_mode_closure_owner(modes), owner))
  assert_eq(@context.source_mode_closure_count(modes), 0)
  let zero = IdentityBudget::{
    work: 0,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  try build_units(contracts, closed, gates, zero) catch {
    UnitBuildFailure::Expressions(
      @context.ExpressionClosureIssue::BudgetExceeded
    ) => ()
    e => raise e
  } noraise {
    _ => fail("expression closure accounting was bypassed")
  }
  let inputs = @context.stage_requirement_inputs(closed)
  assert_true(physical_equal(@context.local_input_closure_owner(inputs), owner))
  assert_eq(@context.local_input_closure_count(inputs), 3)
  let kinds = [
    @context.RawBinding,
    @context.PrimaryKeyComponents,
    @context.PrimaryKeyUniqueness,
  ]
  let raw = @context.local_input_closure_at(inputs, 0).unwrap()
  assert_eq(raw.subject.stage, 0)
  assert_eq(raw.subject.name, "rows")
  for i in 0..<3 {
    let check = @context.local_input_closure_at(inputs, i).unwrap()
    assert_eq(check.kind, kinds[i])
    assert_true(physical_equal(check.subject, raw.subject))
    assert_eq(@context.local_input_execution_phase(check), BeforeLocalInputUse)
    assert_eq(@context.local_input_execution_failure(check), RejectLocalInput)
    match @context.local_input_execution_predecessor(check) {
      None => assert_eq(i, 0)
      Some(prior) => {
        assert_true(i > 0)
        assert_eq(prior.kind, kinds[i - 1])
        assert_true(physical_equal(prior.subject, raw.subject))
      }
    }
  }
  let incoming = @context.stage_requirement_incoming(closed)
  assert_true(physical_equal(@context.incoming_closure_owner(incoming), owner))
  assert_eq(@context.incoming_closure_count(incoming), 3)
  let mut imports = 0
  for i in 0..<3 {
    let check = @context.incoming_closure_at(incoming, i).unwrap()
    assert_eq(check.site.stage, 1)
    assert_true(
      physical_equal(
        check.site.consumer,
        @context.program_identity_stage_at(identity, 1).unwrap(),
      ),
    )
    match check.site.requirement {
      Success(milestone, producer) => {
        assert_eq(check.kind, StageSuccess(milestone))
        assert_eq(milestone, Completed)
        assert_true(
          physical_equal(
            producer,
            @context.program_identity_stage_at(identity, 0).unwrap(),
          ),
        )
      }
      Result(name, producer, _) => {
        assert_eq(check.kind, ResultAvailable)
        assert_true(name == "again" || name == "rows")
        assert_true(
          physical_equal(
            producer,
            @context.program_identity_stage_at(identity, 0).unwrap(),
          ),
        )
        imports += 1
      }
      Receipt(_, _, _) => fail("unexpected receipt requirement")
    }
    assert_eq(@context.incoming_execution_phase(check), BeforeStageActivation)
    assert_eq(@context.incoming_execution_missing(check), AwaitPredecessor)
    assert_eq(@context.incoming_execution_unknown(check), AwaitReconciliation)
    assert_eq(
      @context.incoming_execution_failure(check),
      PreventDownstreamActivation,
    )
  }
  assert_eq(imports, 2)
  let publications = @context.stage_requirement_publications(closed)
  assert_true(
    physical_equal(@context.publication_closure_owner(publications), owner),
  )
  assert_eq(@context.publication_closure_count(publications), 2)
  for stage in 0..<2 {
    let entry = @context.publication_closure_at(publications, stage).unwrap()
    assert_eq(entry.stage, stage)
    assert_eq(entry.result_index, 0)
    assert_true(
      physical_equal(
        @publication.port_orders(entry.port),
        @context.checked_orders(entry.context),
      ),
    )
    let order = @publication.port_order(entry.port)
    assert_eq(@publication.publication_result_index(order), entry.result_index)
    if stage == 0 {
      assert_eq(@publication.publication_strategy(order), CandidateKey)
      assert_eq(@publication.publication_term_count(order), 1)
    } else {
      // An imported published order is evidence, not an invented key list.
      assert_eq(@publication.publication_strategy(order), Inherited)
      assert_true(@publication.publication_inherited_order(order) is Some(_))
      assert_eq(@publication.publication_term_count(order), 0)
    }
  }
}
