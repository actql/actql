///|
fn request_lifetime_text(request : String) -> String {
  "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[{\"id\":\"s\",\"inputs\":{\"a\":{\"connector\":\"c\",\"resource\":\"r\",\"view\":\"v\",\"request\":" +
  request +
  "}},\"steps\":[{\"from\":\"a\",\"derive\":{\"score\":{\"property\":{\"name\":\"SCORE\",\"value\":{\"field\":\"payload\"}}}}},{\"filter\":{\"literal\":true}}],\"results\":{}}],\"results\":{}}"
}

///|
fn request_lifetime_stages(source : @builder.Source) -> Array[@wire.Cursor] {
  @wire.elements(member_lookup(@builder.cursor(source), "stages").unwrap()).unwrap()
}

///|
fn request_lifetime_request(source : @builder.Source) -> @wire.Cursor {
  member_lookup(
    member_lookup(
      member_lookup(request_lifetime_stages(source)[0], "inputs").unwrap(),
      "a",
    ).unwrap(),
    "request",
  ).unwrap()
}

///|
fn request_lifetime_builder(
  request : String,
) -> (@builder.Builder, @builder.Node, @origin.Document) {
  let text = request_lifetime_text(request)
  let document = @origin.document(text, 10000).unwrap()
  let builder = @builder.create(document, mapping_limits().source).unwrap()
  let parsed = @source.parse_json_measured(
    text,
    mapping_limits().source.source,
    source_path="<generated>",
  ).unwrap()
  let root = @builder.import_parsed(builder, parsed).unwrap()
  (builder, root, document)
}

///|
test "request DATA survives full prefix resolved replacement and actual demand prune together" {
  let dense = "{\"items\":[" +
    Array::makei(32, i => i.to_string()).join(",") +
    "]}"
  let deep = "{\"nest\":" +
    Array::make(20, "[").join("") +
    "null" +
    Array::make(20, "]").join("") +
    "}"
  for (request, nodes, text) in [(dense, 34, 5L), (deep, 22, 4L)] {
    let (builder, root, document) = request_lifetime_builder(request)
    let original = @builder.snapshot(builder, root).unwrap()
    let prefix = @builder.snapshot(builder, root).unwrap()
    let state = probe_budget_state(prefix, document)
    let stage = request_lifetime_stages(prefix)[0]
    let first = @wire.element_at(member_lookup(stage, "steps").unwrap(), 0).unwrap()
    let expression = member_lookup(
      member_lookup(first, "derive").unwrap(),
      "score",
    ).unwrap()
    state.expression(expression, Some(probe_budget_rows()), None)
    assert_eq(state.replacements.length(), 1)
    let resolved = state.finish()
    assert_eq(@builder.usage(resolved).nodes, @builder.usage(prefix).nodes)
    let copied_steps = member_lookup(
      request_lifetime_stages(resolved)[0],
      "steps",
    ).unwrap()
    let checked = @pipeline.check_carriers(
      copied_steps,
      [("a", @carrier.relation(@carrier.typed_rows(probe_budget_rows())))],
      None,
      None,
      {
        max_steps: 10000,
        max_work: 10000,
        max_nodes: 10000,
        max_tokens: 10000,
        max_text_bytes: 100000,
        max_depth: 100,
      },
    ).unwrap()
    let demand : ScriptDemand = {
      steps: [[true, false]],
      inputs: [[true]],
      pipelines: [checked],
    }
    let demanded = prune_query_binding_source(
      resolved,
      demand,
      document,
      mapping_limits(),
    ).unwrap()
    assert_eq(
      @wire.array_length(
        member_lookup(request_lifetime_stages(demanded)[0], "steps").unwrap(),
      ),
      Some(1),
    )
    // These are the real snapshot, resolved-copy and prune constructors. Keep
    // every original reachable and compare independent literal quantities;
    // a monotone quote or a one-short-of-itself check would not establish this.
    let sources = [original, prefix, resolved, demanded]
    for index, retained in sources {
      let literal = request_lifetime_request(retained)
      let actual = @wire.observe_subtree_construction_geometry(literal)
      assert_eq((actual.nodes, actual.total_utf16), (nodes, text))
      let writer = @encode.writer(4096, 100, 40)
      @program.emit_admitted_source_value(literal, writer)
      assert_eq(@encode.finish(writer), request)
      for previous in sources[:index] {
        assert_true(
          @wire.tree_index(@builder.cursor(previous), literal) is None,
        )
      }
    }
    let original_name = member_lookup(
      member_lookup(expression, "property").unwrap(),
      "name",
    ).unwrap()
    assert_eq(@wire.text(original_name).unwrap(), "SCORE")
    let changed = @wire.element_at(copied_steps, 0).unwrap()
    let changed = member_lookup(
      member_lookup(changed, "derive").unwrap(),
      "score",
    ).unwrap()
    assert_eq(
      @wire.text(
        member_lookup(member_lookup(changed, "property").unwrap(), "name").unwrap(),
      ).unwrap(),
      "score",
    )
    @builder.discard(builder)
  }
}

