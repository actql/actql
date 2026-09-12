///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 4096,
      max_nodes: 100,
      max_depth: 20,
    }).unwrap(),
    {
      max_nodes: 100,
      max_depth: 20,
      max_string_bytes: 4096,
      max_total_string_bytes: 4096,
    },
  ).unwrap()
}

///|
fn policy() -> @policy.Policy {
  let fields = [
    "max_aggregate_array_items", "max_artifact_bytes", "max_artifact_rows", "max_effect_items",
    "max_graph_input_edges", "max_graph_input_nodes", "max_graph_output_rows", "max_graph_paths",
    "max_infer_items", "max_model_input_tokens_per_item", "max_model_request_bytes_per_item",
    "max_model_total_duration_ms", "max_nested_value_bytes", "max_nested_value_depth",
    "max_relation_output_rows", "max_temporal_matches_per_key", "max_temporal_output_rows",
  ]
  @policy.admit(
    @utf8.encode(
      "{" +
      fields.map(name => "\"" + name + "\":1").join(",") +
      ",\"version\":\"actql-capacity-host-policy/0.1\"}",
    ),
    "sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63",
    { max_bytes: 4096, max_nodes: 100, max_depth: 4, },
  ).unwrap()
}

///|
fn pipeline(
  inputs : Array[(String, @pipeline.InputContract)],
  parameters? : @parameter.Declarations? = None,
  steps? : String = "[]",
) -> @pipeline.CheckedPipeline {
  @pipeline.check_with_evidence(
    cursor(steps),
    inputs,
    parameters,
    Some(cursor("\"a\"")),
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
}

///|
fn base(
  keyed : Bool,
  parameters? : @parameter.Declarations? = None,
  steps? : String = "[]",
) -> @pipeline.CheckedPipeline {
  let rows = @carrier.relation(
    @carrier.typed_rows(
      @schema.from_object(
        @contract.object_contract(
          [
            (
              "id",
              @contract.primitive(
                if keyed {
                  NumberType
                } else {
                  JsonType
                },
                nullable=false,
              ),
            ),
          ],
          nullable=false,
          max_fields=1,
          max_name_bytes=2,
        ).unwrap(),
      ).unwrap(),
    ),
  )
  let input = if keyed {
    @pipeline.KeyedInput(
      @evidence.declare_primary_key(cursor("[\"id\"]"), rows, {
        max_fields: 1,
        max_name_bytes: 2,
      }).unwrap(),
    )
  } else {
    @pipeline.CarrierInput(rows)
  }
  pipeline([("a", input)], parameters~, steps~)
}

///|
fn results(p : @pipeline.CheckedPipeline) -> @results.CheckedResults {
  @results.check(p, cursor("{\"out\":{\"from\":\"a\",\"fields\":[\"id\"]}}"), {
    max_results: 1,
    max_work: 1000,
    max_nodes: 100,
    max_text_bytes: 1000,
    max_depth: 20,
  }).unwrap()
}

///|
fn empty_capacity_sources() -> @host.HostSources {
  let mixed = @wire.check_mixed_claims([], [], {
    max_entities: 0,
    max_references: 0,
    max_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
  }).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, [], {
    max_witnesses: 0,
    max_references: 0,
  }).unwrap()
  @host.bind_claim_sources(claims, [], {
    max_entries: 0,
    max_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
  }).unwrap()
}

///|
fn capacity(
  p : @pipeline.CheckedPipeline,
  capacity_policy? : @policy.Policy = policy(),
) -> @capacity.ApplicationCoverage {
  @capacity.prepare_application_coverage(
    p,
    empty_capacity_sources(),
    capacity_policy,
    [],
    {
      max_work: 1000,
      max_name_bytes: 100,
      max_input_work: 1000,
      max_operand_work: 1000,
    },
  ).unwrap()
}

///|
fn limits() -> @pipeline_check_context.Limits {
  { max_steps: 0, max_results: 1, max_work: 10000, max_text_bytes: 10000, }
}

///|
test "later producer bindings must belong to the retained declaration owner" {
  let declaration_limits : @parameter.DeclarationLimits = {
    max_parameters: 1,
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 1000,
  }
  let body = cursor("{\"n\":{\"type\":\"number\",\"default\":7}}")
  let declarations = @parameter.read_declarations(
    Some(body),
    declaration_limits,
  ).unwrap()
  let foreign = @parameter.read_declarations(Some(body), declaration_limits).unwrap()
  guard @parameter.bind(declarations, None, {
      max_nodes: 100,
      max_depth: 10,
      max_text_bytes: 1000,
    }).unwrap()
    is Ready(values) else {
    fail("missing default binding")
  }
  guard @parameter.bind(foreign, None, {
      max_nodes: 100,
      max_depth: 10,
      max_text_bytes: 1000,
    }).unwrap()
    is Ready(other) else {
    fail("missing foreign binding")
  }
  let producer = base(true, parameters=Some(declarations))
  let input = @pipeline.ProducedInput(
    @pipeline.produced_input(producer, Input(0)).unwrap(),
  )
  let root = pipeline([("a", input), ("unused", input)])
  let applications = [capacity(root), capacity(producer), capacity(producer)]
  assert_true(
    @pipeline_check_context.check(
      results(root),
      [None, Some(values), Some(values)],
      applications,
      policy(),
      limits(),
    )
    is Ok(_),
  )
  guard @pipeline_check_context.check(
      results(root),
      [None, Some(values), Some(other)],
      applications,
      policy(),
      limits(),
    )
    is Err(Guards(error)) else {
    fail("foreign declarations accepted")
  }
  assert_true(physical_equal(error.pipeline, producer))
}

