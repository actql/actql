///|
fn budget(
  nodes? : Int = 100000,
  depth? : Int = 20000,
  string_bytes? : Int = 100000,
  total_bytes? : Int = 1000000,
) -> Limits {
  {
    max_nodes: nodes,
    max_depth: depth,
    max_string_bytes: string_bytes,
    max_total_string_bytes: total_bytes,
  }
}

///|
fn mark(start : Int) -> @span.Span {
  {
    start_byte: start,
    end_byte: start + 1,
    start_line: 1,
    start_column: start + 1,
    end_line: 1,
    end_column: start + 2,
    source_path: "input.json",
  }
}

///|
fn node(value : @source.Value, start? : Int = 0) -> @source.Node {
  { value, span: mark(start), }
}

///|
fn entry(key : String, value : @source.Node, start? : Int = 1) -> @source.Field {
  { key, value, key_span: mark(start), }
}

///|
fn[T] rejection(result : Result[T, Issue]) -> Issue raise {
  match result {
    Err(error) => error
    Ok(_) => fail("expected rejection")
  }
}

///|
fn owned(value : @source.Value) -> Cursor {
  admit(node(value), budget()).unwrap()
}

///|
test "admission validates all limits including directly constructed records" {
  for
    limits in [
      budget(nodes=-1),
      budget(depth=-1),
      budget(string_bytes=-1),
      budget(total_bytes=-1),
    ] {
    let error = rejection(admit(node(@source.Null), limits))
    assert_eq(error.kind, InvalidLimits)
    assert_eq(error.path, [])
    assert_eq(error.span, mark(0))
  }
  assert_eq(
    rejection(admit(node(@source.Null), budget(nodes=0))).kind,
    BudgetExceeded,
  )
  let zero_text = budget(nodes=1, depth=0, string_bytes=0, total_bytes=0)
  assert_true(admit(node(@source.Null), zero_text) is Ok(_))
  assert_eq(text(admit(node(@source.String("")), zero_text).unwrap()), Ok(""))
  assert_eq(
    rejection(admit(node(@source.String("a")), zero_text)).kind,
    BudgetExceeded,
  )
}

///|
test "node counts and container depth have inclusive independent boundaries" {
  let root = node(
    @source.Array([
      node(@source.Array([node(@source.Bool(true))])),
      node(@source.Null),
    ]),
  )
  assert_true(admit(root, budget(nodes=4, depth=2)) is Ok(_))
  assert_eq(rejection(admit(root, budget(nodes=3))).kind, BudgetExceeded)
  assert_eq(rejection(admit(root, budget(depth=1))).path, [@source.Index(0)])
  for value in [@source.Array([]), @source.Object([])] {
    assert_true(admit(node(value), budget(nodes=1, depth=1)) is Ok(_))
    assert_eq(
      rejection(admit(node(value), budget(depth=0))).kind,
      BudgetExceeded,
    )
  }
  // The minimum child count is checked before traversing a wide container.
  let wide = node(
    @source.Array(Array::make(10000, node(@source.Null))),
    start=7,
  )
  assert_eq(rejection(admit(wide, budget(nodes=10000))).span, mark(7))
  assert_true(admit(wide, budget(nodes=10001)) is Ok(_))
}

///|
test "keys and values charge raw UTF8 bytes per occurrence without normalization" {
  let root = node(
    @source.Object([
      entry("é", node(@source.String("😀"), start=10), start=2),
      entry("x", node(@source.String("e\u0301\r\n"), start=20), start=12),
    ]),
  )
  // Key/value charges: 2 + 4 + 1 + 5 = 12 bytes.
  assert_true(admit(root, budget(string_bytes=5, total_bytes=12)) is Ok(_))
  let per_string = rejection(admit(root, budget(string_bytes=4)))
  assert_eq(per_string.kind, BudgetExceeded)
  assert_eq(per_string.span, mark(20))
  let total = rejection(admit(root, budget(total_bytes=11)))
  assert_eq(total.kind, BudgetExceeded)
  assert_eq(total.path, [@source.Key("x")])
  let key_limit = rejection(admit(root, budget(total_bytes=1)))
  assert_eq(key_limit.span, mark(2))
  assert_eq(key_limit.path, [@source.Key("é")])
  let object = open_object(admit(root, budget()).unwrap()).unwrap()
  assert_eq(text(required(object, "x").unwrap()), Ok("e\u0301\r\n"))
  // U+0344 has two raw bytes; NFC would expand it to four.
  assert_true(
    admit(node(@source.String("\u0344")), budget(string_bytes=2, total_bytes=2))
    is Ok(_),
  )
}

