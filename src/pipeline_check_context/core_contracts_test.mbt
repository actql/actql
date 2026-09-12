///|
test "policy presence and concrete limits do not replace interpretation contracts" {
  let lookup = "{\"max_network_attempts_per_request\":3,\"max_request_bytes_per_attempt\":1024,\"max_total_decoded_response_bytes\":65536,\"max_total_duration_ms\":30000,\"max_total_request_bytes\":8192,\"max_total_response_bytes\":16384,\"version\":\"actql-lookup-execution-policy/0.1\"}"
  let profiles = [
    capacity_profile(false),
    bound_profile(),
    capacity_profile(false).replace(
      old="}}",
      new="},\"lookup_execution\":" + lookup + "}",
    ),
    capacity_profile(false).replace(
      old="}}",
      new="},\"lookup_execution\":" +
        lookup.replace(old="8192", new="4096") +
        "}",
    ),
  ]
  let (first, _, first_context) = prepared_identity_fixture()
  let baseline = collect_core_contracts(first, {
    max_work: 10000000,
    max_roots: 1000,
    max_bodies: 100,
    max_edges: 100,
  }).unwrap()
  for profile in profiles {
    let (identity, _, context) = prepared_identity_fixture(
      environment_profile=profile,
    )
    let result = collect_core_contracts(identity, {
      max_work: 10000000,
      max_roots: 1000,
      max_bodies: 100,
      max_edges: 100,
    }).unwrap()
    assert_eq(
      program_identity_definition_cid(identity),
      program_identity_definition_cid(first),
    )
    assert_eq(
      core_contract_root_count(result),
      core_contract_root_count(baseline),
    )
    assert_eq(
      core_contract_body_count(result),
      core_contract_body_count(baseline),
    )
    for i in 0..<core_contract_body_count(result) {
      assert_eq(
        core_contract_body_at(result, i),
        core_contract_body_at(baseline, i),
      )
    }
    if profile != capacity_profile(false) {
      assert_true(
        @environment.cid(
          @local_inputs.program_environment(reconciled_snapshots(context)),
        ) !=
        @environment.cid(
          @local_inputs.program_environment(reconciled_snapshots(first_context)),
        ),
      )
    }
  }
}

