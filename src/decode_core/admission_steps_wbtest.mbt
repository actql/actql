///|
fn budget(
  nodes? : Int = 1000,
  depth? : Int = 100,
  total_bytes? : Int = 10000,
) -> Limits {
  {
    max_nodes: nodes,
    max_depth: depth,
    max_string_bytes: 10000,
    max_total_string_bytes: total_bytes,
  }
}

///|
fn node(value : @source.Value) -> @source.Node {
  {
    value,
    span: {
      start_byte: 0,
      end_byte: 1,
      start_line: 1,
      end_line: 1,
      start_column: 1,
      end_column: 2,
      source_path: "steps.json",
    },
  }
}

///|
fn entry(key : String, value : @source.Node) -> @source.Field {
  { key, value, key_span: value.span, }
}

///|
test "resumable decode transfers one immutable tree without a completion copy" {
  let root = node(
    @source.Object([
      entry(
        "z",
        node(@source.Array([node(@source.Null), node(@source.Number(2))])),
      ),
      entry("a", node(@source.String("é"))),
    ]),
  )
  let admission = start_admission(root, budget()).unwrap()
  let mut result : Cursor? = None
  for _ in 0..<100 {
    match advance_admission(admission, 1).unwrap() {
      AdmissionContinue(work~) => assert_eq(work, 1)
      AdmissionComplete(cursor, work~) => {
        assert_eq(work, 1)
        result = Some(cursor)
        break
      }
      AdmissionFailed(_, ..) => fail("decode")
    }
  }
  let cursor = result.unwrap()
  assert_eq(admission_usage(cursor), {
    nodes: 5,
    depth: 2,
    largest_string_bytes: 2,
    total_string_bytes: 4,
  })
  assert_true(admission.tree.is_empty())
  cancel_admission(admission)
  cancel_admission(admission)
  assert_true(advance_admission(admission, 1) is Err(Terminal))
  let fields = open_object(cursor).unwrap()
  assert_eq(text(lookup(fields, "a").unwrap()), Ok("é"))
  let array = lookup(fields, "z").unwrap()
  assert_true(is_null(element_at(array, 0).unwrap()))
  assert_eq(finite_number(element_at(array, 1).unwrap()), Ok(2))
}

///|
test "resumable decode rejects duplicates and budget exhaustion before exposing a cursor" {
  let root = node(
    @source.Object([
      entry("p", node(@source.Null)),
      entry("p", node(@source.Number(7))),
    ]),
  )
  for bound in [budget(), budget(nodes=2), budget(total_bytes=0)] {
    let expected = admit(root, bound).unwrap_err()
    let admission = start_admission(root, bound).unwrap()
    let mut failed = false
    for _ in 0..<100 {
      match advance_admission(admission, 1).unwrap() {
        AdmissionContinue(work~) => assert_eq(work, 1)
        AdmissionComplete(_, ..) => fail("invalid tree admitted")
        AdmissionFailed(issue, work~) => {
          assert_eq(work, 1)
          assert_eq(issue, expected)
          failed = true
          break
        }
      }
    }
    assert_true(failed)
    assert_true(admission.tree.is_empty())
    assert_true(admission.work.is_empty())
  }
}
