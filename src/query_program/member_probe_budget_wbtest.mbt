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
