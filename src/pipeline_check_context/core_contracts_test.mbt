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
      if program_identity_producer_is_local(identity, stage, visit) !=
        Some(true) {
        continue
      }
      steps += @pipeline.step_count(
        program_identity_producer_at(identity, stage, visit).unwrap(),
      )
    }
  }
  let incoming = core_contract_incoming(inventory)
  assert_true(physical_equal(program_incoming_identity(incoming), identity))
  assert_eq(program_incoming_count(incoming), 3)
  assert_eq(core_contract_root_count(inventory), 23 + 4 * steps)
  assert_eq(core_contract_body_count(inventory), 35)
  let (work, edges) = core_contract_usage(inventory)
  assert_eq(edges, 26)
  assert_eq(
    work,
    7 +
    20 +
    2 +
    247 +
    2 * steps +
    visits +
    4 * steps +
    35 +
    26 +
    program_incoming_usage(incoming).0 +
    6 +
    4 +
    core_contract_root_count(inventory) +
    65 +
    45,
  )
  let mut stage_roots = 0
  let mut unused_roots = 0
  let mut semantic_roots = 0
  for i in 0..<core_contract_root_count(inventory) {
    let root = core_contract_root_at(inventory, i).unwrap()
    match root.site {
      OperationModelContract(_, _, _, _) =>
        fail("this fixture has no model acquisition")
      OperationJoinCountRules(_, _, _) => assert_eq(root.body, JoinCountRules)
      OperationIntervalSearchRules(_, _, _) =>
        assert_eq(root.body, IntervalSearchRules)
      OperationAsOfSearchRules(_, _, _) => assert_eq(root.body, AsOfSearchRules)
      StageLocalInputRules(_, _) => assert_eq(root.body, LocalSnapshotRules)
      StageCanonicalIdentityRules(_) =>
        assert_eq(root.body, CanonicalIdentityRules)
      StagePublicationRules(_, _) =>
        assert_eq(root.body, AdoptedBody(@pipeline.RelaPrimitive))
      StageLocalInputType(stage, input) => {
        assert_eq((stage, input), (0, 0))
        assert_true(root.body is LocalInputType(_))
      }
      StageLocalInputScores(_, _) =>
        fail("this fixture has no score assertions")
      OperationRankingCountRules(_, _, _) =>
        assert_eq(root.body, RankingCountRules)
      OperationSeriesCountRules(_, _, _) =>
        assert_eq(root.body, SeriesCountRules)
      OperationGraphCountRules(_, _, _) => assert_eq(root.body, GraphCountRules)
      OperationWindowCountRules(_, _, _) =>
        assert_eq(root.body, WindowCountRules)
      OperationRelationCountRules(_, _, _) =>
        assert_eq(root.body, RelationCountRules)
      OperationTransferRules(stage, visit, step) => {
        assert_eq(root.body, BoundTransferRules)
        assert_true(
          @pipeline.step_at(
            program_identity_producer_at(identity, stage, visit).unwrap(),
            step,
          )
          is Some(_),
        )
      }
      IncomingRules(index) => {
        let site = program_incoming_at(incoming, index).unwrap()
        assert_eq(site.stage, 1)
        match site.requirement {
          Success(_, _) =>
            assert_eq(root.body, StageSemantics(@environment.GateRequirement))
          Result(_, _, _) => {
            assert_eq(
              root.body,
              StageSemantics(@environment.ResultImportInterface),
            )
            assert_eq(
              core_contract_cid(root.body),
              "sha256:81898e3b8eb76b16e59e0de4b38ed5d948e7752ae127b45ae432f39e0afd2431",
            )
          }
          Receipt(_, _, _) => abort("fixture has no Receipt")
        }
      }
      OperationDataProfile(_, _, _, _)
      | NumericAggregateProfile(_, _, _, _)
      | NumericAggregateSlotRules(_, _, _, _)
      | StageSourceResponsePolicyRules(_, _)
      | StageEffectiveDataPolicyRules(_, _)
      | OperationCountLaw(_, _, _)
      | OperationValuesWireLaw(_, _, _)
      | OperationValuesExecutionRules(_, _, _) =>
        abort("Local fixture has no data profile")
      StageEnvironmentRules(stage) => {
        assert_true(stage >= 0 && stage < 2)
        assert_eq(root.body, CatalogGrammarBody(@environment.EnvironmentBody))
      }
      StageSemanticRules(stage, rules) => {
        assert_eq(stage, semantic_roots / 4)
        assert_eq(
          rules,
          [
            @environment.SourceRules,
            @environment.StageLaws,
            @environment.LocalContracts,
            @environment.LocalDependencies,
          ][semantic_roots % 4],
        )
        assert_eq(root.body, StageSemantics(rules))
        semantic_roots += 1
      }
      StageSourceGrammar(stage) => {
        assert_true(stage >= 0 && stage < 2)
        assert_eq(root.body, ProgramSourceGrammar)
        assert_eq(
          core_contract_cid(root.body),
          "sha256:c6d41701c5ef0653a17d1472cfed07a657f3f655de70aa9c9a24b343fe571947",
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
  assert_eq(semantic_roots, 8)
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
    max_bodies: 35,
    max_edges: 26,
  }
  assert_true(collect_core_contracts(identity, exact) is Ok(_))
  assert_true(
    collect_core_contracts(identity, { ..exact, max_work: 0, })
    is Err(BudgetExceeded),
  )
  assert_true(
    collect_core_contracts(identity, { ..exact, max_work: 1, })
    is Err(SourceInventory(BudgetExceeded)),
  )
  for
    limits in [
      { ..exact, max_work: work - 1, },
      { ..exact, max_roots: exact.max_roots - 1, },
      { ..exact, max_bodies: 34, },
      { ..exact, max_edges: 25, },
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
  assert_true(core_contract_body_at(inventory, exact.max_bodies) is None)
}

///|
test "incoming grammar selection retains accepted and completed gate distinctions" {
  for accepted in [false, true] {
    let identity = incoming_fixture(accepted~)
    let inventory = collect_core_contracts(identity, {
      max_work: 10000000,
      max_roots: 1000,
      max_bodies: 100,
      max_edges: 100,
    }).unwrap()
    let incoming = core_contract_incoming(inventory)
    assert_true(physical_equal(program_incoming_identity(incoming), identity))
    let gate = program_incoming_at(incoming, 0).unwrap()
    guard gate.requirement is Success(milestone, producer) else {
      abort("predecessor gate")
    }
    assert_eq(milestone, if accepted { Accepted } else { Completed })
    assert_true(
      physical_equal(producer, program_identity_stage_at(identity, 0).unwrap()),
    )
    let root = core_contract_root_at(inventory, 0).unwrap()
    assert_eq(root.site, IncomingRules(0))
    assert_eq(root.body, StageSemantics(@environment.GateRequirement))
    assert_eq(
      core_contract_root_at(inventory, 1).unwrap().body,
      StageSemantics(@environment.ResultImportInterface),
    )
  }
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
