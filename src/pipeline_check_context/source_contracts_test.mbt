///|
test "integrity-valid but uninterpreted Catalog facts cannot seal a contract inventory" {
  let remote = []
  let (stages, wiring, _, _, locals, evidence) = wired_inputs_fixture(
    true,
    remote=Some(remote),
    uninterpreted_facts=true,
    profile=capacity_profile(false),
  )
  let wired = attach_result_wiring(
    stages,
    wiring,
    max_work=1000000,
    max_text_bytes=1000000,
  ).unwrap()
  let context = attach_reconciled_inputs(
    wired,
    evidence.unwrap(),
    locals,
    sourceviews=Some(remote[0]),
    max_work=1000000,
    max_text_bytes=1000000,
    max_local_input_nodes=100000,
  ).unwrap()
  let identity = prepared_reconciled_identity(
    context,
    @local_inputs.program_environment(reconciled_snapshots(context)),
  )
  let result = collect_core_contracts(identity, {
    max_work: 10000000,
    max_roots: 1000,
    max_bodies: 1000,
    max_edges: 1000,
  })
  guard result is Err(CatalogBody(stage, input, reference, issue)) else {
    abort("unsupported facts were treated as a leaf")
  }
  assert_eq((stage, input), (0, 0))
  assert_eq(issue, @environment.UnsupportedBodyGrammar("carrier_facts"))
  let selected = @sourceviews.pipeline_input_source(remote[0], stage, input).unwrap()
  let envelope = @environment.reference_contract(
    @sourceviews.selected_reference_at(selected, reference).unwrap(),
  )
  assert_eq(@environment.contract_role(envelope), "carrier_facts")
}

///|
fn check_source_contract_inventory(
  context : ReconciledContexts,
  views : @sourceviews.PipelineInputs,
  expected_inputs? : Int = 1,
) -> Unit raise {
  let v = collect_source_contracts(context, {
    max_work: 10000000,
    max_inputs: 100,
    max_references: 10000,
  }).unwrap()
  assert_true(physical_equal(source_contract_context(v), context))
  assert_eq(source_contract_stage_count(v), 2)
  assert_eq(source_contract_input_count(v, 0), Some(expected_inputs))
  assert_eq(source_contract_input_count(v, 1), Some(0))
  let input = source_contract_input_at(v, 0, 0).unwrap()
  assert_true(
    physical_equal(
      input,
      @sourceviews.pipeline_input_source(views, 0, 0).unwrap(),
    ),
  )
  let refs = @sourceviews.selected_reference_count(input)
  assert_true(refs > 0)
  for i in 0..<refs {
    let envelope = @environment.reference_contract(
      @sourceviews.selected_reference_at(input, i).unwrap(),
    )
    match source_contract_body_at(v, 0, 0, i) {
      Ok(body) => {
        let body = body.unwrap()
        assert_true(
          physical_equal(@environment.catalog_body_contract(body), envelope),
        )
        assert_true(@environment.catalog_body_dependency_count(body) > 0)
      }
      Err(issue) => {
        let kind = @environment.contract_role(envelope)
        assert_true(
          [
            "carrier_facts", "pushdown", "reconciliation", "poll", "cancel", "request_data_handling",
            "provider_execution_capability",
          ].contains(kind),
        )
        assert_eq(issue, @environment.UnsupportedBodyGrammar(kind))
      }
    }
    assert_true(
      physical_equal(
        @environment.reference_member(
          @sourceviews.selected_reference_at(input, i).unwrap(),
        ),
        @environment.source_request_member(
          @sourceviews.selected_contract(input),
        ),
      ),
    )
  }
  let (work, inputs, references) = source_contract_usage(v)
  assert_eq(inputs, expected_inputs)
  assert_eq(references, refs * expected_inputs)
  assert_eq(work, reconciled_usage(context).work + 1 + 2 + expected_inputs)
  let exact : SourceContractLimits = {
    max_work: work,
    max_inputs: inputs,
    max_references: references,
  }
  assert_true(collect_source_contracts(context, exact) is Ok(_))
  for
    limits in [
      { ..exact, max_work: work - 1, },
      { ..exact, max_inputs: inputs - 1, },
      { ..exact, max_references: references - 1, },
    ] {
    assert_true(
      collect_source_contracts(context, limits) is Err(BudgetExceeded),
    )
  }
  for
    limits in [
      { ..exact, max_work: -1, },
      { ..exact, max_inputs: -1, },
      { ..exact, max_references: -1, },
    ] {
    assert_true(collect_source_contracts(context, limits) is Err(InvalidLimits))
  }
  for invalid in [-2147483648, -1, 2, 2147483647] {
    assert_true(source_contract_body_at(v, invalid, 0, 0) is Ok(None))
    assert_true(source_contract_input_count(v, invalid) is None)
    assert_true(source_contract_input_at(v, invalid, 0) is None)
  }
  for invalid in [-2147483648, -1, expected_inputs, 2147483647] {
    assert_true(source_contract_body_at(v, 0, invalid, 0) is Ok(None))
    assert_true(source_contract_input_at(v, 0, invalid) is None)
  }
  assert_true(source_contract_input_at(v, 1, 0) is None)
  for invalid in [-2147483648, -1, refs, 2147483647] {
    assert_true(source_contract_body_at(v, 0, 0, invalid) is Ok(None))
  }
}

