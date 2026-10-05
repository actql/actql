///|
fn membership_bound(
  left_type : String,
  list_type : String,
  left : String,
  list : String,
  op? : String = "in",
) -> @lower.BoundPrepared {
  let declarations = @parameter.read_declarations(
    Some(input_cursor("{\"x\":" + left_type + ",\"xs\":" + list_type + "}")),
    { max_parameters: 2, max_nodes: 100, max_depth: 20, max_text_bytes: 1000, },
  ).unwrap()
  let checked = @pipeline.check(
    input_cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"seed\"},{\"derive\":{\"v\":{\"" +
      op +
      "\":[{\"$param\":\"x\"},{\"$param\":\"xs\"}]}}}]",
    ),
    [],
    Some(declarations),
    None,
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let bindings = match
    @parameter.bind(
      declarations,
      Some(input_cursor("{\"x\":" + left + ",\"xs\":" + list + "}")),
      { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
    ).unwrap() {
    Ready(values) => values
    NeedsBindings(_) => abort("complete membership bindings")
  }
  let owner = @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    Some(bindings),
    max_parameters=2,
    max_name_bytes=3,
  ).unwrap()
  owner
}

///|
fn membership_lowered(
  left_type : String,
  list_type : String,
  left : String,
  list : String,
  op? : String = "in",
) -> @lower.Expression {
  let owner = membership_bound(left_type, list_type, left, list, op~)
  @lower.lower_expression(owner, 1, 0, {
    max_nodes: 1000,
    max_work: 100000,
    max_depth: 100,
    max_literal_nodes: 1000,
    max_literal_text_bytes: 10000,
  }).unwrap()
}

///|
fn membership_assert(actual : Value, expected : Bool?) -> Unit raise {
  match (actual, expected) {
    (Null, None) => ()
    (Boolean(actual), Some(expected)) => assert_eq(actual, expected)
    _ => fail("unexpected membership truth value")
  }
}

///|
test "membership shared frame distinguishes NULL arrays empty sets and NULL elements" {
  let scalar = "{\"type\":\"number\",\"nullable\":true}"
  let list_type = "{\"type\":\"array\",\"nullable\":true,\"items\":{\"type\":\"number\",\"nullable\":true}}"
  for
    (left, list, expected) in [
      ("1", "[]", Some(false)),
      ("null", "[]", Some(false)),
      ("1", "null", Some(false)),
      ("null", "null", Some(false)),
      ("null", "[1]", None),
      ("null", "[null]", None),
      ("1", "[1,null]", Some(true)),
      ("1", "[2,null]", None),
      ("1", "[2]", Some(false)),
      ("1", "[null,1,1]", Some(true)),
    ] {
    for op in ["in", "not_in"] {
      let expression = membership_lowered(scalar, list_type, left, list, op~)
      for drain in [false, true] {
        let logical = test_logical_budget(10000L, 1000L)
        let frame = expression_frame(
          expression,
          {},
          [],
          { remaining: 10000, max_frames: 100, },
          { limit: 1000, live: 0, peak: 0, },
          Some(expression_roots(logical, 100)),
        ).unwrap()
        while true {
          match advance_expression_frame(frame, drain~) {
            Ok(None) => ()
            Ok(Some(value)) => {
              membership_assert(
                value.value,
                expected.map(x => if op == "not_in" { !x } else { x }),
              )
              release_logical_root(logical, value.root.unwrap()).unwrap()
              break
            }
            Err(_) => fail("membership evaluation failed")
          }
        }
        assert_eq(logical.live, 0L)
        assert_eq(frame.workspace.live, 0)
      }
    }
  }
}

