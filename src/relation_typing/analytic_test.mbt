///|
fn analytic_body(functions : String, frame? : String? = None) -> String {
  let suffix = match frame {
    Some(f) => ",\"frame\":" + f
    None => ""
  }
  "{\"partition_by\":[\"id\",\"id\"],\"order_by\":[{\"amount\":\"asc\"}],\"functions\":" +
  functions +
  suffix +
  "}"
}

///|
fn current_frame() -> String {
  "{\"start\":\"current_row\",\"end\":\"current_row\"}"
}

///|
test "analytic pending indices retain exact call owners without confusing frame obligations" {
  let operation = checked(
    Analytic,
    analytic_body(
      "{\"z\":{\"fn\":\"sum\",\"expr\":\"amount\"},\"r\":{\"fn\":\"rank\"},\"a\":{\"fn\":\"sum\",\"expr\":\"amount\",\"filter\":\"flag\"}}",
      frame=Some(current_frame()),
    ),
  )
  let analytic = @relation_typing.analytic(operation).unwrap()
  assert_eq(@relation_typing.analytic_partition_count(analytic), 2)
  for i in 0..<2 {
    assert_true(
      @relation_typing.analytic_partition_at(analytic, i).unwrap().field
      is Unqualified("id"),
    )
  }
  assert_true(@relation_typing.analytic_partition_at(analytic, -1) is None)
  assert_true(@relation_typing.analytic_partition_at(analytic, 2) is None)
  let detached = @relation_typing.analytic_partition(analytic)
  detached.clear()
  assert_eq(@relation_typing.analytic_partition_count(analytic), 2)
  let count = @relation_typing.pending_validation_count(operation)
  let mut first = 0
  let mut last = 0
  for i in 0..<count {
    let pending = @relation_typing.pending_validation_at(operation, i).unwrap()
    let owner = @relation_typing.analytic_call_for_validation(analytic, i)
    match pending.kind {
      AggregateDemand | AggregateEnvelope | NumericAggregateObservation => {
        let owner = owner.unwrap()
        let ordinal = if owner.name == "a" {
          first += 1
          0
        } else {
          last += 1
          2
        }
        assert_true(
          physical_equal(
            owner,
            @relation_typing.analytic_call_at(analytic, ordinal).unwrap(),
          ),
        )
        assert_true(physical_equal(owner.source, pending.source))
        assert_true(owner.function is Aggregate(_))
      }
      _ => assert_true(owner is None)
    }
  }
  assert_eq(first, 3)
  assert_eq(last, 3)
  assert_true(
    @relation_typing.analytic_call_for_validation(analytic, -1) is None,
  )
  assert_true(
    @relation_typing.analytic_call_for_validation(analytic, count) is None,
  )
}

///|
test "analytic selection retains existing structured and reference domains" {
  let row = schema(
    "{\"id\":{\"type\":\"string\",\"nullable\":false},\"amount\":{\"type\":\"number\",\"nullable\":false},\"r\":{\"type\":\"resource_ref\",\"resource_kind\":\"file\",\"nullable\":false},\"obj\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"a\":{\"type\":\"number\",\"nullable\":true}}}}",
  )
  for name in ["lag", "lead", "first_value", "last_value"] {
    let frame = if name == "lag" || name == "lead" {
      None
    } else {
      Some(current_frame())
    }
    let body = analytic_body(
      "{\"v\":{\"fn\":\"" +
      name +
      "\",\"expr\":\"r\"},\"o\":{\"fn\":\"" +
      name +
      "\",\"expr\":\"obj\"}}",
      frame~,
    )
    let v = check_row(Analytic, cursor(body), row, None, limits()).unwrap()
    assert_true(
      @contract.type_equal(
        field(output_row(v), "v"),
        @contract.with_nullability(field(row, "r"), true),
        100,
      ),
    )
    assert_true(
      @contract.type_equal(
        field(output_row(v), "o"),
        @contract.with_nullability(field(row, "obj"), true),
        100,
      ),
    )
  }
}