///|
test "one constructor shares order binding and capacity ownership across repeated producers" {
  let producer = base(true)
  let input = @pipeline.ProducedInput(
    @pipeline.produced_input(producer, Input(0)).unwrap(),
  )
  let root = pipeline([("a", input), ("unused", input)])
  let result = results(root)
  let root_capacity = capacity(root)
  let producer_capacity = capacity(producer)
  let applications = [root_capacity, producer_capacity, producer_capacity]
  let bindings : Array[@parameter.BoundValues?] = [None, None, None]
  let checked = @pipeline_check_context.check(
    result,
    bindings,
    applications,
    policy(),
    limits(),
  ).unwrap()
  let orders = @pipeline_check_context.checked_orders(checked)
  let closure = @results.checked_producer_orders(orders)
  assert_eq(@pipeline.contextual_closure_count(closure), 3)
  assert_true(
    physical_equal(@pipeline_check_context.checked_results(checked), result),
  )
  assert_true(
    physical_equal(
      @pipeline.bound_guard_closure_source(
        @pipeline_check_context.bound_guards(checked),
      ),
      closure,
    ),
  )
  assert_true(
    physical_equal(
      @capacity.application_closure_orders(
        @pipeline_check_context.checked_capacity(checked),
      ),
      closure,
    ),
  )
  assert_true(
    physical_equal(
      @capacity.application_closure_guards(
        @pipeline_check_context.checked_capacity(checked),
      ),
      @pipeline_check_context.bound_guards(checked),
    ),
  )
  let (work, text) = @pipeline_check_context.usage(checked)
  let (ow, ot) = @results.checked_orders_usage(orders)
  let (gw, gt) = @pipeline.bound_guard_closure_usage(
    @pipeline_check_context.bound_guards(checked),
  )
  let cw = @capacity.application_closure_work(
    @pipeline_check_context.checked_capacity(checked),
  )
  assert_eq(
    (work, text),
    (
      ow +
      @pipeline_check_context.expression_requirement_work(checked) +
      gw +
      cw,
      ot + gt,
    ),
  )
  let exact = { ..limits(), max_work: work, max_text_bytes: text, }
  assert_true(
    @pipeline_check_context.check(
      result,
      bindings,
      applications,
      policy(),
      exact,
    )
    is Ok(_),
  )
  assert_true(
    @pipeline_check_context.check(result, bindings, applications, policy(), {
      ..exact,
      max_work: work - 1,
    })
    is Err(_),
  )
  assert_true(text > 0)
  assert_true(
    @pipeline_check_context.check(result, bindings, applications, policy(), {
      ..exact,
      max_text_bytes: text - 1,
    })
    is Err(_),
  )
  applications[2] = root_capacity
  assert_true(
    @pipeline_check_context.check(
      result,
      bindings,
      applications,
      policy(),
      limits(),
    )
    is Err(Capacity(ForeignPipeline(2))),
  )
  bindings.pop() |> ignore
  assert_true(
    @pipeline_check_context.check(
      result,
      bindings,
      applications,
      policy(),
      limits(),
    )
    is Err(Guards(_)),
  )
  applications.clear()
  bindings.clear()
  assert_true(
    physical_equal(
      @capacity.application_closure_at(
        @pipeline_check_context.checked_capacity(checked),
        2,
      ).unwrap(),
      producer_capacity,
    ),
  )
}

///|
test "unresolved publication order and missing capacity cannot yield a context" {
  let unordered = base(false)
  assert_true(
    @pipeline_check_context.check(
      results(unordered),
      [None],
      [capacity(unordered)],
      policy(),
      limits(),
    )
    is Err(Orders(_)),
  )
  let ordered = base(true)
  assert_true(
    @pipeline_check_context.check(
      results(ordered),
      [None],
      [],
      policy(),
      limits(),
    )
    is Err(Capacity(CoverageCount(expected=1, actual=0))),
  )
  for
    invalid in [
      { ..limits(), max_steps: -1, },
      { ..limits(), max_results: -1, },
      { ..limits(), max_work: -1, },
      { ..limits(), max_text_bytes: -1, },
    ] {
    assert_true(
      @pipeline_check_context.check(
        results(ordered),
        [None],
        [capacity(ordered)],
        policy(),
        invalid,
      )
      is Err(Orders(_)),
    )
  }
}
