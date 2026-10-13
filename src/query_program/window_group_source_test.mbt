///|
fn window_group_source_seed() -> String {
  (
    #|{"values":{"schema":{"id":{"type":"number","nullable":false},"occurred_ms":{"type":"number","nullable":false},"cohort":{"type":"string","nullable":false},"amount":{"type":"number","nullable":true}},"rows":[{"id":1,"occurred_ms":0,"cohort":"a","amount":2},{"id":2,"occurred_ms":1,"cohort":"a","amount":3},{"id":3,"occurred_ms":60000,"cohort":"a","amount":null},{"id":4,"occurred_ms":60000,"cohort":"b","amount":4}]},"as":"records"}
  )
}

///|
fn window_group_source_context() -> Context {
  let seed = @wire.admit(
    @source.parse_json(
      window_group_source_seed(),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  {
    ..pair_context(),
    inputs: [
      {
        relation: [{ value: "records", quoted: false, }],
        name: "records",
        source: GeneratedValues(seed),
        visible_fields: ["id", "occurred_ms", "cohort", "amount"],
        graph_bindings: [],
      },
    ],
  }
}

///|
fn window_group_source_control(
  aggregates : String,
  ordered? : Bool = false,
  parameters? : Bool = false,
) -> @program.Program {
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.window_group\"," +
    (if parameters { "\"params\":{\"p\":{\"type\":\"number\"}}," } else { "" }) +
    "\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    window_group_source_seed() +
    (if ordered {
      ",{\"from\":\"records\",\"assert_rows\":{\"unique_by\":[\"id\"]},\"as\":\"keyed\"}"
    } else {
      ""
    }) +
    ",{\"from\":\"" +
    (if ordered { "keyed" } else { "records" }) +
    "\",\"row_window\":{\"kind\":\"fixed\",\"time\":\"occurred_ms\",\"size\":\"1m\"},\"as\":\"windowed\"},{\"from\":\"windowed\",\"window_group\":{\"by\":[\"cohort\"],\"aggregates\":" +
    aggregates +
    "},\"as\":\"grouped\"},{\"from\":\"grouped\",\"select\":[\"window_start\",\"window_end\",\"cohort\",\"n\",\"total\"]},{\"sort\":[{\"field\":\"window_start\",\"dir\":\"asc\",\"nulls\":\"first\"},{\"field\":\"window_end\",\"dir\":\"asc\",\"nulls\":\"first\"},{\"field\":\"cohort\",\"dir\":\"asc\",\"nulls\":\"first\"}],\"as\":\"out\"}],\"results\":{\"rows\":{\"from\":\"out\",\"fields\":[\"window_start\",\"window_end\",\"cohort\",\"n\",\"total\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "independent common window group control carries real boundary roles" {
  window_group_common_checked(
    window_group_source_control(
      "{\"n\":{\"fn\":\"count\"},\"total\":{\"fn\":\"sum\",\"field\":\"amount\"}}",
    ),
  )
}

///|
test "named window group field roles reach the existing common operation" {
  let actual = with_carrier_program(
    "FROM records AS r |> row_window(kind:'fixed',time:r.occurred_ms,size:'1m') |> window_group(by:[r.cohort],aggregates:{n:{fn:'count'},total:{fn:'sum',field:r.amount}}) |> SELECT window_start,window_end,cohort,n,total |> ORDER BY window_start,window_end,cohort",
    window_group_source_context(),
  ).unwrap()
  let control = window_group_source_control(
    "{\"n\":{\"fn\":\"count\"},\"total\":{\"fn\":\"sum\",\"field\":\"amount\"}}",
  )
  assert_eq(
    @json.parse(with_carrier_argument(actual, "window_group")),
    @json.parse(with_carrier_argument(control, "window_group")),
  )
  window_group_common_checked(actual)
}

///|
test "named window group expression and filter keep the original query AST" {
  let actual = with_carrier_program(
    "FROM records AS r |> row_window(kind:'fixed',time:r.occurred_ms,size:'1m') |> window_group(by:[r.cohort],aggregates:{n:{fn:'count'},total:{fn:'sum',expr:COALESCE(r.amount,0)+1,filter:r.amount IS NOT NULL,distinct:true}}) |> SELECT window_start,window_end,cohort,n,total |> ORDER BY window_start,window_end,cohort",
    window_group_source_context(),
  ).unwrap()
  let control = window_group_source_control(
    "{\"n\":{\"fn\":\"count\"},\"total\":{\"fn\":\"sum\",\"expr\":{\"add\":[{\"coalesce\":[{\"field\":\"amount\"},{\"literal\":0}]},{\"literal\":1}]},\"filter\":{\"not\":{\"is_null\":{\"field\":\"amount\"}}},\"distinct\":true}}",
  )
  assert_eq(
    @json.parse(with_carrier_argument(actual, "window_group")),
    @json.parse(with_carrier_argument(control, "window_group")),
  )
  window_group_common_checked(actual)
}

///|
fn window_group_common_checked(program : @program.Program) -> Unit raise {
  let source = @stage_parameters.prepare(program, {
    max_parameters: 100,
    max_nodes: 10000,
    max_depth: 100,
    max_text_bytes: 100000,
  }).unwrap()
  match
    @stage_results.check_local_program(source, {
      max_stages: 10,
      max_steps: 100,
      max_results: 100,
      max_work: 1000000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
      max_text_bytes: 100000,
    }) {
    Ok(_) => ()
    Err(Pipeline(stage, issue)) =>
      fail(
        "window group pipeline " +
        stage.to_string() +
        ": " +
        @debug.to_string(issue.kind),
      )
    Err(Order(stage, PipelineOrder(issue))) =>
      fail(
        "window group order " +
        stage.to_string() +
        ": " +
        @debug.to_string(issue.kind),
      )
    _ => fail("window group structural boundary")
  }
}

///|
test "named window group preserves all existing function-specific aggregate options" {
  for
    (authored, expected) in [
      ("{fn:'count',field:r.amount}", "{\"fn\":\"count\",\"field\":\"amount\"}"),
      (
        "{fn:'count_if',expr:r.amount>2}", "{\"fn\":\"count_if\",\"expr\":{\"gt\":[{\"field\":\"amount\"},{\"literal\":2}]}}",
      ),
      (
        "{fn:'avg',field:r.amount,distinct:true}", "{\"fn\":\"avg\",\"field\":\"amount\",\"distinct\":true}",
      ),
      ("{fn:'min',field:r.amount}", "{\"fn\":\"min\",\"field\":\"amount\"}"),
      ("{fn:'max',field:r.amount}", "{\"fn\":\"max\",\"field\":\"amount\"}"),
      (
        "{fn:'array_agg',field:r.amount,order_by:[{field:r.id,dir:'asc',nulls:'first'}],max_items:2,distinct:true}",
        "{\"fn\":\"array_agg\",\"field\":\"amount\",\"order_by\":[{\"field\":\"id\",\"dir\":\"asc\",\"nulls\":\"first\"}],\"max_items\":2,\"distinct\":true}",
      ),
      (
        "{fn:'string_agg',field:r.cohort,order_by:[{r.id:'asc'}],max_bytes:8,delimiter:',',distinct:true}",
        "{\"fn\":\"string_agg\",\"field\":\"cohort\",\"order_by\":[{\"id\":\"asc\"}],\"max_bytes\":8,\"delimiter\":\",\",\"distinct\":true}",
      ),
      (
        "{fn:'first',field:r.amount,order_by:[{r.id:'asc'}]}", "{\"fn\":\"first\",\"field\":\"amount\",\"order_by\":[{\"id\":\"asc\"}]}",
      ),
      (
        "{fn:'last',field:r.amount,order_by:[{r.id:'asc'}]}", "{\"fn\":\"last\",\"field\":\"amount\",\"order_by\":[{\"id\":\"asc\"}]}",
      ),
      (
        "{fn:'percentile_disc',field:r.amount,fraction:0.5}", "{\"fn\":\"percentile_disc\",\"field\":\"amount\",\"fraction\":0.5}",
      ),
      (
        "{fn:'percentile_cont',field:r.amount,fraction:0.5}", "{\"fn\":\"percentile_cont\",\"field\":\"amount\",\"fraction\":0.5}",
      ),
      (
        "{fn:'var_pop',field:r.amount}", "{\"fn\":\"var_pop\",\"field\":\"amount\"}",
      ),
      (
        "{fn:'var_samp',field:r.amount}", "{\"fn\":\"var_samp\",\"field\":\"amount\"}",
      ),
      (
        "{fn:'stddev_pop',field:r.amount}", "{\"fn\":\"stddev_pop\",\"field\":\"amount\"}",
      ),
      (
        "{fn:'stddev_samp',field:r.amount}", "{\"fn\":\"stddev_samp\",\"field\":\"amount\"}",
      ),
    ] {
    let ordered = authored.contains("order_by")
    let prefix = if ordered {
      "WITH keyed AS (FROM records |> ASSERT UNIQUE BY (id)) FROM keyed AS r"
    } else {
      "FROM records AS r"
    }
    let actual_result = with_carrier_program(
      prefix +
      " |> row_window(kind:'fixed',time:r.occurred_ms,size:'1m') |> window_group(by:[r.cohort],aggregates:{n:{fn:'count'},total:" +
      authored +
      "}) |> SELECT window_start,window_end,cohort,n,total |> ORDER BY window_start,window_end,cohort",
      window_group_source_context(),
    )
    let actual = match actual_result {
      Ok(program) => program
      Err(BindingPreparation(LocalProgram(Pipeline(_, issue)))) =>
        fail(authored + ": " + @debug.to_string(issue.kind))
      Err(BindingPreparation(LocalProgram(Order(_, PipelineOrder(issue))))) =>
        fail(authored + ": order " + @debug.to_string(issue.kind))
      Err(Expression(issue)) =>
        fail(authored + ": expression " + @debug.to_string(issue.issue))
      Err(UnknownColumn) => fail(authored + ": field scope")
      Err(InvalidQuery) => fail(authored + ": closed signature")
      Err(UnsupportedGraph) => fail(authored + ": Carrier dispatch")
      Err(UnsupportedProjection) => fail(authored + ": projection")
      Err(_) => fail(authored + ": other preparation boundary")
    }
    let control = window_group_source_control(
      "{\"n\":{\"fn\":\"count\"},\"total\":" + expected + "}",
      ordered~,
    )
    assert_eq(
      @json.parse(with_carrier_argument(actual, "window_group")),
      @json.parse(with_carrier_argument(control, "window_group")),
    )
    window_group_common_checked(control)
    window_group_common_checked(actual)
  }
}

///|
test "window aggregate ordering without key evidence remains a common refusal" {
  let actual = with_carrier_program(
    "FROM records AS r |> row_window(kind:'fixed',time:r.occurred_ms,size:'1m') |> window_group(by:[r.cohort],aggregates:{n:{fn:'count'},total:{fn:'array_agg',field:r.amount,order_by:[{field:r.id,dir:'asc',nulls:'first'}],max_items:2,distinct:true}}) |> SELECT window_start,window_end,cohort,n,total |> ORDER BY window_start,window_end,cohort",
    window_group_source_context(),
  )
  assert_true(
    actual
    is Err(
      BindingPreparation(
        LocalProgram(Order(_, PipelineOrder({ kind: UnresolvedOrder, .. })))
      )
    ),
  )
}

///|
test "window group does not manufacture boundary roles from ordinary fields" {
  for
    text in [
      "FROM records |> window_group(by:[cohort],aggregates:{n:{fn:'count'}}) |> SELECT n",
      "WITH fake AS (SELECT cohort,occurred_ms AS window_start,occurred_ms+1 AS window_end FROM records) FROM fake |> window_group(by:[cohort],aggregates:{n:{fn:'count'}}) |> SELECT n",
    ] {
    assert_true(
      with_carrier_program(text, window_group_source_context())
      is Err(
        BindingPreparation(
          LocalProgram(Pipeline(_, { kind: MissingWindowEvidence, .. }))
        )
      ),
    )
  }
}

///|
test "window group preserves function-specific common refusals" {
  for
    (body, expected) in [
      ("{fn:'countif',expr:r.amount>0}", @relation.InvalidAggregate("countif")),
      ("{fn:'SUM',field:r.amount}", @relation.InvalidAggregate("SUM")),
      (
        "{fn:'sum',field:r.amount,max_items:2}",
        @relation.InvalidAggregateOption("max_items"),
      ),
      (
        "{fn:'sum',field:r.amount,expr:r.amount+1}",
        @relation.InvalidAggregateArgument(
          "field and expr are mutually exclusive",
        ),
      ),
      ("{fn:'sum',field:r.amount,filter:r.amount}", @relation.ExpectedBoolean),
    ] {
    let actual = with_carrier_program(
      "FROM records AS r |> row_window(kind:'fixed',time:r.occurred_ms,size:'1m') |> window_group(by:[r.cohort],aggregates:{total:" +
      body +
      "}) |> SELECT total",
      window_group_source_context(),
    )
    guard actual
      is Err(
        BindingPreparation(
          LocalProgram(Pipeline(_, { kind: Operation(issue), .. }))
        )
      ) else {
      fail("expected common aggregate refusal")
    }
    assert_eq(issue, expected)
  }
}

///|
test "window aggregate expressions preserve Parameters and option guards" {
  let actual = with_carrier_program(
    "WITH keyed AS (FROM records |> ASSERT UNIQUE BY (id)) FROM keyed AS r |> row_window(kind:'fixed',time:r.occurred_ms,size:'1m') |> window_group(by:[r.cohort],aggregates:{n:{fn:'count'},total:{fn:'array_agg',expr:COALESCE(r.amount,0)+@p,filter:r.amount IS NOT NULL,order_by:[{field:r.id,dir:'asc',nulls:'first'}],max_items:@p}}) |> SELECT window_start,window_end,cohort,n,total |> ORDER BY window_start,window_end,cohort",
    {
      ..window_group_source_context(),
      parameter_declarations: Some(number_parameter_declarations()),
    },
  ).unwrap()
  let control = window_group_source_control(
    "{\"n\":{\"fn\":\"count\"},\"total\":{\"fn\":\"array_agg\",\"expr\":{\"add\":[{\"coalesce\":[{\"field\":\"amount\"},{\"literal\":0}]},{\"$param\":\"p\"}]},\"filter\":{\"not\":{\"is_null\":{\"field\":\"amount\"}}},\"order_by\":[{\"field\":\"id\",\"dir\":\"asc\",\"nulls\":\"first\"}],\"max_items\":{\"$param\":\"p\"}}}",
    ordered=true,
    parameters=true,
  )
  assert_eq(
    @json.parse(with_carrier_argument(actual, "window_group")),
    @json.parse(with_carrier_argument(control, "window_group")),
  )
  window_group_common_checked(control)
  window_group_common_checked(actual)
}

///|
test "public window source projection retains the existing input receiver" {
  for
    (argument, expected) in [
      ("field:r.amount", "{\"fn\":\"sum\",\"field\":\"amount\"}"),
      (
        "expr:COALESCE(r.amount,0)+1,filter:r.amount IS NOT NULL,distinct:true",
        "{\"fn\":\"sum\",\"expr\":{\"add\":[{\"coalesce\":[{\"field\":\"amount\"},{\"literal\":0}]},{\"literal\":1}]},\"filter\":{\"not\":{\"is_null\":{\"field\":\"amount\"}}},\"distinct\":true}",
      ),
    ] {
    let actual = with_carrier_program(
      "WITH raw AS (SELECT id, COALESCE(amount,0) AS occurred_ms, IF(id<=2,'a','b') AS cohort, amount FROM records) FROM raw AS r |> row_window(kind:'fixed',time:r.occurred_ms,size:'1m') |> window_group(by:[r.cohort],aggregates:{n:{fn:'count'},total:{fn:'sum'," +
      argument +
      "}}) |> SELECT window_start,window_end,cohort,n,total |> ORDER BY window_start,window_end,cohort",
      window_group_source_context(),
    ).unwrap()
    assert_eq(
      @json.parse(with_carrier_argument(actual, "window_group")),
      @json.parse(
        "{\"by\":[\"cohort\"],\"aggregates\":{\"n\":{\"fn\":\"count\"},\"total\":" +
        expected +
        "}}",
      ),
    )
    window_group_common_checked(actual)
  }
}

///|
test "public window output retains independent full schema including empty input" {
  for empty in [false, true] {
    let program = with_carrier_program(
      "WITH raw AS (SELECT id, COALESCE(amount,0) AS occurred_ms, IF(id<=2,'a','b') AS cohort, amount FROM records" +
      (if empty { " WHERE FALSE" } else { "" }) +
      ") FROM raw AS r |> row_window(kind:'fixed',time:r.occurred_ms,size:'1m') |> window_group(by:[r.cohort],aggregates:{n:{fn:'count'},total:{fn:'sum',field:r.amount}}) |> SELECT window_start,window_end,cohort,n,total |> ORDER BY window_start,window_end,cohort",
      window_group_source_context(),
    ).unwrap()
    let checked = match
      @check.check_parsed(
        program,
        graph_event_environment(),
        None,
        check_limits(),
      ) {
      Checked(checked) => checked
      Rejected(issue) => {
        graph_rows_rejected(issue)
        fail("window schema")
      }
      NeedsInputs(_) => fail("window schema uses a closed Values control")
    }
    let stage = @stage_results.stage_at(
      @check.checked_stage_results(checked),
      @program.stage_count(program) - 1,
    ).unwrap()
    let result = @relation_results.lookup(stage, "rows").unwrap()
    // Canonical object-schema ordering is separate from Result projection.
    // Assert the authored public order through its existing Result owner.
    assert_eq(@relation_results.fields(result), [
      "window_start", "window_end", "cohort", "n", "total",
    ])
    let schema = @relation_results.output_schema(result)
    assert_eq(
      @schema.fields(schema).map(field => @schema.field_reference_name(field)),
      ["cohort", "n", "total", "window_end", "window_start"],
    )
    for name in @relation_results.fields(result) {
      let field = @schema.lookup_reference(schema, name).unwrap()
      assert_eq(field.presence, @schema.Required)
      let expected = if name == "cohort" {
        "{\"type\":\"string\",\"nullable\":false,\"max_utf8_bytes\":1}"
      } else if name == "total" {
        "{\"type\":\"number\",\"nullable\":true}"
      } else {
        "{\"type\":\"number\",\"nullable\":false}"
      }
      assert_eq(
        @json.parse(
          @contract.stringify_checked(field.contract, 10000, 10000, 100),
        ),
        @json.parse(expected),
      )
    }
  }
}