///|
fn request_lifetime_empty_catalog() -> @environment.SourceRequestContracts {
  // Independent empty canonical Environment fixture, not production output.
  let environment = @environment.read(
    b"{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],\"evidence_bundle_cid\":\"sha256:bf3e299a7386f7442aa04abc23901a1b3f580b490e6c625fe4ea686dce61032c\",\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}",
    "sha256:bf3e299a7386f7442aa04abc23901a1b3f580b490e6c625fe4ea686dce61032c",
    { max_bytes: 10000, max_nodes: 1000, max_depth: 20, max_members: 100, },
  ).unwrap()
  let registry = @environment.check_contract_registry(environment, {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 20,
    max_members: 100,
  }).unwrap()
  let contents = @environment.check_catalog_contents(registry, {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 20,
    max_members: 100,
  }).unwrap()
  let references = @environment.check_catalog_references(contents, {
    max_work: 10000,
    max_references: 100,
  }).unwrap()
  let policies = @environment.check_source_data_policies(references, {
    max_work: 10000,
    max_policies: 100,
  }).unwrap()
  let values = @environment.check_protocol_value_contracts(policies, {
    max_envelopes: 100,
    contracts: { max_nodes: 1000, max_depth: 20, max_text_bytes: 10000, },
  }).unwrap()
  let shapes = @environment.check_source_view_shapes(values, {
    max_work: 10000,
    max_views: 100,
  }).unwrap()
  let modes = @environment.check_source_read_modes(shapes, 10000).unwrap()
  let carriers = @environment.check_carrier_schemas(modes, {
    max_work: 10000,
    max_schemas: 100,
    bodies: { max_nodes: 1000, max_bytes: 10000, max_depth: 20, },
  }).unwrap()
  @environment.check_source_request_contracts(carriers, {
    max_work: 10000,
    max_roles: 100,
  }).unwrap()
}

///|
test "nested source-prefix refusal retains request copy beside its exact original" {
  let request = "{\"paths\":[\"a\",\"b\"],\"glob\":null}"
  let (builder, root, document) = request_lifetime_builder(request)
  let original = @builder.snapshot(builder, root).unwrap()
  let state = probe_budget_state(original, document)
  let stages = request_lifetime_stages(original)
  let steps = @wire.elements(member_lookup(stages[0], "steps").unwrap()).unwrap()
  let refused = try {
    ignore(
      state.source_prefix_carrier(
        stages,
        0,
        steps,
        request_lifetime_empty_catalog(),
        None,
      ),
    )
    None
  } catch {
    Abort(BindingPreparationSource(SourceRegistration(_), failed)) =>
      Some(failed)
    _ => None
  }
  guard refused is Some(failed) else {
    fail("expected the actual copied-prefix Source registration refusal")
  }
  let old_request = request_lifetime_request(original)
  let copied_request = request_lifetime_request(failed)
  assert_eq(@wire.observe_subtree_construction_geometry(old_request).nodes, 5)
  assert_eq(
    @wire.observe_subtree_construction_geometry(copied_request).nodes,
    5,
  )
  assert_true(
    @wire.tree_index(@builder.cursor(original), copied_request) is None,
  )
  assert_eq(
    @wire.array_length(member_lookup(old_request, "paths").unwrap()),
    Some(2),
  )
  @builder.discard(builder)
}

///|
test "outer checked prefix preserves request and original after semantic and work refusal" {
  let (source_builder, source_root, _) = request_lifetime_builder(
    "{\"region\":null}",
  )
  let original = @builder.snapshot(source_builder, source_root).unwrap()
  let declaration = member_lookup(
    member_lookup(request_lifetime_stages(original)[0], "inputs").unwrap(),
    "a",
  ).unwrap()
  let query = @query.parse_query(
    "FROM a |> SELECT payload",
    mapping_syntax_limits(),
  ).unwrap()
  let document = @query.query_document(query)
  let builder = @builder.create(document, mapping_limits().source).unwrap()
  let construction : Construction = {
    builder,
    generated: @origin.range(document, 0, 0, kind=Generated).unwrap(),
    model_tasks: None,
    parameter_names: None,
    infer_labels: false,
    infer_budget: { remaining_work: 10000, },
  }
  let input = import_query_cursor(construction, declaration)
  let step = construction.object([
    ("from", construction.text("a")),
    ("filter", construction.object([("literal", construction.add(Bool(true)))])),
  ])
  let copied = try {
    ignore(
      checked_query_prefix_pipeline(
        construction,
        query,
        mapping_context(),
        [],
        [("a", input)],
        [step],
        mapping_limits(),
        { remaining_work: 10000, },
      ),
    )
    None
  } catch {
    Abort(BindingPreparationSource(MissingSourceCatalog(_), failed)) =>
      Some(failed)
    _ => None
  }
  guard copied is Some(copied) else {
    fail("expected exact checked-prefix diagnostic Source")
  }
  assert_eq(
    @wire.observe_subtree_construction_geometry(
      request_lifetime_request(copied),
    ).nodes,
    2,
  )
  assert_true(
    @wire.tree_index(
      @builder.cursor(original),
      request_lifetime_request(copied),
    )
    is None,
  )
  assert_true(
    try {
      ignore(
        checked_query_prefix_pipeline(
          construction,
          query,
          mapping_context(),
          [],
          [("a", input)],
          [step],
          mapping_limits(),
          { remaining_work: 1, },
        ),
      )
      false
    } catch {
      Abort(Expression({ issue: @expression.WorkLimit, .. })) => true
      _ => false
    },
  )
  assert_eq(
    @wire.observe_subtree_construction_geometry(
      request_lifetime_request(original),
    ).nodes,
    2,
  )
  assert_eq(
    @wire.observe_subtree_construction_geometry(
      request_lifetime_request(copied),
    ).nodes,
    2,
  )
  @builder.discard(builder)
  @builder.discard(source_builder)
}
