///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 1000,
    }).unwrap(),
    {
      max_nodes: 100000,
      max_depth: 1000,
      max_string_bytes: 1000000,
      max_total_string_bytes: 1000000,
    },
  ).unwrap()
}

///|
fn collected(steps : String) -> @collection.Collected {
  let root = cursor(steps)
  let declarations = @parameter.read_declarations(
    Some(cursor("{\"n\":{\"type\":\"number\",\"default\":2}}")),
    { max_parameters: 10, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let schema = @schema.from_fields(
    [
      (
        @schema.Unqualified("amount"),
        @contract.primitive(@contract.NumberType, nullable=false),
      ),
    ],
    max_fields=10,
    max_name_bytes=100,
  ).unwrap()
  let pipeline = @pipeline.check(
    root,
    [("rows", schema)],
    Some(declarations),
    None,
    {
      max_steps: 100,
      max_work: 1000000,
      max_nodes: 100000,
      max_depth: 1000,
      max_text_bytes: 1000000,
      max_tokens: 10000,
    },
  ).unwrap()
  @collection.collect(root, pipeline, {
    max_work: 1000000,
    max_slots: 1000,
    max_references: 1000,
    max_pointer_units: 100000,
    max_direct_text_bytes: 100000,
  }).unwrap()
}

///|
fn rendered(steps : Steps) -> String raise @encode.EncodeFailure {
  let writer = @encode.writer(1000000, 100000, 1000)
  emit(steps, writer)
  @encode.finish(writer)
}

///|
test "step source replaces complete expression slots and retains unbound direct operands" {
  let owner = collected(
    (
      #|[{"derive":{"y":"$n + $n"},"as":"unused","meta":{"note":"omit"}},{"take":{"$param":"n"},"from":"rows","meta":{"$param":"annotation"}}]
    ),
  )
  let steps = prepare(owner, max_work=100000).unwrap()
  assert_true(physical_equal(collection(steps), owner))
  assert_eq(
    rendered(steps),
    (
      #|[{"as":"unused","derive":{"y":{"add":[{"$param":"n"},{"$param":"n"}]}}},{"from":"rows","take":{"$param":"n"}}]
    ),
  )
  let same = prepare(
    collected(
      (
        #|[{"as":"unused","derive":{"y":{"add":[{"$param":"n"},{"$param":"n"}]}}},{"from":"rows","take":{"$param":"n"}}]
      ),
    ),
    max_work=100000,
  ).unwrap()
  assert_eq(rendered(steps), rendered(same))
  assert_true(!physical_equal(collection(steps), collection(same)))
  let exact = work(steps)
  assert_eq(rendered(prepare(owner, max_work=exact).unwrap()), rendered(steps))
  assert_true(prepare(owner, max_work=exact - 1) is Err(WorkLimit))
  assert_true(prepare(owner, max_work=-1) is Err(InvalidLimits))
}

///|
test "step metadata exclusion does not descend into expression business data" {
  let steps = prepare(
    collected(
      (
        #|[{"derive":{"payload":{"literal":{"meta":"keep","literal":{"$param":"not a hole"}}}},"meta":{"note":"omit"}}]
      ),
    ),
    max_work=100000,
  ).unwrap()
  assert_eq(
    rendered(steps),
    (
      #|[{"derive":{"payload":{"literal":{"literal":{"$param":"not a hole"},"meta":"keep"}}}}]
    ),
  )
}

///|
test "ordered derive keeps its array shape and shadowed slots without completion" {
  let steps = prepare(
    collected(
      (
        #|[{"derive":[{"amount":"amount + 1"},{"y":"amount + $n"}],"meta":{"note":"omit"}},{"select":["y"]},{"derive":{}},{"sort":[]}]
      ),
    ),
    max_work=100000,
  ).unwrap()
  assert_eq(
    rendered(steps),
    (
      #|[{"derive":[{"amount":{"add":[{"field":"amount"},{"literal":1}]}},{"y":{"add":[{"field":"amount"},{"$param":"n"}]}}]},{"select":["y"]},{"derive":{}},{"sort":[]}]
    ),
  )
  assert_eq(rendered(prepare(collected("[]"), max_work=1).unwrap()), "[]")
}

///|
test "source emission shares enclosing sink limits and has no partial successful output" {
  let steps = prepare(
    collected("[{\"filter\":\"amount > 0\"}]"),
    max_work=100000,
  ).unwrap()
  let expected = "[{\"filter\":{\"gt\":[{\"field\":\"amount\"},{\"literal\":0}]}}]"
  assert_eq(rendered(steps), expected)
  for nodes in [7, 8, 9] {
    for depth in [4, 5, 6] {
      let accepted = try {
        let writer = @encode.hashing_writer(expected.length(), nodes, depth)
        emit(steps, writer)
        // Fixed SHA-256 computed independently with Node crypto.
        assert_eq(
          @encode.finish_hash(writer),
          "b8c091e30811e741369d0c24dc47d0cf2f916192e4075e9ffc918e6325af9ac6",
        )
        true
      } catch {
        _ => false
      }
      assert_eq(accepted, nodes >= 8 && depth >= 5)
    }
  }
  for cap in [expected.length() - 1, expected.length(), expected.length() + 1] {
    let writer = @encode.writer(cap, 100, 100)
    let accepted = try {
      emit(steps, writer)
      assert_eq(@encode.finish(writer), expected)
      true
    } catch {
      _ => false
    }
    assert_eq(accepted, cap >= expected.length())
    let measured = try {
      let writer = @encode.measuring_writer(cap, 100, 100)
      emit(steps, writer)
      assert_eq(@encode.finish_measurement(writer), expected.length())
      true
    } catch {
      _ => false
    }
    assert_eq(measured, accepted)
    if !accepted {
      let closed = try {
        @encode.finish(writer) |> ignore
        false
      } catch {
        @encode.ClosedWriter => true
        _ => false
      }
      assert_true(closed)
    }
  }
}
