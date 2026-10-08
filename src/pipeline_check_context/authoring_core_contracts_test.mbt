///|
fn authoring_contract_fixture(
  second_stage? : Bool = false,
) -> (
  SourceViewDeclarationPreparation,
  @program_refs.ProgramSemantics,
  Array[AuthoringPublicationChecks],
) raise {
  let stage =
    #|{"id":"first","inputs":{},"steps":[{"values":{"schema":{"seed":{"type":"boolean","nullable":false}},"rows":[{"seed":true}]},"as":"seed"},{"derive":{"n":"$x"}},{"select":["n"],"as":"output"}],"results":{"out":{"from":"output","fields":["n"]}}}
  let program = "{\"version\":\"actql/0.1\",\"id\":\"authoring\",\"params\":{\"x\":{\"type\":\"number\"}},\"stages\":[" +
    stage +
    (if second_stage {
      "," + stage.replace(old="first", new="second")
    } else {
      ""
    }) +
    "],\"results\":{\"out\":{\"from\":{\"stage\":\"" +
    (if second_stage { "second" } else { "first" }) +
    "\",\"result\":\"out\"}}}}"
  let parsed = match
    @syntax.parse(
      program,
      {
        source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
        tree: {
          max_nodes: 1000,
          max_depth: 100,
          max_string_bytes: 10000,
          max_total_string_bytes: 10000,
        },
        max_stages: 2,
      },
      format=Json,
    ) {
    Ok(value) => value
    Err(issue) => {
      @debug.debug(issue)
      fail("Authoring fixture must be a valid structured Program")
    }
  }
  let stages = @stages.prepare(parsed, {
    max_parameters: 1,
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }).unwrap()
  let declarations = @stages.declarations(stages)
  assert_true(
    @parameter.bind(declarations, None, {
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    })
    is Ok(NeedsBindings(_)),
  )
  let identity_limits = source_preparation_limits()
  let source = prepare_sourceview_declarations(
    stages,
    sourceview_catalog(prepared_environment_fixture(capacity_profile(false))),
    {
      max_work: 1000000,
      max_bindings: 10,
      max_slots: 100,
      max_order_keys: 100,
      inputs: {
        max_work: 1000000,
        max_nodes: 10000,
        max_depth: 100,
        max_text_bytes: 100000,
      },
      topology: {
        max_stages: 2,
        max_steps: 10,
        max_results: 2,
        max_work: 1000000,
        max_nodes: 10000,
        max_tokens: 1000,
        max_text_bytes: 100000,
        max_depth: 100,
      },
      body: identity_limits.body,
      uses: identity_limits.uses,
      references: identity_limits.references,
    },
  ).unwrap()
  let semantics = @program_refs.prepare_program_semantics(
    sourceview_declaration_usage(source),
    {
      max_work: 1000000,
      max_stages: 2,
      max_hash_bytes: 1000000,
      max_hash_nodes: 100000,
      max_depth: 100,
    },
  ).unwrap()
  let publications = []
  for index in 0..<@stages.stage_count(stages) {
    let stage_ports = @stage_results.wiring_stage_at(
      sourceview_declaration_wiring(source),
      index,
    ).unwrap()
    let ports = @stage_results.stage_port_publications(stage_ports)
    let pipeline = @parameter_slots.pipeline(
      @stages.collection(@stage_results.stage_port_source(stage_ports)),
    )
    let profiles = authoring_profile_proof(pipeline)
    let capacity = authoring_capacity()
    let resource = resolve_authoring_values_resources(
      profiles,
      0,
      capacity,
      values_publication_limits(),
    ).unwrap()
    let authoring = close_pipeline_authoring(
      profiles,
      capacity,
      [resource],
      1000000,
      100,
      100,
    ).unwrap()
    let orders = prepare_pipeline_orders(
      @results.ports_orders(ports),
      max_work=1000000,
      max_text_bytes=1000000,
    ).unwrap()
    let context = prepare_pipeline_authoring_context(
      authoring,
      orders,
      {
        max_work: 1000000,
        max_text_bytes: 1000000,
        max_name_bytes: 10000,
        max_input_work: 1000000,
        max_operand_work: 1000000,
      },
      { max_bytes: 1000000, max_nodes: 100000, max_depth: 100, },
    ).unwrap()
    publications.push(
      prepare_authoring_publications(context, ports, 1000000, 100).unwrap(),
    )
  }
  (source, semantics, publications)
}

