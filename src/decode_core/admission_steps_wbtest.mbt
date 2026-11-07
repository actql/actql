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
test "decode yields within long Text and preserves exact byte accounting" {
  let value = String::make(257, 'é') + "😀"
  // 257 two-byte scalars and one four-byte scalar; no key bytes.
  for total in [518, 517] {
    let admission = start_admission(
      node(@source.String(value)),
      budget(total_bytes=total),
    ).unwrap()
    let mut polls = 0
    let mut terminal = false
    for _ in 0..<100 {
      polls += 1
      match advance_admission(admission, 1).unwrap() {
        AdmissionContinue(work~) => assert_eq(work, 1)
        AdmissionComplete(cursor, ..) => {
          assert_eq(total, 518)
          assert_eq(text(cursor), Ok(value))
          assert_eq(admission_usage(cursor).total_string_bytes, 518)
          terminal = true
          break
        }
        AdmissionFailed(issue, ..) => {
          assert_eq(total, 517)
          assert_eq(issue.kind, BudgetExceeded)
          terminal = true
          break
        }
      }
    }
    assert_true(terminal && polls >= 5)
    assert_true(admission.text is None)
    assert_true(admission.tree.is_empty())
    assert_true(admission.work.is_empty())
  }
  let admission = start_admission(node(@source.String(value)), budget()).unwrap()
  assert_true(advance_admission(admission, 1) is Ok(AdmissionContinue(..)))
  assert_true(advance_admission(admission, 1) is Ok(AdmissionContinue(..)))
  assert_true(admission.text is Some(_))
  cancel_admission(admission)
  assert_true(admission.text is None && admission.work.is_empty())
  assert_true(advance_admission(admission, 1) is Err(Terminal))
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

///|
test "key admission maps follow active ancestors rather than completed siblings" {
  let siblings = node(
    @source.Array([
      node(@source.Object([entry("a", node(@source.Number(1.0)))])),
      node(@source.Object([entry("b", node(@source.Number(2.0)))])),
      node(@source.Object([entry("c", node(@source.Number(3.0)))])),
    ]),
  )
  let admission = start_admission(siblings, budget()).unwrap()
  let mut peak = 0
  while true {
    let mut live = 0
    for frame in admission.work {
      if frame is ObjectNext(_, _, _, _, _) {
        live += 1
      }
    }
    peak = Int::max(peak, live)
    match advance_admission(admission, 1).unwrap() {
      AdmissionContinue(..) => ()
      AdmissionComplete(cursor, ..) => {
        assert_eq(admission_usage(cursor).nodes, 7)
        assert_eq(peak, 1)
        assert_true(admission.work.is_empty())
        break
      }
      AdmissionFailed(_, ..) => fail("Original sibling admission changed")
    }
  }
  let shallow = admission_construction_inventory(7, 3, 3, 1, 2).unwrap()
  let active = @shape.key_admission_construction_extent(2, 3).unwrap()
  assert_eq(shallow.keys.record_headers, active.record_headers)
  assert_eq(shallow.keys.reference_slots, active.reference_slots)
  assert_eq(shallow.keys.scalar_words, active.scalar_words)
}
