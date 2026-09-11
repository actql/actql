///|
fn nest_resolve(
  p : @pipeline_typing.CheckedPipeline,
  i : Int,
) -> @pipeline_typing.NestOrder {
  @pipeline_typing.resolve_nest_order(
    p,
    i,
    max_work=10000,
    max_text_bytes=10000,
  ).unwrap()
}

///|
test "nest order uses child evidence and never substitutes parent sequence" {
  let row = @schema.from_fields(
    [(Unqualified("id"), @contract.primitive(NumberType, nullable=false))],
    max_fields=1,
    max_name_bytes=2,
  ).unwrap()
  for parent in ["seed", "raw"] {
    for child in ["seed", "raw"] {
      for explicit in [false, true] {
        let order = if explicit {
          ",\"order_by\":[{\"id\":\"desc\"}]"
        } else {
          ""
        }
        let p = @pipeline_typing.check(
          cursor(
            "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":2},{\"id\":1},{\"id\":1}]},\"as\":\"seed\"},{\"nest\":{\"with\":\"" +
            child +
            "\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"into\":\"items\",\"fields\":[\"id\"]" +
            order +
            "},\"from\":\"" +
            parent +
            "\"}]",
          ),
          [("raw", row)],
          None,
          None,
          limits(),
        ).unwrap()
        let result = @pipeline_typing.resolve_nest_order(
          p,
          1,
          max_work=10000,
          max_text_bytes=10000,
        )
        if explicit && child == "raw" {
          assert_eq(result.unwrap_err().kind, UnresolvedOrder)
          assert_eq(result.unwrap_err().path, [@source.Index(1), Key("nest")])
        } else {
          let r = result.unwrap()
          assert_eq(
            @pipeline_typing.nest_order_child(r),
            if child == "seed" {
              Step(0)
            } else {
              Input(0)
            },
          )
          assert_eq(
            @pipeline_typing.nest_order_strategy(r),
            if explicit {
              Authored
            } else if child == "seed" {
              Inherited
            } else {
              ProjectedFields
            },
          )
          assert_eq(
            @pipeline_typing.nest_order_inherited(r) is Some(_),
            child == "seed",
          )
          assert_true(@pipeline_typing.nest_order_key(r) is None)
          assert_eq(
            @pipeline_typing.nest_order_term_count(r),
            if child == "seed" && !explicit {
              0
            } else {
              1
            },
          )
          if explicit {
            assert_true(
              @pipeline_typing.nest_order_term_at(r, 0).unwrap().authored,
            )
          }
          assert_true(@pipeline_typing.nest_order_term_at(r, -1) is None)
          assert_true(@pipeline_typing.nest_order_term_at(r, 2) is None)
          let (work, text) = @pipeline_typing.nest_order_usage(r)
          assert_true(
            @pipeline_typing.resolve_nest_order(
              p,
              1,
              max_work=work,
              max_text_bytes=text,
            )
            is Ok(_),
          )
          assert_true(
            @pipeline_typing.resolve_nest_order(
              p,
              1,
              max_work=work - 1,
              max_text_bytes=text,
            )
            is Err(_),
          )
          if text > 0 {
            assert_true(
              @pipeline_typing.resolve_nest_order(
                p,
                1,
                max_work=work,
                max_text_bytes=text - 1,
              )
              is Err(_),
            )
          }
        }
        assert_eq(
          @pipeline_typing.logical_order(p, Step(1)) is Some(_),
          parent == "seed",
        )
        assert_eq(
          @pipeline_typing.resolve_nest_order(
            p,
            0,
            max_work=10,
            max_text_bytes=10,
          ).unwrap_err().kind,
          InvalidBody,
        )
        assert_eq(
          @pipeline_typing.resolve_nest_order(
            p,
            -1,
            max_work=10,
            max_text_bytes=10,
          ).unwrap_err().kind,
          InvalidBody,
        )
        assert_eq(
          @pipeline_typing.resolve_nest_order(
            p,
            1,
            max_work=-1,
            max_text_bytes=10,
          ).unwrap_err().kind,
          InvalidLimits,
        )
      }
    }
  }
}