///|
test "core contract collection preserves owned occurrences and shares dependency bodies" {
  let (identity, _, _) = prepared_identity_fixture(unused_operation=true)
  let inventory = collect_core_contracts(identity, {
    max_work: 10000000,
    max_roots: 1000,
    max_bodies: 100,
    max_edges: 100,
  }).unwrap()
  assert_true(physical_equal(core_contract_identity(inventory), identity))
  let mut visits = 0
  let mut steps = 0
  for stage in 0..<2 {
    let count = program_identity_producer_count(identity, stage).unwrap()
    visits += count
    for visit in 0..<count {
      steps += @pipeline.step_count(
        program_identity_producer_at(identity, stage, visit).unwrap(),
      )
    }
  }
  assert_eq(core_contract_root_count(inventory), 10 + 2 * steps)
  assert_eq(core_contract_body_count(inventory), 25)
  let (work, edges) = core_contract_usage(inventory)
  assert_eq(edges, 23)
  assert_eq(
    work,
    program_identity_usage(identity).0 +
    7 +
    10 +
    2 * steps +
    visits +
    2 * steps +
    25 +
    23,
  )
  let mut stage_roots = 0
  let mut unused_roots = 0
  let mut semantic_roots = 0
  for i in 0..<core_contract_root_count(inventory) {
    let root = core_contract_root_at(inventory, i).unwrap()
    match root.site {
      StageEnvironmentRules(stage) => {
        assert_true(stage >= 0 && stage < 2)
        assert_eq(root.body, CatalogGrammarBody(@environment.EnvironmentBody))
      }
      StageSemanticRules(stage, rules) => {
        assert_eq(stage, semantic_roots / 2)
        assert_eq(
          rules,
          if semantic_roots % 2 == 0 {
            @environment.SourceRules
          } else {
            @environment.StageLaws
          },
        )
        assert_eq(root.body, StageSemantics(rules))
        semantic_roots += 1
      }
      StageSourceGrammar(stage) => {
        assert_true(stage >= 0 && stage < 2)
        assert_eq(root.body, ProgramSourceGrammar)
        assert_eq(
          core_contract_cid(root.body),
          "sha256:a6bfc4b6c00d89f521ccee9e99e1dbbd7385675fd55478f1536f36f860b1ef0a",
        )
      }
      CatalogReference(_, _, _) => abort("Local fixture has no Catalog inputs")
      StageExpression(stage) => {
        assert_eq(stage, stage_roots)
        stage_roots += 1
        assert_eq(root.body, ExpressionBody(@environment.ExpressionRoot))
      }
      OperationLaw(stage, visit, step, profile, law) => {
        let pipeline = program_identity_producer_at(identity, stage, visit).unwrap()
        let operation = @pipeline.step_at(pipeline, step).unwrap()
        if operation.binding_name == Some("unused") {
          unused_roots += 1
        }
        assert_eq(profile, 0)
        assert_eq(
          root.body,
          AdoptedBody(
            if law == 0 {
              @pipeline.RelaScalar
            } else {
              @pipeline.RelaPrimitive
            },
          ),
        )
      }
    }
  }
  assert_eq(stage_roots, 2)
  assert_eq(semantic_roots, 4)
  assert_true(
    physical_equal(
      program_source_contract_identity(core_contract_sources(inventory)),
      identity,
    ),
  )
  assert_true(unused_roots >= 2)
  let seen : Array[String] = []
  for i in 0..<core_contract_body_count(inventory) {
    let cid = core_contract_cid(core_contract_body_at(inventory, i).unwrap())
    assert_true(!seen.contains(cid))
    seen.push(cid)
  }
  let exact : CoreContractLimits = {
    max_work: work,
    max_roots: core_contract_root_count(inventory),
    max_bodies: 25,
    max_edges: 23,
  }
  assert_true(collect_core_contracts(identity, exact) is Ok(_))
  assert_true(
    collect_core_contracts(identity, {
      ..exact,
      max_work: program_identity_usage(identity).0,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    collect_core_contracts(identity, {
      ..exact,
      max_work: program_identity_usage(identity).0 + 1,
    })
    is Err(SourceInventory(BudgetExceeded)),
  )
  for
    limits in [
      { ..exact, max_work: work - 1, },
      { ..exact, max_roots: exact.max_roots - 1, },
      { ..exact, max_bodies: 24, },
      { ..exact, max_edges: 22, },
    ] {
    assert_true(collect_core_contracts(identity, limits) is Err(BudgetExceeded))
  }
  for
    limits in [
      { ..exact, max_work: -1, },
      { ..exact, max_roots: -1, },
      { ..exact, max_bodies: -1, },
      { ..exact, max_edges: -1, },
    ] {
    assert_true(collect_core_contracts(identity, limits) is Err(InvalidLimits))
  }
  for invalid in [-2147483648, -1, 2147483647] {
    assert_true(core_contract_root_at(inventory, invalid) is None)
    assert_true(core_contract_body_at(inventory, invalid) is None)
  }
  assert_true(core_contract_root_at(inventory, exact.max_roots) is None)
  assert_true(core_contract_body_at(inventory, 25) is None)
}

///|
test "shared contract identities do not merge Programs or erase unused source" {
  let (first, _, _) = prepared_identity_fixture()
  let (other, _, _) = prepared_identity_fixture()
  let (unused, _, _) = prepared_identity_fixture(unused_operation=true)
  let limits : CoreContractLimits = {
    max_work: 10000000,
    max_roots: 1000,
    max_bodies: 100,
    max_edges: 100,
  }
  let a = collect_core_contracts(first, limits).unwrap()
  let b = collect_core_contracts(other, limits).unwrap()
  let c = collect_core_contracts(unused, limits).unwrap()
  assert_true(
    !physical_equal(core_contract_identity(a), core_contract_identity(b)),
  )
  assert_eq(core_contract_body_count(a), core_contract_body_count(c))
  assert_true(core_contract_root_count(c) > core_contract_root_count(a))
  assert_true(
    program_identity_definition_cid(first) !=
    program_identity_definition_cid(unused),
  )
  assert_eq(
    program_identity_definition_cid(first),
    program_identity_definition_cid(other),
  )
}
