///|
fn pinned_graph(g : @carrier.Carrier) -> @graph_contract.CheckedContract {
  @graph_contract.admit(g, {
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 1000,
  }).unwrap()
}

///|
fn delta_rows(t : @contract.Contract?) -> @carrier.Carrier {
  @carrier.relation(
    @carrier.rows(
      [(Unqualified("change"), t)],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=6,
    ).unwrap(),
  )
}

///|
test "qualified delta fields and incompatible complete record domains" {
  let number = @contract.primitive(NumberType, nullable=false)
  let base = complete_graph(number, number, "a")
  let expected = pinned_graph(base)
  let rows = @carrier.relation(
    @carrier.rows(
      [
        (
          Qualified(Left, "change"),
          Some(@contract.primitive(JsonType, nullable=true)),
        ),
        (Qualified(Right, "change"), Some(number)),
      ],
      field_set=Open,
      max_fields=2,
      max_name_bytes=100,
    ).unwrap(),
  )
  assert_true(
    @graph_typing.check_apply(
      cursor("{\"with\":\"d\",\"field\":\"left.change\"}"),
      base,
      rows,
      expected,
      limits(),
    )
    is Ok(_),
  )
  assert_true(
    @graph_typing.check_apply(
      cursor("{\"with\":\"d\",\"field\":\"right.change\"}"),
      base,
      rows,
      expected,
      limits(),
    )
    is Err({ kind: InvalidDeltaType, .. }),
  )
  assert_true(
    @graph_typing.check_apply(
      cursor("{\"with\":\"d\",\"field\":\"change\"}"),
      base,
      rows,
      expected,
      limits(),
    )
    is Err({ kind: UnknownDeltaField("change"), .. }),
  )
  let empty = @contract.object_contract(
    [],
    nullable=false,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  assert_true(
    @graph_typing.check_apply(
      cursor("{\"with\":\"d\",\"field\":\"change\"}"),
      base,
      delta_rows(Some(empty)),
      expected,
      limits(),
    )
    is Err({ kind: ContractMismatch(_), .. }),
  )
}

///|
test "typed diff feeds apply without turning contract evidence into snapshot proof" {
  let id = @contract.decimal_contract(20, 3, nullable=false).unwrap()
  let base = complete_graph(
    id,
    @contract.primitive(StringType, nullable=false),
    "a",
  )
  let target = complete_graph(
    id,
    @contract.primitive(StringType, nullable=true),
    "b",
  )
  let diff = @graph_typing.check_diff(
    cursor("{\"with\":\"target\"}"),
    base,
    target,
    limits(),
  ).unwrap()
  let expected = @graph_typing.diff_graph_contract(diff)
  let input = delta_rows(Some(@graph_typing.diff_contract(diff)))
  let source = cursor("{\"with\":\"deltas\",\"field\":\"change\"}")
  let checked = @graph_typing.check_apply(
    source,
    base,
    input,
    expected,
    limits(),
  ).unwrap()
  assert_eq(@graph_typing.apply_with_name(checked), "deltas")
  assert_eq(@graph_typing.apply_field(checked), "change")
  assert_eq(
    @graph_contract.cid(@graph_typing.apply_graph_contract(checked)),
    @graph_contract.cid(expected),
  )
  assert_eq(
    @graph_contract.cid(pinned_graph(@graph_typing.apply_output(checked))),
    @graph_contract.cid(expected),
  )
  let pending = @graph_typing.apply_pending(checked)
  for
    required in [
      @graph_typing.RequireExactlyOneDeltaRow,
      @graph_typing.MatchPinnedGraphContract,
      @graph_typing.MatchExactBaseIdentity,
      @graph_typing.MatchExactTargetIdentity,
      @graph_typing.ValidateExactBeforeRecords,
      @graph_typing.ValidateResultEndpointsAndContract,
    ] {
    assert_true(pending.contains(required))
  }
  pending.clear()
  assert_eq(@graph_typing.apply_pending(checked).length(), 14)
  let u = @graph_typing.apply_usage(checked)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(
    @graph_typing.check_apply(source, base, input, expected, exact) is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @graph_typing.check_apply(source, base, input, expected, cap)
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
}

///|
test "JSON delta admission is deferred but wrong carriers and known incompatible types fail" {
  let number = @contract.primitive(NumberType, nullable=false)
  let base = complete_graph(number, number, "a")
  let expected = pinned_graph(base)
  let source = cursor("{\"with\":\"deltas\",\"field\":\"change\"}")
  let json = delta_rows(Some(@contract.primitive(JsonType, nullable=true)))
  assert_true(
    @graph_typing.check_apply(source, base, json, expected, limits()) is Ok(_),
  )
  assert_true(
    @graph_typing.check_apply(
      source,
      base,
      delta_rows(Some(number)),
      expected,
      limits(),
    )
    is Err({ kind: InvalidDeltaType, .. }),
  )
  assert_true(
    @graph_typing.check_apply(
      source,
      base,
      delta_rows(None),
      expected,
      limits(),
    )
    is Err({ kind: UntypedDeltaField("change"), .. }),
  )
  assert_true(
    @graph_typing.check_apply(source, base, base, expected, limits())
    is Err({ kind: WrongCarrier(GraphKind), .. }),
  )
  assert_true(
    @graph_typing.check_apply(source, json, json, expected, limits())
    is Err({ kind: WrongCarrier(RelationKind), .. }),
  )
  let incompatible = complete_graph(
    @contract.primitive(StringType, nullable=false),
    number,
    "a",
  )
  assert_true(
    @graph_typing.check_apply(source, incompatible, json, expected, limits())
    is Err({ kind: ContractMismatch(_), .. }),
  )
  let incomplete = @carrier.unknown_carrier(GraphKind)
  assert_true(
    @graph_typing.check_apply(source, incomplete, json, expected, limits())
    is Err({ kind: IncompleteGraph, .. }),
  )
}

///|
test "apply body is closed and field diagnostics retain their source position" {
  let number = @contract.primitive(NumberType, nullable=false)
  let base = complete_graph(number, number, "a")
  let expected = pinned_graph(base)
  let rows = delta_rows(Some(@contract.primitive(JsonType, nullable=false)))
  for
    text in [
      "{}", "{\"with\":\"d\"}", "{\"with\":\"d\",\"field\":\"change\",\"extra\":1}",
      "{\"with\":\"\",\"field\":\"change\"}",
    ] {
    assert_true(
      @graph_typing.check_apply(cursor(text), base, rows, expected, limits())
      is Err(_),
    )
  }
  let result = @graph_typing.check_apply(
    cursor("{\"with\":\"d\",\"field\":\"missing\"}"),
    base,
    rows,
    expected,
    limits(),
  )
  guard result is Err(e) else { fail("expected missing field") }
  assert_true(e.kind is UnknownDeltaField("missing"))
  assert_eq(e.path, [@source.Key("field")])
}