///|
test "invalid Unicode and duplicate keys use key spans before their values" {
  let malformed = String::from_array([(0xD800).unsafe_to_char()])
  let key_error = rejection(
    admit(
      node(
        @source.Object([
          entry(malformed, node(@source.String(malformed), start=30), start=5),
        ]),
      ),
      budget(),
    ),
  )
  assert_eq(key_error.kind, InvalidUnicode)
  assert_eq(key_error.span, mark(5))
  let value_error = rejection(
    admit(
      node(@source.Array([node(@source.String(malformed), start=9)])),
      budget(),
    ),
  )
  assert_eq(value_error.kind, InvalidUnicode)
  assert_eq(value_error.path, [@source.Index(0)])
  assert_eq(value_error.span, mark(9))
  let duplicate = node(
    @source.Object([
      entry("a/~", node(@source.Null)),
      entry("a/~", node(@source.String(malformed), start=40), start=15),
    ]),
  )
  let error = rejection(admit(duplicate, budget()))
  assert_eq(error.kind, DuplicateField)
  assert_eq(error.path, [@source.Key("a/~")])
  assert_eq(error.span, mark(15))
  // Earlier invalid values precede later duplicate-key detection.
  let prior = node(
    @source.Object([
      entry("a", node(@source.String(malformed), start=8)),
      entry("a", node(@source.Null), start=20),
    ]),
  )
  assert_eq(rejection(admit(prior, budget())).span, mark(8))
  // Budget admission uses a lower bound before full Unicode validation.
  assert_eq(
    rejection(admit(node(@source.String(malformed)), budget(string_bytes=0))).kind,
    BudgetExceeded,
  )
}

///|
test "exact keys remain distinct even when canonical normalization would collide" {
  let root = owned(
    @source.Object([
      entry("e\u0301", node(@source.Number(1))),
      entry("é", node(@source.Number(2))),
      entry("x\r\n", node(@source.Null)),
      entry("x\n", node(@source.Null)),
    ]),
  )
  assert_eq(object_field_names(root), Ok(["e\u0301", "é", "x\r\n", "x\n"]))
}

///|
test "owned cursors are independent of input and returned collections" {
  let values = [node(@source.String("original"), start=11)]
  let fields = [entry("a", node(@source.Array(values)))]
  let root = admit(node(@source.Object(fields)), budget()).unwrap()
  let object = open_object(root).unwrap()
  let array = required(object, "a").unwrap()
  values[0] = node(@source.String("changed"))
  values.push(node(@source.Null))
  fields[0] = entry("other", node(@source.Bool(false)))
  fields.push(entry("extra", node(@source.Null)))
  let first = elements(array).unwrap()
  first[0] = root
  first.push(root)
  let names = object_field_names(root).unwrap()
  names[0] = "changed"
  names.push("extra")
  let child = elements(array).unwrap()[0]
  let path = cursor_path(child)
  path[0] = @source.Key("changed")
  assert_eq(text(child), Ok("original"))
  assert_eq(cursor_span(child), mark(11))
  assert_eq(cursor_path(child), [@source.Key("a"), @source.Index(0)])
  assert_eq(object_field_names(root), Ok(["a"]))
  assert_eq(elements(array).unwrap().length(), 1)
  guard view(array) is ArrayValue(shallow) else { fail("expected array view") }
  shallow[0] = root
  assert_eq(text(elements(array).unwrap()[0]), Ok("original"))
  let error = rejection(boolean(child))
  error.path[0] = @source.Key("changed")
  assert_eq(rejection(boolean(child)).path, [@source.Key("a"), @source.Index(0)])
}

///|
test "shared subtrees are copied and budgeted by occurrence" {
  let shared = node(@source.Array([node(@source.String("ab"))]))
  let root = node(@source.Array([shared, shared]))
  let cursor = admit(root, budget(nodes=5, depth=2, total_bytes=4)).unwrap()
  assert_eq(rejection(admit(root, budget(nodes=4))).kind, BudgetExceeded)
  assert_eq(rejection(admit(root, budget(total_bytes=3))).path, [
    @source.Index(1),
    @source.Index(0),
  ])
  let branches = elements(cursor).unwrap()
  assert_eq(cursor_path(elements(branches[0]).unwrap()[0]), [
    @source.Index(0),
    @source.Index(0),
  ])
  assert_eq(cursor_path(elements(branches[1]).unwrap()[0]), [
    @source.Index(1),
    @source.Index(0),
  ])
}

///|
test "cyclic input terminates through depth or node admission" {
  let items : Array[@source.Node] = []
  let root = node(@source.Array(items))
  items.push(root)
  let depth_error = rejection(admit(root, budget(depth=30)))
  assert_eq(depth_error.kind, BudgetExceeded)
  assert_eq(depth_error.path.length(), 30)
  let node_error = rejection(admit(root, budget(nodes=30)))
  assert_eq(node_error.kind, BudgetExceeded)
  // Release the caller's cycle; admission retained no borrowed tree.
  items[0] = node(@source.Null)
}

///|
test "deep admission navigation and issue paths are iterative" {
  let mut root = node(@source.String("leaf"), start=17)
  for index = 0; index < 10000; index = index + 1 {
    root = node(@source.Array([root]))
  }
  let mut cursor = admit(root, budget(nodes=10001, depth=10000)).unwrap()
  for index = 0; index < 10000; index = index + 1 {
    cursor = elements(cursor).unwrap()[0]
  }
  assert_eq(text(cursor), Ok("leaf"))
  let error = rejection(boolean(cursor))
  assert_eq(error.path.length(), 10000)
  assert_true(error.path.iter().all(segment => segment == @source.Index(0)))
  assert_eq(error.span, mark(17))
  assert_eq(rejection(admit(root, budget(depth=9999))).path.length(), 9999)
}