///|
test "authoring contracts retain exact semantics and close the existing interpretation dependency graph without values" {
  let (source, semantics, publications) = authoring_contract_fixture()
  let limits : CoreContractLimits = {
    max_work: 1000000,
    max_roots: 100,
    max_bodies: 100,
    max_edges: 100,
  }
  let checked = collect_authoring_core_contracts(
    source, semantics, publications, limits,
  ).unwrap()
  assert_true(physical_equal(authoring_core_contract_source(checked), source))
  assert_true(
    physical_equal(authoring_core_contract_semantics(checked), semantics),
  )
  let publication = publications[0]
  assert_true(
    physical_equal(
      authoring_core_contract_publication_at(checked, 0).unwrap(),
      publication,
    ),
  )
  let roots : Array[(CoreContractSite, CoreContractBody)] = [
    (StageEnvironmentRules(0), CatalogGrammarBody(@environment.EnvironmentBody)),
    (StageSourceGrammar(0), ProgramSourceGrammar),
    (StageCanonicalIdentityRules(0), CanonicalIdentityRules),
    (
      StageSemanticRules(0, @environment.SourceRules),
      StageSemantics(@environment.SourceRules),
    ),
    (
      StageSemanticRules(0, @environment.StageLaws),
      StageSemantics(@environment.StageLaws),
    ),
    (
      StageSemanticRules(0, @environment.LocalContracts),
      StageSemantics(@environment.LocalContracts),
    ),
    (
      StageSemanticRules(0, @environment.LocalDependencies),
      StageSemantics(@environment.LocalDependencies),
    ),
    (StageExpression(0), ExpressionBody(@environment.ExpressionRoot)),
    (StagePublicationRules(0, 0), AdoptedBody(@pipeline.RelaPrimitive)),
    (OperationTransferRules(0, 0, 0), BoundTransferRules),
    (OperationValuesWireLaw(0, 0, 0), ValuesWireLaw),
    (OperationValuesExecutionRules(0, 0, 0), ValuesExecutionRules),
    (OperationCountLaw(0, 0, 0), ValuesCountLaw),
    (OperationLaw(0, 0, 0, 0, 0), AdoptedBody(@pipeline.RelaScalar)),
    (OperationLaw(0, 0, 0, 0, 1), AdoptedBody(@pipeline.RelaPrimitive)),
    (OperationTransferRules(0, 0, 1), BoundTransferRules),
    (OperationRelationCountRules(0, 0, 1), RelationCountRules),
    (OperationLaw(0, 0, 1, 0, 0), AdoptedBody(@pipeline.RelaScalar)),
    (OperationLaw(0, 0, 1, 0, 1), AdoptedBody(@pipeline.RelaPrimitive)),
    (OperationTransferRules(0, 0, 2), BoundTransferRules),
    (OperationRelationCountRules(0, 0, 2), RelationCountRules),
    (OperationLaw(0, 0, 2, 0, 0), AdoptedBody(@pipeline.RelaScalar)),
    (OperationLaw(0, 0, 2, 0, 1), AdoptedBody(@pipeline.RelaPrimitive)),
  ]
  // Independent inventory: Values adds transfer/wire/execution/count and both
  // adopted RelA laws. Derive and Select each add transfer/relation-count and
  // both RelA laws. These fourteen follow the nine Stage/publication roots.
  assert_eq(authoring_core_contract_root_count(checked), 23)
  for index in 0..<roots.length() {
    let actual = authoring_core_contract_root_at(checked, index).unwrap()
    assert_eq(actual.site, roots[index].0)
    assert_eq(actual.body, roots[index].1)
  }
  let seen : Array[CoreContractBody] = []
  for index in 0..<authoring_core_contract_body_count(checked) {
    let body = authoring_core_contract_body_at(checked, index).unwrap()
    assert_false(seen.contains(body))
    seen.push(body)
  }
  assert_true(seen.contains(ValuesExecutionRules))
  assert_true(seen.contains(CatalogGrammarBody(@environment.ValueGrammarBody)))
  assert_true(
    seen.contains(CatalogGrammarBody(@environment.CapacityGrammarBody)),
  )
  assert_true(seen.contains(ExpressionBody(Inherited(Base))))
  assert_false(seen.contains(LocalSnapshotRules))
  let (work, edges) = authoring_core_contract_usage(checked)
  let exact : CoreContractLimits = {
    max_work: work,
    max_roots: 23,
    max_bodies: seen.length(),
    max_edges: edges,
  }
  assert_true(
    collect_authoring_core_contracts(source, semantics, publications, exact)
    is Ok(_),
  )
  for
    limited in [
      { ..exact, max_work: work - 1, },
      { ..exact, max_roots: 22, },
      { ..exact, max_bodies: seen.length() - 1, },
      { ..exact, max_edges: edges - 1, },
    ] {
    assert_true(
      collect_authoring_core_contracts(source, semantics, publications, limited)
      is Err(BudgetExceeded),
    )
  }
  publications.clear()
  assert_true(
    physical_equal(
      authoring_core_contract_publication_at(checked, 0).unwrap(),
      publication,
    ),
  )
  assert_true(authoring_core_contract_root_at(checked, -1) is None)
  assert_true(authoring_core_contract_body_at(checked, -1) is None)
}

///|
test "authoring contracts refuse foreign owners missing stages and implicit incoming gates" {
  let (source, semantics, publications) = authoring_contract_fixture()
  let (_, foreign_semantics, foreign_publications) = authoring_contract_fixture()
  let limits : CoreContractLimits = {
    max_work: 1000000,
    max_roots: 100,
    max_bodies: 100,
    max_edges: 100,
  }
  assert_true(
    collect_authoring_core_contracts(
      source, foreign_semantics, publications, limits,
    )
    is Err(ForeignSemantics),
  )
  assert_true(
    collect_authoring_core_contracts(
      source, semantics, foreign_publications, limits,
    )
    is Err(ForeignPublication(0)),
  )
  assert_true(
    collect_authoring_core_contracts(source, semantics, [], limits)
    is Err(StageInventory),
  )
  assert_true(
    collect_authoring_core_contracts(source, semantics, publications, {
      ..limits,
      max_work: 0,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    collect_authoring_core_contracts(source, semantics, publications, {
      ..limits,
      max_work: -1,
    })
    is Err(InvalidLimits),
  )
  let (source, semantics, publications) = authoring_contract_fixture(
    second_stage=true,
  )
  // Neither Stage has an external pipeline input; the second Stage still has
  // an implicit success gate. Empty input counts cannot erase that obligation.
  assert_true(
    collect_authoring_core_contracts(source, semantics, publications, limits)
    is Err(UnsupportedIncoming(1)),
  )
}
