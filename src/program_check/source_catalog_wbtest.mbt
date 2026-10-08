///|
test "source Catalog preparation retains the exact configured and wire owners" {
  let wire = keyed_sourceview_environment()
  let environment = checking_environment(
    wire,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  let prepared = prepare_source_catalog(environment, {
    max_work: 10000000,
    max_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 100,
  }).unwrap()
  assert_true(physical_equal(source_catalog_owner(prepared), environment))
  let catalog = source_catalog_contracts(prepared)
  let refs = @environment.data_policy_references(
    @environment.value_contract_policies(
      @environment.source_view_shape_values(
        @environment.read_mode_shapes(
          @environment.carrier_schema_modes(
            @environment.source_request_carriers(catalog),
          ),
        ),
      ),
    ),
  )
  assert_true(
    physical_equal(
      @environment.contract_registry_environment(
        @environment.catalog_registry(@environment.reference_contents(refs)),
      ),
      checking_environment_wire(environment),
    ),
  )
  // A separately admitted equal wire is not substituted for the retained owner.
  let other = keyed_sourceview_environment()
  assert_false(physical_equal(checking_environment_wire(environment), other))
  assert_eq(@environment.cid(wire), @environment.cid(other))
}

///|
test "source Catalog preparation reports aggregate usage and refuses short caps" {
  let environment = checking_environment(
    keyed_sourceview_environment(),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  let generous : SourceCatalogLimits = {
    max_work: 10000000,
    max_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 100,
  }
  let used = source_catalog_usage(
    prepare_source_catalog(environment, generous).unwrap(),
  )
  assert_true(used.work > 0 && used.bytes > 0 && used.nodes > 0)
  let exact : SourceCatalogLimits = {
    max_work: used.work,
    max_bytes: used.bytes,
    max_nodes: used.nodes,
    max_depth: generous.max_depth,
  }
  assert_eq(
    source_catalog_usage(prepare_source_catalog(environment, exact).unwrap()),
    used,
  )
  for
    short in [
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_bytes: exact.max_bytes - 1, },
      { ..exact, max_nodes: exact.max_nodes - 1, },
      { ..exact, max_work: -1, },
      { ..exact, max_bytes: -1, },
      { ..exact, max_nodes: -1, },
      { ..exact, max_depth: -1, },
    ] {
    assert_true(prepare_source_catalog(environment, short) is Err(_))
  }
  // Refusal does not replace or mutate the owner, so the same preparation may
  // be attempted again with its original exact allowance.
  assert_eq(
    source_catalog_usage(prepare_source_catalog(environment, exact).unwrap()),
    used,
  )
}

///|
test "prepared Catalog registers the retained Source Stage without schema substitution" {
  let environment = checking_environment(
    keyed_sourceview_environment(),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  let prepared = prepare_source_catalog(environment, {
    max_work: 10000000,
    max_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 100,
  }).unwrap()
  // Independent ordinary Program: Catalog selection supplies the actual
  // SourceView schema. No row sample, synthetic key or Graph domain is supplied.
  let text =
    #|{"version":"actql/0.1","id":"fixture.source_catalog","stages":[{"id":"main","inputs":{"rows":{"connector":"crm/main","resource":"r","view":"v"}},"steps":[{"from":"rows","select":["id"],"as":"kept"}],"results":{"rows":{"from":"kept","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let program = @syntax.parse(
    text,
    {
      source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      tree: {
        max_nodes: 1000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 10000,
      },
      max_stages: 1,
    },
    format=Json,
  ).unwrap()
  let source = @stages.prepare(program, {
    max_parameters: 0,
    max_nodes: 1000,
    max_text_bytes: 10000,
    max_depth: 100,
  }).unwrap()
  let (views, _) = @context.prepare_source_registrations(
    source,
    source_catalog_contracts(prepared),
    {
      max_work: 1000000,
      max_nodes: 10000,
      max_text_bytes: 100000,
      max_depth: 100,
    },
    max_inputs=1,
    max_views=1,
    max_order_keys=1,
  ).unwrap()
  let input = @sourceviews.pipeline_input_at(views, 0, 0).unwrap()
  guard input.1 is @pipeline.SourceViewInput(stage, declared, _, _) else {
    fail("Catalog selection must retain SourceView provenance")
  }
  assert_eq(declared, "rows")
  assert_true(physical_equal(stage, @stages.stage_at(source, 0).unwrap()))
  assert_true(
    physical_equal(
      @sourceviews.pipeline_environment(views),
      checking_environment_wire(environment),
    ),
  )
  let body = @decode.open_object(@syntax.stage_body(stage)).unwrap()
  let steps = @decode.required(body, "steps").unwrap()
  let limits : @pipeline.Limits = {
    max_steps: 1,
    max_work: 1000000,
    max_nodes: 10000,
    max_tokens: 10000,
    max_text_bytes: 100000,
    max_depth: 100,
  }
  let checked = @pipeline.check_with_evidence(
    steps,
    [input],
    Some(@stages.declarations(source)),
    None,
    limits,
  ).unwrap()
  let rows = @carrier.complete_schema(
    @carrier.relation_rows(@pipeline.output_carrier(checked).unwrap()).unwrap(),
  ).unwrap()
  assert_eq(@schema.field_count(rows), 1)
  let id = @schema.lookup_reference(rows, "id").unwrap()
  assert_false(id.contract.nullable)
  assert_true(id.contract.shape is @contract.Number)
  // An independently admitted equal document has a different Stage owner.
  let foreign = @syntax.parse(
    text,
    {
      source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      tree: {
        max_nodes: 1000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 10000,
      },
      max_stages: 1,
    },
    format=Json,
  ).unwrap()
  let foreign_body = @decode.open_object(
    @syntax.stage_body(@syntax.stages(foreign)[0]),
  ).unwrap()
  assert_true(
    @pipeline.check_with_evidence(
      @decode.required(foreign_body, "steps").unwrap(),
      [input],
      Some(@stages.declarations(source)),
      None,
      limits,
    )
    is Err({ kind: KeyEvidence(InputContractMismatch), .. }),
  )
}
