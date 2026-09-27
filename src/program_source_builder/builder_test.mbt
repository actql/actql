///|
fn limits() -> @program_source_builder.Limits {
  {
    source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 20, },
    tree: {
      max_nodes: 1000,
      max_depth: 20,
      max_string_bytes: 1000,
      max_total_string_bytes: 10000,
    },
    max_origin_entries: 2000,
    max_output_bytes: 10000,
  }
}

///|
test "immutable builder bounds reuse and rejects owner substitution" {
  let document = @origin.document("x", 10).unwrap()
  let origin = @origin.range(document, 0, 1).unwrap()
  let b = @program_source_builder.create(document, limits()).unwrap()
  let n = @program_source_builder.add(b, String("e\u0301\r\n"), origin).unwrap()
  let xs = [n, n]
  let array = @program_source_builder.add(b, Array(xs), origin).unwrap()
  xs.clear()
  let source = @program_source_builder.finish(b, array).unwrap()
  let cursor = @program_source_builder.cursor(source)
  assert_eq(@wire.array_length(cursor), Some(2))
  assert_eq(@wire.text(@wire.element_at(cursor, 0).unwrap()).unwrap(), "é\n")
  assert_eq(@program_source_builder.usage(source), {
    input_bytes: 1,
    nodes: 3,
    depth: 1,
  })
  assert_eq(@program_source_builder.output_bytes(source), 15)
  let mapped = @program_source_builder.origin(source, cursor).unwrap()
  assert_eq(@origin.span(mapped), @origin.span(origin))
  let other = @program_source_builder.create(document, limits()).unwrap()
  assert_true(
    @program_source_builder.add(other, Array([n]), origin) is Err(ForeignNode),
  )
  assert_true(@program_source_builder.add(b, Null, origin) is Err(Closed))
  let other = @program_source_builder.create(document, limits()).unwrap()
  let foreign = @origin.range(@origin.document("x", 10).unwrap(), 0, 1).unwrap()
  assert_true(
    @program_source_builder.add(other, Null, foreign) is Err(ForeignOrigin),
  )
}

///|
test "duplicate normalized keys and invalid numbers close without a Source" {
  let document = @origin.document("source", 10).unwrap()
  let origin = @origin.range(document, 0, 6).unwrap()
  let b = @program_source_builder.create(document, limits()).unwrap()
  let n = @program_source_builder.add(b, Null, origin).unwrap()
  assert_true(
    @program_source_builder.add(
      b,
      Object([
        { key: "é", origin, value: n, },
        { key: "e\u0301", origin, value: n, },
      ]),
      origin,
    )
    is Err(DuplicateKey("é")),
  )
  assert_true(@program_source_builder.finish(b, n) is Err(Closed))
  for number in [-0.0, 1.0 / 0.0, 0.0 / 0.0] {
    let b = @program_source_builder.create(document, limits()).unwrap()
    assert_true(
      @program_source_builder.add(b, Number(number), origin)
      is Err(InvalidScalar),
    )
  }
}

///|
test "exact limits and one-over reject expansion before publishing" {
  let document = @origin.document("null", 4).unwrap()
  let origin = @origin.range(document, 0, 4).unwrap()
  let exact : @program_source_builder.Limits = {
    source: { max_input_bytes: 4, max_nodes: 3, max_depth: 1, },
    tree: {
      max_nodes: 3,
      max_depth: 1,
      max_string_bytes: 0,
      max_total_string_bytes: 0,
    },
    max_origin_entries: 3,
    max_output_bytes: 11,
  }
  let b = @program_source_builder.create(document, exact).unwrap()
  let n = @program_source_builder.add(b, Null, origin).unwrap()
  let r = @program_source_builder.add(b, Array([n, n]), origin).unwrap()
  assert_eq(
    @program_source_builder.output_bytes(
      @program_source_builder.finish(b, r).unwrap(),
    ),
    11,
  )
  for
    (small, issue) in [
      (
        { ..exact, source: { ..exact.source, max_nodes: 2, }, },
        @program_source_builder.NodeLimit,
      ),
      ({ ..exact, tree: { ..exact.tree, max_depth: 0, }, }, DepthLimit),
      ({ ..exact, max_origin_entries: 2, }, OriginLimit),
      ({ ..exact, max_output_bytes: 10, }, OutputLimit),
    ] {
    let b = @program_source_builder.create(document, small).unwrap()
    let n = @program_source_builder.add(b, Null, origin).unwrap()
    match @program_source_builder.add(b, Array([n, n]), origin) {
      Err(actual) => assert_eq(actual, issue)
      Ok(_) => fail("one-over must reject")
    }
  }
  let b = @program_source_builder.create(document, limits()).unwrap()
  @program_source_builder.discard(b)
  assert_true(@program_source_builder.add(b, Null, origin) is Err(Closed))
}

