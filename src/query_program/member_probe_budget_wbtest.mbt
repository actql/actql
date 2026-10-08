///|
fn probe_budget_source() -> (@builder.Source, @origin.Document) {
  let text =
    #|[{"property":{"name":"SCORE","value":{"field":"payload"}}},{"property":{"name":"score","value":{"coalesce":[{"field":"payload"},{"literal":1}]}}},{"property":{"name":"ScOrE","value":{"field":"payload"}}}]
  let limits = mapping_limits()
  let document = @origin.document(text, 10000).unwrap()
  let parsed = @source.parse_json_measured(
    text,
    limits.source.source,
    source_path="<generated>",
  ).unwrap()
  let builder = @builder.create(document, limits.source).unwrap()
  let root = @builder.import_parsed(builder, parsed).unwrap()
  (@builder.finish(builder, root).unwrap(), document)
}

///|
fn probe_budget_state(
  source : @builder.Source,
  document : @origin.Document,
  work? : Int = 10000,
) -> MemberResolution {
  {
    source,
    document,
    limits: mapping_limits(),
    work,
    output_work: 0,
    probe_refused: false,
    replacements: Map([]),
  }
}

///|
fn probe_budget_rows() -> @schema.Schema {
  let number = @contract.primitive(@contract.NumberType, nullable=false)
  let payload = @contract.object_contract(
    [("score", number)],
    nullable=true,
    max_fields=10,
    max_name_bytes=100,
  ).unwrap()
  @schema.from_fields(
    [(@schema.Unqualified("payload"), payload)],
    max_fields=10,
    max_name_bytes=100,
  ).unwrap()
}

///|
fn probe_graph_prefix_source(
  bad_key? : Bool = false,
) -> (@builder.Source, @origin.Document) {
  let text =
    #|[{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}}},"rows":[{"id":1,"payload":null}]},"as":"nodes"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["id"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"payload","to":"payload"}]}}]}],"edges":[]},"as":"g"},{"from":"g","match_nodes":{"definition":"N","label":"Person","where":{"literal":true},"fields":["payload"]}}]
  let text = if bad_key {
    text.replace(old="\"key\":[\"id\"]", new="\"key\":[\"missing\"]")
  } else {
    text
  }
  let limits = mapping_limits()
  let document = @origin.document(text, 10000).unwrap()
  let parsed = @source.parse_json_measured(
    text,
    limits.source.source,
    source_path="<generated>",
  ).unwrap()
  let builder = @builder.create(document, limits.source).unwrap()
  let root = @builder.import_parsed(builder, parsed).unwrap()
  (@builder.finish(builder, root).unwrap(), document)
}