///|
test "membership equality retains exact decimal temporal and Unicode domains" {
  for
    (left_type, item_type, left, list, expected) in [
      (
        "{\"type\":\"decimal\",\"precision\":38,\"scale\":2}", "{\"type\":\"decimal\",\"precision\":38,\"scale\":3}",
        "\"1.00\"", "[\"1.001\",\"1.000\"]", true,
      ),
      (
        "{\"type\":\"decimal\",\"precision\":38,\"scale\":0}", "{\"type\":\"decimal\",\"precision\":38,\"scale\":0}",
        "\"99999999999999999999999999999999999999\"", "[\"99999999999999999999999999999999999998\"]",
        false,
      ),
      (
        "{\"type\":\"date\"}", "{\"type\":\"date\"}", "\"2026-10-05\"", "[\"2026-10-04\",\"2026-10-05\"]",
        true,
      ),
      (
        "{\"type\":\"timestamp\"}", "{\"type\":\"timestamp\"}", "\"2026-10-05T00:00:00.000Z\"",
        "[\"2026-10-05T00:00:00.001Z\"]", false,
      ),
      (
        "{\"type\":\"string\"}", "{\"type\":\"string\"}", "\"😀é\"", "[\"😀\",\"😀é\"]",
        true,
      ),
      (
        "{\"type\":\"boolean\"}", "{\"type\":\"boolean\"}", "true", "[false,true]",
        true,
      ),
    ] {
    let expression = membership_lowered(
      left_type,
      "{\"type\":\"array\",\"items\":" + item_type + "}",
      left,
      list,
    )
    membership_assert(
      evaluate_expression(expression, {}, [], {
        remaining: 10000,
        max_frames: 100,
      }).unwrap(),
      Some(expected),
    )
  }
}

///|
test "membership does not fold away demanded failures or missing row values" {
  assert_true(
    run_expr(
      "{\"in\":[{\"divide\":[{\"literal\":1},{\"literal\":0}]},{\"literal\":[]}]}",
    )
    is Err({ kind: Scalar(ArithmeticFailure), .. }),
  )
  assert_true(
    run_expr("{\"in\":[{\"field\":\"id\"},{\"literal\":[]}]}")
    is Err({ kind: MissingValue, .. }),
  )
}

///|
test "membership retains identical logical work before and after an early match" {
  for
    (source, expected) in [
      ("\"1 IN (1, 2, 3)\"", true),
      ("\"1 IN (2, 3, 1)\"", true),
      ("\"1 IN (2, 3, 4)\"", false),
    ] {
    // Three expression entries; scalar/list production and consumption each
    // charge 2 * (1 + 4), then one Boolean result: 3 + 10 + 1 = 14.
    let logical = test_logical_budget(14L, 100L)
    membership_assert(
      evaluate_entries(source, logical).unwrap(),
      Some(expected),
    )
    assert_eq(logical.work, 14L)
    assert_eq(logical.live, 0L)
    let short = test_logical_budget(13L, 100L)
    assert_true(evaluate_entries(source, short) is Err(_))
    assert_eq(short.live, 0L)
  }
}

///|
test "membership cancellation and control failure release only owned roots" {
  for advances in 1..<24 {
    let logical = test_logical_budget(1000L, 100L)
    let borrowed = retain_logical_value(logical, Number(9)).unwrap()
    let frame = expression_frame(
      lowered("\"1 IN (1, 2, 3, 4, 5)\""),
      {},
      [],
      { remaining: 1000, max_frames: 100, },
      { limit: 1000, live: 0, peak: 0, },
      Some(expression_roots(logical, 100)),
    ).unwrap()
    for _ in 0..<advances {
      match advance_expression_frame(frame) {
        Ok(None) => ()
        Ok(Some(value)) => {
          release_logical_root(logical, value.root.unwrap()).unwrap()
          break
        }
        Err(_) => fail("unexpected bounded membership failure")
      }
    }
    let work = logical.work
    close_expression_frame(frame)
    assert_eq(logical.work, work)
    assert_false(borrowed.released)
    assert_eq(logical.live, 1L)
    assert_eq(frame.workspace.live, 0)
    release_logical_root(logical, borrowed).unwrap()
  }
  for control in 0..<20 {
    let a = test_logical_budget(1000L, 100L)
    let b = test_logical_budget(1000L, 100L)
    let stepped = resume_test_expression(
      "\"1 IN (1, 2, 3)\"",
      a,
      1,
      max_control=control,
    )
    let drained = resume_test_expression(
      "\"1 IN (1, 2, 3)\"",
      b,
      1,
      drain=true,
      max_control=control,
    )
    match (stepped, drained) {
      (Err(x), Err(y)) => assert_eq(x.kind, y.kind)
      (Ok(x), Ok(y)) => {
        membership_assert(x.value, Some(true))
        membership_assert(y.value, Some(true))
        release_logical_root(a, x.root.unwrap()).unwrap()
        release_logical_root(b, y.root.unwrap()).unwrap()
      }
      _ => fail("suspension changed membership budget boundary")
    }
    assert_eq((a.work, a.live, a.failed), (b.work, b.live, b.failed))
  }
}