///|
test "editable ParsedSource usage and spans confer no admission" {
  let text = "[null,null]"
  let document = @origin.document(text, 20).unwrap()
  let parsed = @source.parse_json_measured(
    text,
    limits().source,
    source_path="<generated>",
  ).unwrap()
  let forged = { ..parsed, usage: { input_bytes: 0, nodes: 0, depth: 0, }, }
  let b = @program_source_builder.create(document, {
    ..limits(),
    source: { ..limits().source, max_nodes: 2, },
  }).unwrap()
  assert_true(
    @program_source_builder.import_parsed(b, forged) is Err(NodeLimit),
  )
  let b = @program_source_builder.create(document, limits()).unwrap()
  let root = @program_source_builder.import_parsed(b, forged).unwrap()
  assert_eq(
    @program_source_builder.usage(
      @program_source_builder.finish(b, root).unwrap(),
    ),
    { input_bytes: 11, nodes: 3, depth: 1, },
  )
  let bad = {
    ..parsed,
    node: { ..parsed.node, span: { ..parsed.node.span, start_byte: -1, }, },
  }
  let b = @program_source_builder.create(document, limits()).unwrap()
  assert_true(@program_source_builder.import_parsed(b, bad) is Err(InvalidSpan))
}

///|
test "string limits measure normalized values and raw admission stays bounded" {
  let document = @origin.document("e\u0301", 3).unwrap()
  let origin = @origin.range(document, 0, 3).unwrap()
  let exact = {
    ..limits(),
    tree: { ..limits().tree, max_string_bytes: 2, max_total_string_bytes: 2, },
    max_output_bytes: 4,
  }
  let b = @program_source_builder.create(document, exact).unwrap()
  let n = @program_source_builder.add(b, String("e\u0301"), origin).unwrap()
  let source = @program_source_builder.finish(b, n).unwrap()
  assert_eq(@wire.text(@program_source_builder.cursor(source)).unwrap(), "é")
  assert_eq(@program_source_builder.output_bytes(source), 4)
  for
    small in [
      { ..exact, tree: { ..exact.tree, max_string_bytes: 1, }, },
      { ..exact, tree: { ..exact.tree, max_total_string_bytes: 1, }, },
    ] {
    let b = @program_source_builder.create(document, small).unwrap()
    assert_true(
      @program_source_builder.add(b, String("e\u0301"), origin)
      is Err(StringLimit),
    )
  }
}

///|
test "cyclic editable trees and exponential reuse stay bounded" {
  let document = @origin.document("null", 4).unwrap()
  let origin = @origin.range(document, 0, 4).unwrap()
  let xs : Array[@source.Node] = []
  let raw : @source.Node = { value: Array(xs), span: @origin.span(origin), }
  xs.push(raw)
  let b = @program_source_builder.create(document, limits()).unwrap()
  assert_true(
    @program_source_builder.import_parsed(b, {
      node: raw,
      usage: { input_bytes: 0, nodes: 0, depth: 0, },
    })
    is Err(DepthLimit),
  )
  xs.clear()
  let b = @program_source_builder.create(document, limits()).unwrap()
  let mut n = @program_source_builder.add(b, Null, origin).unwrap()
  let mut stopped = false
  for _ in 0..<20 {
    match @program_source_builder.add(b, Array([n, n]), origin) {
      Ok(next) => n = next
      Err(NodeLimit) => {
        stopped = true
        break
      }
      _ => fail("expected bounded occurrence expansion")
    }
  }
  assert_true(stopped)
  assert_true(@program_source_builder.finish(b, n) is Err(Closed))
}

///|
test "key and value origins retain generated roles and exact owner binding" {
  let doc = @origin.document("key value", 9).unwrap()
  let key = @origin.range(doc, 0, 3, kind=Generated).unwrap()
  let value = @origin.range(doc, 4, 9).unwrap()
  let b = @program_source_builder.create(doc, limits()).unwrap()
  let node = @program_source_builder.add(b, Null, value).unwrap()
  let object = @program_source_builder.add(
    b,
    Object([{ key: "key", origin: key, value: node, }]),
    value,
  ).unwrap()
  let source = @program_source_builder.finish(b, object).unwrap()
  let root = @program_source_builder.cursor(source)
  let child = @wire.lookup(@wire.open_object(root).unwrap(), "key").unwrap()
  assert_eq(
    @origin.kind(@program_source_builder.key_origin(source, child).unwrap()),
    Generated,
  )
  assert_eq(
    @origin.start(@program_source_builder.key_origin(source, child).unwrap()).byte_offset,
    0,
  )
  assert_eq(
    @origin.start(@program_source_builder.origin(source, child).unwrap()).byte_offset,
    4,
  )
  assert_true(@program_source_builder.key_origin(source, root) is None)
  let other = @program_source_builder.create(doc, limits()).unwrap()
  let n = @program_source_builder.add(other, Null, value).unwrap()
  let other = @program_source_builder.finish(other, n).unwrap()
  assert_true(
    @program_source_builder.origin(
      source,
      @program_source_builder.cursor(other),
    )
    is None,
  )
}