///|
test "analytic ranking and navigation preserve input contracts and symbolic positions" {
  let v = checked(
    Analytic,
    analytic_body(
      "{\"r\":{\"fn\":\"rank\"},\"d\":{\"fn\":\"dense_rank\"},\"n\":{\"fn\":\"row_number\"},\"before\":{\"fn\":\"lag\",\"expr\":\"id\"},\"after\":{\"fn\":\"lead\",\"expr\":\"amount\",\"offset\":0}}",
    ),
  )
  let a = @relation_typing.analytic(v).unwrap()
  assert_eq(@relation_typing.analytic_partition(a).length(), 2)
  assert_eq(@relation_typing.analytic_order(a).length(), 1)
  assert_true(@relation_typing.analytic_frame(a) is None)
  for name in ["r", "d", "n"] {
    let c = field(output_row(v), name)
    assert_true(!c.nullable && c.shape is @contract.Number)
  }
  assert_true(field(output_row(v), "before").nullable)
  assert_true(!field(output_row(v), "id").nullable)
  let calls = @relation_typing.analytic_calls(a)
  assert_true(calls[0].function is Lead(offset=Literal(0L), ..))
  assert_true(calls[1].function is Lag(offset=Literal(1L), ..))
  calls.clear()
  assert_eq(@relation_typing.analytic_calls(a).length(), 5)
  assert_true(
    indexed_obligation_copy(
      @relation_typing.pending_validations(v),
      @relation_typing.pending_validation_count(v),
      i => @relation_typing.pending_validation_at(v, i),
      (a, b) => a.kind == b.kind && physical_equal(a.source, b.source),
    ).any(p => p.kind is AnalyticPositionOrder),
  )
  let ranks = checked(Analytic, analytic_body("{\"r\":{\"fn\":\"rank\"}}"))
  assert_true(
    !indexed_obligation_copy(
      @relation_typing.pending_validations(ranks),
      @relation_typing.pending_validation_count(ranks),
      i => @relation_typing.pending_validation_at(ranks, i),
      (a, b) => a.kind == b.kind && physical_equal(a.source, b.source),
    ).any(p => p.kind is AnalyticPositionOrder),
  )
}

///|
test "analytic frames share all aggregate signatures without aggregate-local orders" {
  for
    name in [
      "count", "count_if", "sum", "avg", "min", "max", "array_agg", "string_agg",
      "first", "last", "percentile_disc", "percentile_cont", "var_pop", "var_samp",
      "stddev_pop", "stddev_samp",
    ] {
    let arg = if name == "count_if" {
      "flag"
    } else if name == "string_agg" {
      "id"
    } else {
      "amount"
    }
    let extra = if name == "string_agg" {
      ",\"delimiter\":\",\""
    } else if name.has_prefix("percentile") {
      ",\"fraction\":0.5"
    } else {
      ""
    }
    let call = "{\"v\":{\"fn\":\"" +
      name +
      "\",\"expr\":\"" +
      arg +
      "\"" +
      extra +
      "}}"
    let v = checked(Analytic, analytic_body(call, frame=Some(current_frame())))
    assert_true(
      @relation_typing.analytic_calls(@relation_typing.analytic(v).unwrap())[0].function
      is Aggregate(_),
    )
    assert_eq(
      field(output_row(v), "v").nullable,
      !["count", "count_if", "array_agg"].contains(name),
    )
    assert_true(
      check_row(Analytic, cursor(analytic_body(call)), input(), None, limits())
      is Err({ kind: InvalidFrame, .. }),
    )
  }
  for name in ["first_value", "last_value"] {
    let v = checked(
      Analytic,
      analytic_body(
        "{\"v\":{\"fn\":\"" + name + "\",\"expr\":\"flag\"}}",
        frame=Some(current_frame()),
      ),
    )
    assert_true(field(output_row(v), "v").nullable)
  }
}

///|
test "analytic rejects nonlocal aliases and closed-call modifier violations" {
  for
    calls in [
      "{}", "{\"id\":{\"fn\":\"rank\"}}", "{\"a\":{\"fn\":\"lag\",\"expr\":\"id\"},\"b\":{\"fn\":\"lag\",\"expr\":\"a\"}}",
      "{\"r\":{\"fn\":\"rank\",\"distinct\":false}}", "{\"r\":{\"fn\":\"row_number\",\"filter\":\"TRUE\"}}",
      "{\"r\":{\"fn\":\"lag\",\"expr\":\"NULL\"}}", "{\"r\":{\"fn\":\"lag\",\"expr\":\"id\",\"offset\":-1}}",
    ] {
    assert_true(
      check_row(Analytic, cursor(analytic_body(calls)), input(), None, limits())
      is Err(_),
    )
  }
  for
    call in [
      "{\"r\":{\"fn\":\"rank\"}}", "{\"a\":{\"fn\":\"array_agg\",\"expr\":\"id\",\"order_by\":[{\"id\":\"asc\"}]}}",
      "{\"a\":{\"fn\":\"first_value\",\"expr\":\"id\",\"filter\":\"TRUE\"}}",
    ] {
    assert_true(
      check_row(
        Analytic,
        cursor(analytic_body(call, frame=Some(current_frame()))),
        input(),
        None,
        limits(),
      )
      is Err(_),
    )
  }
}

