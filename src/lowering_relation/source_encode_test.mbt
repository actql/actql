///|
fn source_root(
  owner : @lowering_relation.BoundPrepared,
) -> @lowering_relation.ExpressionRoot {
  let seq = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  @lowering_relation.root_at(
    @lowering_relation.prepare_roots(seq, root_limits()).unwrap(),
    0,
  ).unwrap()
}

///|
fn source_wire(root : @lowering_relation.ExpressionRoot) -> String raise {
  let out = @encode.writer(100000, 10000, 2000)
  @lowering_relation.emit_root_source(root, out)
  @encode.finish(out)
}

///|
test "root source emits normalized text syntax rather than the bound machine node" {
  let root = source_root(
    expression_pipeline(",{\"derive\":{\"v\":\"id + 2\"}}"),
  )
  assert_eq(source_wire(root), "{\"add\":[{\"field\":\"id\"},{\"literal\":2}]}")
  let d = declarations()
  let owner = @lowering_relation.bind_parameters(
    prepared_with(d, tail=",{\"derive\":{\"v\":{\"$param\":\"amount\"}}}"),
    Some(bound(d)),
    max_parameters=1,
    max_name_bytes=6,
  ).unwrap()
  let root = source_root(owner)
  assert_eq(source_wire(root), "{\"$param\":\"amount\"}")
  assert_eq(expression_wire(root.expression), "{\"body\":7,\"op\":\"literal\"}")
}

///|
test "source encoding keeps literal contents opaque and omitted ELSE absent" {
  let root = source_root(
    expression_pipeline(
      ",{\"derive\":{\"v\":{\"literal\":{\"z\":[true,null,3],\"if\":{\"$param\":\"business\"},\"a\":\"é\"}}}}",
    ),
  )
  assert_eq(
    source_wire(root),
    "{\"literal\":{\"z\":[true,null,3],\"if\":{\"$param\":\"business\"},\"a\":\"é\"}}",
  )
  let root = source_root(
    expression_pipeline(
      ",{\"derive\":{\"v\":{\"case\":{\"when\":[{\"when\":{\"literal\":true},\"then\":{\"literal\":1}}]}}}}",
    ),
  )
  assert_eq(
    source_wire(root),
    "{\"case\":{\"when\":[{\"when\":{\"literal\":true},\"then\":{\"literal\":1}}]}}",
  )
}

///|
test "source emission shares writer budgets and failed writers publish nothing" {
  let root = source_root(
    expression_pipeline(",{\"derive\":{\"v\":{\"literal\":1}}}"),
  )
  let expected = "[{\"literal\":1},{\"literal\":1}]"
  let out = @encode.writer(expected.length(), 100, 10)
  @encode.begin_array(out)
  @lowering_relation.emit_root_source(root, out)
  @lowering_relation.emit_root_source(root, out)
  @encode.end_array(out)
  assert_eq(@encode.finish(out), expected)
  for limits in [(expected.length() - 1, 100, 10), (100, 2, 10), (100, 100, 1)] {
    let short = @encode.writer(limits.0, limits.1, limits.2)
    let failed = try {
      @encode.begin_array(short)
      @lowering_relation.emit_root_source(root, short)
      @lowering_relation.emit_root_source(root, short)
      @encode.end_array(short)
      let _ = @encode.finish(short)
      false
    } catch {
      @encode.OutputLimit => true
      _ => false
    }
    assert_true(failed)
    let unpublished = try {
      let _ = @encode.finish(short)
      false
    } catch {
      _ => true
    }
    assert_true(unpublished)
  }
  assert_eq(source_wire(root), "{\"literal\":1}")
}

///|
test "deep source emission uses container continuations instead of recursion" {
  let mut expr = "{\"literal\":1}"
  for _i = 0; _i < 512; _i = _i + 1 {
    expr = "{\"negate\":" + expr + "}"
  }
  let owner = expression_pipeline(",{\"derive\":{\"v\":" + expr + "}}")
  let seq = @lowering_relation.prepare_sequence(owner, {
    ..sequence_limits(),
    expressions: { ..expression_limits(), max_depth: 600, },
  }).unwrap()
  let root = @lowering_relation.root_at(
    @lowering_relation.prepare_roots(seq, root_limits()).unwrap(),
    0,
  ).unwrap()
  assert_eq(source_wire(root), expr)
}