///|
test "nest key completion keeps hidden identity and recognizes projected aliases" {
  for term in ["a", "b", "x", ""] {
    let order = if term == "" {
      ""
    } else {
      ",\"order_by\":[{\"" + term + "\":\"desc\"}]"
    }
    let p = @pipeline_typing.check_carriers(
      cursor(
        "[{\"time_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:00.010Z\",\"step\":1},\"as\":\"grid\"},{\"derive\":{\"x\":{\"literal\":1}}},{\"select\":[{\"a\":\"time\"},{\"b\":\"time\"},\"x\"],\"as\":\"child\"},{\"nest\":{\"with\":\"child\",\"on\":[{\"left\":\"a\",\"right\":\"b\"}],\"into\":\"items\",\"fields\":[\"x\"]" +
        order +
        "}}]",
      ),
      [],
      None,
      None,
      limits(),
    ).unwrap()
    let r = nest_resolve(p, 3)
    if term == "" {
      assert_eq(@pipeline_typing.nest_order_strategy(r), Inherited)
      assert_true(@pipeline_typing.nest_order_key(r) is None)
    } else {
      assert_eq(@pipeline_typing.nest_order_strategy(r), Authored)
      assert_true(@pipeline_typing.nest_order_key(r) is Some(_))
      assert_true(@pipeline_typing.nest_order_inherited(r) is None)
      assert_eq(
        @pipeline_typing.nest_order_term_count(r),
        if term == "x" {
          2
        } else {
          1
        },
      )
      if term == "x" {
        let hidden = @pipeline_typing.nest_order_term_at(r, 1).unwrap()
        assert_eq(hidden.field, Unqualified("a"))
        assert_true(!hidden.authored)
      }
    }
  }
}

///|
test "nest omitted order follows declared projection rather than schema name order" {
  let p = join_pipeline(
    "[{\"nest\":{\"with\":\"r\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"into\":\"items\",\"fields\":[{\"z\":\"id\"},{\"a\":\"amount\"}]},\"from\":\"l\"}]",
  ).unwrap()
  let r = nest_resolve(p, 0)
  assert_eq(@pipeline_typing.nest_order_strategy(r), ProjectedFields)
  assert_eq(
    @pipeline_typing.nest_order_term_at(r, 0).unwrap().field,
    Unqualified("id"),
  )
  assert_eq(
    @pipeline_typing.nest_order_term_at(r, 1).unwrap().field,
    Unqualified("amount"),
  )
  let consumer = @pipeline_typing.nest_order_consumer(r)
  guard consumer.operation is @pipeline_typing.Nest(checked~, ..) else {
    abort("expected nest")
  }
  assert_true(
    @nest.pending_validations(checked).contains(@nest.ResolveTotalOrder),
  )
  assert_true(
    @nest.pending_validations(checked).contains(@nest.ResolveNestedEnvelope),
  )
}

///|
test "nest hidden child key orders structured payload but unordered structure cannot be a fallback" {
  let number = @contract.primitive(NumberType, nullable=false)
  let row = @schema.from_fields(
    [
      (Unqualified("id"), number),
      (
        Unqualified("payload"),
        @contract.array_contract(number, nullable=false).unwrap(),
      ),
    ],
    max_fields=2,
    max_name_bytes=20,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(row))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), carrier, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  let source = cursor(
    "[{\"nest\":{\"with\":\"rows\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"into\":\"items\",\"fields\":[\"payload\"]}}]",
  )
  let raw = @pipeline_typing.check_carriers(
    source,
    [("rows", carrier)],
    None,
    None,
    limits(),
  ).unwrap()
  let issue = @pipeline_typing.resolve_nest_order(
    raw,
    0,
    max_work=10000,
    max_text_bytes=10000,
  ).unwrap_err()
  assert_eq(issue.kind, UnresolvedOrder)
  assert_eq(issue.path, [@source.Index(0), Key("nest"), Key("fields"), Index(0)])
  let p = @pipeline_typing.check_with_evidence(
    source,
    [("rows", @pipeline_typing.KeyedInput(key))],
    None,
    None,
    limits(),
  ).unwrap()
  let r = nest_resolve(p, 0)
  assert_eq(@pipeline_typing.nest_order_strategy(r), CandidateKey)
  assert_true(@pipeline_typing.nest_order_key(r) is Some(_))
  assert_true(@pipeline_typing.nest_order_inherited(r) is None)
  assert_eq(
    @pipeline_typing.nest_order_term_at(r, 0).unwrap().field,
    Unqualified("id"),
  )
  assert_true(@pipeline_typing.logical_order(p, Step(0)) is None)
  let (work, text) = @pipeline_typing.nest_order_usage(r)
  assert_true(
    @pipeline_typing.resolve_nest_order(
      p,
      0,
      max_work=work,
      max_text_bytes=text,
    )
    is Ok(_),
  )
  assert_true(
    @pipeline_typing.resolve_nest_order(
      p,
      0,
      max_work=work - 1,
      max_text_bytes=text,
    )
    is Err(_),
  )
  assert_true(
    @pipeline_typing.resolve_nest_order(
      p,
      0,
      max_work=work,
      max_text_bytes=text - 1,
    )
    is Err(_),
  )
}