///|
test "Graph prefix uses common output and charges copying plus successful pipeline work" {
  let (source, document) = probe_graph_prefix_source()
  let resolution = probe_budget_state(source, document)
  let control = @pipeline.check_carriers(
    @builder.cursor(source),
    [],
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
  let output = resolution
    .closed_prefix_carrier(
      @wire.elements(@builder.cursor(source)).unwrap(),
      None,
    )
    .unwrap()
  let rows = member_rows(output).unwrap()
  let payload = @schema.lookup_reference(rows, "payload").unwrap().contract
  assert_true(payload.nullable)
  guard payload.shape is @contract.Object(fields) else {
    fail("common match output must retain the object")
  }
  let score = @contract.field_at(fields, 0).unwrap()
  assert_eq(score.name, "score")
  assert_true(score.contract.nullable)
  assert_eq(
    resolution.work,
    10000 - @builder.usage(source).nodes - @pipeline.usage(control).work,
  )
  assert_false(resolution.probe_refused)
}

///|
test "Graph prefix lends its remaining work before copying any over-budget tree" {
  let (source, document) = probe_graph_prefix_source()
  let steps = @wire.elements(@builder.cursor(source)).unwrap()
  // This fixture is already an array of the exact prefix. Its independent
  // admitted source node count includes the replacement array's single root.
  let nodes = @builder.usage(source).nodes
  for allowance in [0, nodes - 1] {
    let short = probe_budget_state(source, document, work=allowance)
    let rejected = try {
      ignore(short.closed_prefix_carrier(steps, None))
      false
    } catch {
      Abort(Expression({ issue: @expression.WorkLimit, .. })) => true
      _ => false
    }
    assert_true(rejected)
    // Failed partial construction retains the loan; it cannot fund a retry.
    assert_eq(short.work, 0)
  }
}

///|
test "refused Graph prefix retains its remaining allowance and stops continuation" {
  let (source, document) = probe_graph_prefix_source(bad_key=true)
  let resolution = probe_budget_state(source, document)
  let steps = @wire.elements(@builder.cursor(source)).unwrap()
  assert_true(resolution.closed_prefix_carrier(steps, None) is None)
  assert_true(resolution.probe_refused)
  assert_eq(resolution.work, 0)
  assert_eq(resolution.output_work, 0)
  assert_true(resolution.closed_prefix_carrier([steps[0]], None) is None)
  assert_eq(resolution.work, 0)
}

///|
test "member copy lends bounded work before importing any over-budget tree" {
  let (source, document) = probe_budget_source()
  // One array, two five-node property expressions and one nine-node expression.
  let nodes = 1 + 5 + 9 + 5
  let exact = probe_budget_state(source, document, work=nodes)
  let copied = exact.copy(@builder.cursor(source))
  assert_eq(@builder.usage(copied).nodes, nodes)
  assert_eq(exact.work, 0)
  let short = probe_budget_state(source, document, work=nodes - 1)
  let rejected = try {
    ignore(short.copy(@builder.cursor(source)))
    false
  } catch {
    Abort(Expression({ issue: @expression.WorkLimit, .. })) => true
    _ => false
  }
  assert_true(rejected)
  // A failed importer cannot release the allowance and start another copy.
  assert_eq(short.work, 0)
}

///|
test "authored member discovery reserves children before scheduling the scan" {
  let (source, document) = probe_budget_source()
  // Visit the array root and schedule its three children before finding a member.
  let exact = probe_budget_state(source, document, work=1 + 3)
  assert_true(exact.has_authored_member())
  assert_eq(exact.work, 0)
  let short = probe_budget_state(source, document, work=3)
  let rejected = try {
    ignore(short.has_authored_member())
    false
  } catch {
    Abort(Expression({ issue: @expression.WorkLimit, .. })) => true
    _ => false
  }
  assert_true(rejected)
  assert_eq(short.work, 2)
}

///|
test "each receiver environment debits its field and admitted name work" {
  let (source, document) = probe_budget_source()
  let root = @builder.cursor(source)
  let rows = probe_budget_rows()
  // One field plus the seven UTF-16 units in its name, for each probe.
  let exact = probe_budget_state(source, document, work=2 * (1 + 7))
  ignore(exact.environment(root, Some(rows), None))
  assert_eq(exact.work, 8)
  ignore(exact.environment(root, Some(rows), None))
  assert_eq(exact.work, 0)
  let short = probe_budget_state(source, document, work=7)
  let rejected = try {
    ignore(short.environment(root, Some(rows), None))
    false
  } catch {
    Abort(Expression({ issue: @expression.WorkLimit, .. })) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "refused common member probe retains its allowance and stops further probes" {
  let (source, document) = probe_budget_source()
  let resolution = probe_budget_state(source, document)
  let root = @builder.cursor(source)
  let bad = @wire.element_at(root, 1).unwrap()
  resolution.expression(bad, Some(probe_budget_rows()), None)
  assert_true(resolution.probe_refused)
  assert_eq(resolution.work, 0)
  assert_eq(resolution.output_work, 0)
  assert_eq(resolution.replacements.length(), 0)
  resolution.expression(
    @wire.element_at(root, 0).unwrap(),
    Some(probe_budget_rows()),
    None,
  )
  assert_eq(resolution.replacements.length(), 0)
  assert_eq(resolution.work, 0)
  assert_eq(
    @wire.tree_index(root, @builder.cursor(resolution.finish())),
    Some(0),
  )
}

///|
test "refused member probe preserves the held final copy and authored locations" {
  let (source, document) = probe_budget_source()
  let resolution = probe_budget_state(source, document)
  let root = @builder.cursor(source)
  let good = @wire.element_at(root, 0).unwrap()
  resolution.expression(good, Some(probe_budget_rows()), None)
  assert_eq(resolution.replacements.length(), 1)
  assert_eq(resolution.output_work, @builder.usage(source).nodes)
  resolution.expression(
    @wire.element_at(root, 1).unwrap(),
    Some(probe_budget_rows()),
    None,
  )
  assert_true(resolution.probe_refused)
  assert_eq(resolution.work, 0)
  resolution.expression(
    @wire.element_at(root, 2).unwrap(),
    Some(probe_budget_rows()),
    None,
  )
  assert_eq(resolution.replacements.length(), 1)
  let copied = resolution.finish()
  assert_eq(resolution.work, 0)
  assert_eq(resolution.output_work, 0)
  assert_eq(@builder.usage(copied).nodes, @builder.usage(source).nodes)
  let field = member_lookup(member_lookup(good, "property").unwrap(), "name").unwrap()
  let actual = member_lookup(
    member_lookup(
      @wire.element_at(@builder.cursor(copied), 0).unwrap(),
      "property",
    ).unwrap(),
    "name",
  ).unwrap()
  assert_eq(@wire.text(actual).unwrap(), "score")
  assert_eq(
    @origin.span(@builder.origin(copied, actual).unwrap()),
    @origin.span(@builder.origin(source, field).unwrap()),
  )
  let unvisited = member_lookup(
    member_lookup(
      @wire.element_at(@builder.cursor(copied), 2).unwrap(),
      "property",
    ).unwrap(),
    "name",
  ).unwrap()
  assert_eq(@wire.text(unvisited).unwrap(), "ScOrE")
}

///|
test "unknown producer schemas do not stop independent member binding" {
  let (source, document) = probe_budget_source()
  let resolution = probe_budget_state(source, document)
  let root = @builder.cursor(source)
  resolution.expression(@wire.element_at(root, 0).unwrap(), None, None)
  assert_false(resolution.probe_refused)
  assert_eq(resolution.replacements.length(), 0)
  resolution.expression(
    @wire.element_at(root, 2).unwrap(),
    Some(probe_budget_rows()),
    None,
  )
  assert_false(resolution.probe_refused)
  assert_eq(resolution.replacements.length(), 1)
}

///|
test "final member copy reserves exactly its retained nodes before another probe" {
  let (source, document) = probe_budget_source()
  let root = @builder.cursor(source)
  let at = member_lookup(
    member_lookup(@wire.element_at(root, 0).unwrap(), "property").unwrap(),
    "name",
  ).unwrap()
  let nodes = @builder.usage(source).nodes
  let small = probe_budget_state(source, document, work=nodes - 1)
  let rejected = try {
    small.replace_member(at, "score")
    false
  } catch {
    Abort(Expression({ issue: @expression.WorkLimit, .. })) => true
    _ => false
  }
  assert_true(rejected)
  assert_eq(small.replacements.length(), 0)
  assert_eq(small.output_work, 0)
  let exact = probe_budget_state(source, document, work=nodes)
  exact.replace_member(at, "score")
  assert_eq(exact.work, 0)
  assert_eq(exact.output_work, nodes)
  ignore(exact.finish())
  assert_eq(exact.work, 0)
  assert_eq(exact.output_work, 0)
}

///|
test "local Relation types use authored input admission within the remaining nodes" {
  let (source, document) = probe_budget_source()
  let declaration = @wire.admit(
    @source.parse_json(
      (
        #|{"carrier":"relation","schema":{"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":false}}}}}
      ),
      mapping_limits().source.source,
    ).unwrap(),
    mapping_limits().source.tree,
  ).unwrap()
  // Ten source nodes including the declaration, schema and recursive contract.
  let exact = probe_budget_state(source, document, work=10)
  let rows = exact.input_schema(declaration).unwrap()
  let payload = @schema.lookup_reference(rows, "payload").unwrap().contract
  assert_true(payload.nullable)
  guard payload.shape is @contract.Object(fields) else {
    fail("authored closed object must retain its common contract")
  }
  let score = @contract.field_at(fields, 0).unwrap()
  assert_eq(score.name, "score")
  assert_false(score.contract.nullable)
  assert_true(score.contract.shape is @contract.Number)
  assert_eq(exact.work, 0)
  assert_false(exact.probe_refused)
  let short = probe_budget_state(source, document, work=9)
  let rejected = try {
    ignore(short.input_schema(declaration))
    false
  } catch {
    Abort(Expression({ issue: @expression.WorkLimit, .. })) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "an unattached published Source View is not a local Relation declaration" {
  let (source, document) = probe_budget_source()
  let resolution = probe_budget_state(source, document)
  let declaration = @wire.admit(
    @source.parse_json(
      (
        #|{"connector":"fixture","resource":"rows","view":"current","schema":{"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":false}}}}}
      ),
      mapping_limits().source.source,
    ).unwrap(),
    mapping_limits().source.tree,
  ).unwrap()
  assert_true(resolution.input_schema(declaration) is None)
  assert_false(resolution.probe_refused)
  assert_eq(resolution.work, 10000)
}

///|
fn member_vector_probe_source() -> (@builder.Source, @origin.Document) {
  let text =
    #|[{"id":"id","vector":"embedding"},{"id":"missing","vector":"embedding"},{"queries":"vectors","metric":"dot","k":2}]
  let limits = mapping_limits()
  let document = @origin.document(text, 10000).unwrap()
  let parsed = @source.parse_json_measured(
    text,
    limits.source.source,
    source_path="<generated>",
  ).unwrap()
  let builder = @builder.create(document, limits.source).unwrap()
  let root = @builder.import_parsed(builder, parsed).unwrap()
  (@builder.finish(builder, root).unwrap(), document)
}

///|
fn member_vector_probe_input() -> @carrier.Carrier {
  let schema = @schema.from_fields(
    [
      (
        @schema.Unqualified("id"),
        @contract.primitive(@contract.StringType, nullable=false),
      ),
      (
        @schema.Unqualified("embedding"),
        @contract.vector_contract(2, nullable=false).unwrap(),
      ),
    ],
    max_fields=10,
    max_name_bytes=100,
  ).unwrap()
  @carrier.relation(@carrier.typed_rows(schema))
}

///|
test "member Carrier probes retain NEAREST types without discharging validation" {
  let (source, document) = member_vector_probe_source()
  let state = probe_budget_state(source, document)
  let root = @builder.cursor(source)
  let names : Map[String, @carrier.Carrier?] = Map([])
  let vectors = state
    .operation_carrier(
      "to_vectors",
      @wire.element_at(root, 0).unwrap(),
      Some(member_vector_probe_input()),
      names,
      None,
    )
    .unwrap()
  assert_eq(@carrier.kind(vectors), @carrier.VectorsKind)
  names["vectors"] = Some(vectors)
  let result = state
    .operation_carrier(
      "nearest",
      @wire.element_at(root, 2).unwrap(),
      Some(vectors),
      names,
      None,
    )
    .unwrap()
  let rows = member_rows(result).unwrap()
  assert_eq(@schema.field_count(rows), 4)
  let score = @schema.lookup_reference(rows, "score").unwrap().contract
  assert_true(score.shape is @contract.Number)
  assert_false(score.nullable)
  assert_false(state.probe_refused)
  assert_true(state.work < 10000 && state.work > 0)
}

///|
test "refused vector role probe retains allowance and stops member continuation" {
  let (source, document) = member_vector_probe_source()
  let state = probe_budget_state(source, document)
  let root = @builder.cursor(source)
  let names : Map[String, @carrier.Carrier?] = Map([])
  assert_true(
    state.operation_carrier(
      "to_vectors",
      @wire.element_at(root, 1).unwrap(),
      Some(member_vector_probe_input()),
      names,
      None,
    )
    is None,
  )
  assert_true(state.probe_refused)
  assert_eq(state.work, 0)
  assert_true(
    state.operation_carrier(
      "to_vectors",
      @wire.element_at(root, 0).unwrap(),
      Some(member_vector_probe_input()),
      names,
      None,
    )
    is None,
  )
  assert_eq(state.work, 0)
}
