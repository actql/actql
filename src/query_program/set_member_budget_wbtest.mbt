///|
fn set_member_probe_source() -> (@builder.Source, @origin.Document) {
  let text = "{\"with\":\"right\",\"duplicates\":\"distinct\"}"
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
test "set member schemas charge the common probe and preserve nullable output" {
  let (source, document) = set_member_probe_source()
  let body = @builder.cursor(source)
  let right = probe_budget_rows()
  let payload = @schema.field_at(right, 0).unwrap()
  let left = @schema.from_fields(
    [(payload.name, @contract.with_nullability(payload.contract, false))],
    max_fields=10,
    max_name_bytes=100,
  ).unwrap()
  let names = Map([
    ("right", Some(@carrier.relation(@carrier.typed_rows(right)))),
  ])
  for
    (tag, operation) in [
      ("intersect", @set_shape.Intersect),
      ("except", @set_shape.Except),
    ] {
    let resolution = probe_budget_state(source, document)
    let checked = @set_shape.check(operation, body, left, right, {
      max_work: 10000,
      max_text_bytes: mapping_limits().source.tree.max_total_string_bytes,
      max_nodes: mapping_limits().source.tree.max_nodes,
      max_depth: mapping_limits().source.tree.max_depth,
    }).unwrap()
    let rows = resolution
      .operation_schema(tag, body, Some(left), names, None)
      .unwrap()
    assert_true(@schema.field_at(rows, 0).unwrap().contract.nullable)
    assert_eq(@schema.field_at(rows, 0).unwrap().name, payload.name)
    assert_eq(
      resolution.work,
      10000 - @builder.usage(source).nodes - @set_shape.usage(checked).work,
    )
    assert_false(resolution.probe_refused)
  }
}

///|
test "set member probes refuse exhausted work without releasing the allowance" {
  let (source, document) = set_member_probe_source()
  let rows = probe_budget_rows()
  let names = Map([
    ("right", Some(@carrier.relation(@carrier.typed_rows(rows)))),
  ])
  for tag in ["intersect", "except"] {
    let resolution = probe_budget_state(
      source,
      document,
      work=@builder.usage(source).nodes,
    )
    let rejected = try {
      ignore(
        resolution.operation_schema(
          tag,
          @builder.cursor(source),
          Some(rows),
          names,
          None,
        ),
      )
      false
    } catch {
      Abort(Expression({ issue: @expression.WorkLimit, .. })) => true
      _ => false
    }
    assert_true(rejected)
    assert_eq(resolution.work, 0)
  }
}

///|
test "incompatible set schemas remain the common owner's refusal" {
  let (source, document) = set_member_probe_source()
  let left = probe_budget_rows()
  let right = @schema.from_fields(
    [(Unqualified("payload"), @contract.primitive(BooleanType, nullable=false))],
    max_fields=10,
    max_name_bytes=100,
  ).unwrap()
  let names = Map([
    ("right", Some(@carrier.relation(@carrier.typed_rows(right)))),
  ])
  for
    (tag, operation) in [
      ("intersect", @set_shape.Intersect),
      ("except", @set_shape.Except),
    ] {
    assert_true(
      @set_shape.check(operation, @builder.cursor(source), left, right, {
        max_work: 10000,
        max_text_bytes: mapping_limits().source.tree.max_total_string_bytes,
        max_nodes: mapping_limits().source.tree.max_nodes,
        max_depth: mapping_limits().source.tree.max_depth,
      })
      is Err({ kind: Schema(IncompatibleContracts(_, _)), .. }),
    )
    let resolution = probe_budget_state(source, document)
    assert_true(
      resolution.operation_schema(
        tag,
        @builder.cursor(source),
        Some(left),
        names,
        None,
      )
      is None,
    )
    assert_true(resolution.probe_refused)
    assert_eq(resolution.work, 0)
  }
}