///|
test "repeated unused SourceView declarations retain separate input occurrences" {
  let remote = []
  let (stages, wiring, _, _, locals, evidence) = wired_inputs_fixture(
    true,
    remote=Some(remote),
    repeat_remote=true,
    profile=capacity_profile(false),
  )
  let views = remote[0]
  let wired = attach_result_wiring(
    stages,
    wiring,
    max_work=1000000,
    max_text_bytes=1000000,
  ).unwrap()
  let context = attach_reconciled_inputs(
    wired,
    evidence.unwrap(),
    locals,
    sourceviews=Some(views),
    max_work=1000000,
    max_text_bytes=1000000,
    max_local_input_nodes=100000,
  ).unwrap()
  check_source_contract_inventory(context, views, expected_inputs=2)
  let v = collect_source_contracts(context, {
    max_work: 10000000,
    max_inputs: 2,
    max_references: 10000,
  }).unwrap()
  let a = source_contract_input_at(v, 0, 0).unwrap()
  let b = source_contract_input_at(v, 0, 1).unwrap()
  assert_false(physical_equal(a, b))
  assert_eq(@sourceviews.declaration(a).input_name, "remote")
  assert_eq(@sourceviews.declaration(b).input_name, "remote_again")
  assert_true(
    physical_equal(
      @sourceviews.selected_contract(a),
      @sourceviews.selected_contract(b),
    ),
  )
  for i in 0..<@sourceviews.selected_reference_count(a) {
    assert_true(
      physical_equal(
        @sourceviews.selected_reference_at(a, i).unwrap(),
        @sourceviews.selected_reference_at(b, i).unwrap(),
      ),
    )
  }
  let identity = prepared_reconciled_identity(
    context,
    @local_inputs.program_environment(reconciled_snapshots(context)),
  )
  let result = collect_core_contracts(identity, {
    max_work: 10000000,
    max_roots: 1000,
    max_bodies: 1000,
    max_edges: 1000,
  })
  let inventory = match result {
    Ok(value) => value
    Err(issue) => {
      @debug.debug(issue)
      abort("selected Catalog collection")
    }
  }
  assert_true(physical_equal(core_contract_identity(inventory), identity))
  let count = @sourceviews.selected_reference_count(a)
  let incoming_count = program_incoming_count(core_contract_incoming(inventory))
  for input in 0..<2 {
    let policy = core_contract_root_at(
      inventory,
      incoming_count + input * (count + 2),
    ).unwrap()
    assert_eq(policy.site, StageSourceResponsePolicyRules(0, input))
    assert_eq(policy.body, SourceResponsePolicyRules)
    let effective = core_contract_root_at(
      inventory,
      incoming_count + input * (count + 2) + 1,
    ).unwrap()
    assert_eq(effective.site, StageEffectiveDataPolicyRules(0, input))
    assert_eq(effective.body, EffectiveDataPolicyRules)
    for reference in 0..<count {
      let root = core_contract_root_at(
        inventory,
        incoming_count + input * (count + 2) + 2 + reference,
      ).unwrap()
      assert_eq(root.site, CatalogReference(0, input, reference))
      let expected = @environment.contract_identity(
          @environment.reference_contract(
            @sourceviews.selected_reference_at(a, reference).unwrap(),
          ),
        ).2
      assert_eq(root.body, CatalogContract(expected))
      assert_true(stage_has_contract(inventory, 0, CatalogContract(expected)))
      assert_false(stage_has_contract(inventory, 1, CatalogContract(expected)))
    }
  }
  assert_true(stage_has_contract(inventory, 0, SourceResponsePolicyRules))
  assert_false(stage_has_contract(inventory, 1, SourceResponsePolicyRules))
  assert_true(stage_has_contract(inventory, 0, EffectiveDataPolicyRules))
  assert_false(stage_has_contract(inventory, 1, EffectiveDataPolicyRules))
  assert_eq(core_contract_body_count(inventory), 42)
  let (work, edges) = core_contract_usage(inventory)
  assert_eq(edges, 39)
  let exact : CoreContractLimits = {
    max_work: work,
    max_roots: core_contract_root_count(inventory),
    max_bodies: 42,
    max_edges: edges,
  }
  assert_true(collect_core_contracts(identity, exact) is Ok(_))
  for
    limits in [
      { ..exact, max_work: work - 1, },
      { ..exact, max_roots: exact.max_roots - 1, },
      { ..exact, max_bodies: 41, },
      { ..exact, max_edges: edges - 1, },
    ] {
    assert_true(collect_core_contracts(identity, limits) is Err(_))
  }
}