///|
test "frame boundaries compare exact offsets and reject structural inversions" {
  let call = "{\"v\":{\"fn\":\"count\"}}"
  for
    frame in [
      "{\"start\":\"unbounded_preceding\",\"end\":\"unbounded_following\"}",
      "{\"start\":{\"preceding\":9007199254740991},\"end\":{\"preceding\":1}}",
      "{\"start\":{\"following\":1},\"end\":{\"following\":9007199254740991}}",
      current_frame(),
    ] {
    ignore(checked(Analytic, analytic_body(call, frame=Some(frame))))
  }
  for
    frame in [
      "{\"start\":\"unbounded_following\",\"end\":\"unbounded_following\"}", "{\"start\":\"unbounded_preceding\",\"end\":\"unbounded_preceding\"}",
      "{\"start\":{\"preceding\":1},\"end\":{\"preceding\":2}}", "{\"start\":{\"following\":2},\"end\":{\"following\":1}}",
      "{\"start\":{\"following\":1},\"end\":\"current_row\"}", "{\"start\":{\"preceding\":0},\"end\":\"current_row\"}",
      "{\"start\":\"current_row\",\"end\":\"current_row\",\"type\":\"RANGE\"}",
    ] {
    assert_true(
      check_row(
        Analytic,
        cursor(analytic_body(call, frame=Some(frame))),
        input(),
        None,
        limits(),
      )
      is Err(_),
    )
  }
}

///|
test "symbolic frames preserve numeric and cross-boundary obligations" {
  let params = @parameter.read_declarations(
    Some(cursor("{\"n\":{\"type\":\"number\"},\"m\":{\"type\":\"number\"}}")),
    { max_parameters: 5, max_nodes: 30, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let body = analytic_body(
    "{\"v\":{\"fn\":\"count\"},\"x\":{\"fn\":\"lag\",\"expr\":\"id\",\"offset\":{\"$param\":\"n\"}}}",
    frame=Some(
      "{\"start\":{\"preceding\":{\"$param\":\"n\"}},\"end\":{\"preceding\":{\"$param\":\"m\"}}}",
    ),
  )
  let v = check_row(Analytic, cursor(body), input(), Some(params), limits()).unwrap()
  let pending = indexed_obligation_copy(
    @relation_typing.pending_validations(v),
    @relation_typing.pending_validation_count(v),
    i => @relation_typing.pending_validation_at(v, i),
    (a, b) => a.kind == b.kind && physical_equal(a.source, b.source),
  )
  assert_true(pending.any(p => p.kind is BoundFrameOrder))
  assert_true(pending.any(p => p.kind is BoundInteger(name="n", minimum=0L)))
  assert_true(pending.any(p => p.kind is BoundInteger(name="n", minimum=1L)))
}

///|
test "analytic argument budgets accumulate across calls without output materialization" {
  let body = cursor(
    analytic_body(
      "{\"a\":{\"fn\":\"sum\",\"expr\":\"amount+1\"},\"b\":{\"fn\":\"sum\",\"expr\":\"amount+1\",\"filter\":\"flag\"}}",
      frame=Some(current_frame()),
    ),
  )
  let v = check_row(Analytic, body, input(), None, limits()).unwrap()
  assert_eq(@relation_typing.binding_count(v), 3)
  let exact = {
    ..limits(),
    max_work: @relation_typing.work_used(v),
    max_nodes: @relation_typing.nodes_used(v),
    max_text_bytes: @relation_typing.text_bytes_used(v),
    max_tokens: @relation_typing.tokens_used(v),
  }
  assert_true(check_row(Analytic, body, input(), None, exact) is Ok(_))
  for
    l in [
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_nodes: exact.max_nodes - 1, },
      { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
      { ..exact, max_tokens: exact.max_tokens - 1, },
    ] {
    assert_true(check_row(Analytic, body, input(), None, l) is Err(_))
  }
}