///|
test "membership comparison charges every variable width operand" {
  let expression = lowered("\"1 IN (1)\"")
  for
    (left, right, work) in [
      (Text("é😀"), Text("é😀"), 12),
      (decimal_value("1.00", 2), decimal_value("1.000", 3), 7),
    ] {
    let exact = { remaining: work, max_frames: 100, }
    membership_assert(
      membership_compare(exact, expression, left, right).unwrap(),
      Some(true),
    )
    assert_eq(exact.remaining, 0)
    let short = { remaining: work - 1, max_frames: 100, }
    assert_true(
      membership_compare(short, expression, left, right)
      is Err({ kind: ControlLimit, .. }),
    )
  }
}

///|
test "public scalar membership shares independent empty and NULL truth values" {
  let empty = Captured(@admitted.array_value([]))
  let only_null = Captured(@admitted.array_value([@admitted.null_value()]))
  let matches_null = Captured(
    @admitted.array_value([
      @admitted.number_value(1).unwrap(),
      @admitted.null_value(),
    ]),
  )
  let misses_null = Captured(
    @admitted.array_value([
      @admitted.number_value(2).unwrap(),
      @admitted.null_value(),
    ]),
  )
  let misses = Captured(
    @admitted.array_value([@admitted.number_value(2).unwrap()]),
  )
  for
    (left, right, expected) in [
      (Number(1), empty, Some(false)),
      (Null, empty, Some(false)),
      (Number(1), Null, Some(false)),
      (Null, Null, Some(false)),
      (Null, only_null, None),
      (Null, misses, None),
      (Number(1), only_null, None),
      (Number(1), matches_null, Some(true)),
      (Number(1), misses_null, None),
      (Number(1), misses, Some(false)),
    ] {
    membership_assert(binary(@lower.In, left, right).unwrap(), expected)
    membership_assert(
      binary(@lower.NotIn, left, right).unwrap(),
      expected.map(x => !x),
    )
  }
}

///|
test "nullable array parameter callers retain the exact nonnullable result contract" {
  for
    (left_type, item_type, extra, left) in [
      (
        "{\"type\":\"number\",\"nullable\":false}", "{\"type\":\"number\",\"nullable\":false}",
        "", "1",
      ),
      (
        "{\"type\":\"number\",\"nullable\":true}", "{\"type\":\"number\",\"nullable\":true}",
        ",\"max_items\":0", "null",
      ),
    ] {
    for list in ["null", "[]"] {
      for op in ["in", "not_in"] {
        let expression = membership_lowered(
          left_type,
          "{\"type\":\"array\",\"nullable\":true,\"items\":" +
          item_type +
          extra +
          "}",
          left,
          list,
          op~,
        )
        assert_false(@lower.expression_contract(expression).nullable)
        assert_true(
          @lower.expression_contract(expression).shape is @contract.Boolean,
        )
        membership_assert(
          evaluate_expression(expression, {}, [], {
            remaining: 10000,
            max_frames: 100,
          }).unwrap(),
          Some(op == "not_in"),
        )
      }
    }
  }
}

///|
test "membership backend admission compares scalar domains with array items" {
  for op in ["in", "not_in"] {
    let owner = membership_bound(
      "{\"type\":\"decimal\",\"precision\":8,\"scale\":2,\"nullable\":false}",
      "{\"type\":\"array\",\"nullable\":true,\"items\":{\"type\":\"decimal\",\"precision\":12,\"scale\":3,\"nullable\":false}}",
      "\"1.00\"",
      "[\"1.000\"]",
      op~,
    )
    let sequence = prepared_sequence(owner)
    let pipeline = @lower.prepare_fragment_pipeline(sequence, 1, {
      max_roots: 100,
      max_pointer_bytes: 10000,
      max_work: 100000,
    }).unwrap()
    let request = @lower.prepare_fragment_request(pipeline, 10L, 1000L).unwrap()
    assert_true(
      prepare_runtime_fragment(
        request,
        test_fragment_contract(),
        material_demands(),
        registry_limits(),
        capability_limits(),
      )
      is Ok(_),
    )
  }
}