///|
test "source contract inventories join only their original Program identity context" {
  let (operations, references, bindings) = program_sources_fixture()
  let sources = bind_program_sources(operations, references, bindings, 10000000).unwrap()
  let identity = identify_program_sources(sources, identity_limits()).unwrap()
  let context = source_request_inputs(
    source_rows_requests(
      source_policy_rows(
        source_capacity_context(
          source_producer_capacity(
            preparation_sources(operation_profiles_preparation(operations)),
          ),
        ),
      ),
    ),
  )
  let requirements = collect_source_contracts(context, {
    max_work: 10000000,
    max_inputs: 0,
    max_references: 0,
  }).unwrap()
  assert_eq(source_contract_stage_count(requirements), 2)
  for i in 0..<2 {
    assert_eq(source_contract_input_count(requirements, i), Some(0))
  }
  let v = bind_program_source_contracts(identity, requirements, 10000000).unwrap()
  for stage in [-2147483648, -1, 0, 1, 2, 2147483647] {
    assert_true(program_source_contract_body_at(v, stage, 0, 0) is Ok(None))
  }
  assert_true(physical_equal(program_source_contract_identity(v), identity))
  assert_true(
    physical_equal(program_source_contract_requirements(v), requirements),
  )
  let work = program_source_contract_work(v)
  assert_eq(work, program_identity_usage(identity).0 + 4)
  assert_true(
    bind_program_source_contracts(identity, requirements, work) is Ok(_),
  )
  assert_true(
    bind_program_source_contracts(identity, requirements, work - 1)
    is Err(BudgetExceeded),
  )
  assert_true(
    bind_program_source_contracts(identity, requirements, -1)
    is Err(InvalidLimits),
  )
  let (other_operations, other_references, other_bindings) = program_sources_fixture()
  let other_sources = bind_program_sources(
    other_operations, other_references, other_bindings, 10000000,
  ).unwrap()
  let other_identity = identify_program_sources(
    other_sources,
    identity_limits(),
  ).unwrap()
  assert_eq(
    program_identity_definition_cid(identity),
    program_identity_definition_cid(other_identity),
  )
  assert_true(
    bind_program_source_contracts(other_identity, requirements, 10000000)
    is Err(ForeignContext),
  )
  // Reissuing an identity from the exact same validated source context is safe.
  let same = identify_program_sources(sources, identity_limits()).unwrap()
  assert_true(bind_program_source_contracts(same, requirements, work) is Ok(_))
}
