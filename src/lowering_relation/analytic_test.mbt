///|
fn analytic_owner(
  body : String,
  declarations? : @parameter.Declarations? = None,
  values? : @parameter.BoundValues? = None,
) -> @lowering_relation.BoundPrepared {
  @lowering_relation.bind_parameters(
    @lowering_relation.prepare(top_k_checked(body, declarations), limits()).unwrap(),
    values,
    max_parameters=2,
    max_name_bytes=64,
  ).unwrap()
}

///|
fn analytic_kernel(body : String) -> @lowering_relation.PreparedKernel {
  match
    @lowering_relation.prepare_kernel(
      analytic_owner(body),
      0,
      max_bindings=100,
      max_name_bytes=1000,
      expression_limits(),
    ) {
    Ok(value) => value
    Err(@lowering_relation.AnalyticFailure(issue)) =>
      match issue {
        AnalyticNotFound => abort("analytic not found")
        InvalidAnalyticLimits => abort("invalid analytic limits")
        AnalyticPreparationLimit => abort("analytic preparation limit")
        AnalyticExpressionFailure(_) => abort("analytic expression")
        MissingAnalyticParameter(_) => abort("missing analytic parameter")
        InvalidAnalyticParameter(_) => abort("invalid analytic parameter")
        InvalidAnalyticCall(_) => abort("invalid analytic call")
        AnalyticAggregateFailure(_) => abort("analytic aggregate")
      }
    Err(MissingKernelNode) => abort("missing kernel node")
    Err(InvalidKernelWiring) => abort("invalid kernel wiring")
    Err(KernelBudgetExceeded) => abort("kernel budget")
    Err(InvalidKernelLimits) => abort("invalid kernel limits")
    Err(ExpressionFailure(_)) => abort("kernel expression")
    Err(InvalidTakeCount) => abort("take count")
    Err(InvalidTopKCount) => abort("top-k count")
    Err(PendingTakeOrder) => abort("take order")
    Err(PendingTopKOrder) => abort("top-k order")
    Err(PendingSortOrder) => abort("sort order")
    Err(PendingLagOrder) => abort("lag order")
    Err(InvalidLagOffset) => abort("lag offset")
    Err(PendingWatermarkOrder) => abort("watermark order")
    Err(InvalidWatermarkThreshold) => abort("watermark threshold")
    Err(PivotFailure(_)) => abort("pivot")
    Err(CountGroupFailure(_)) => abort("count group")
    Err(GroupFailure(_)) => abort("group")
  }
}

///|
test "analytic keeps authored peers separate from position completion" {
  let kernel = analytic_kernel(
    "\"analytic\":{\"partition_by\":[\"group\",\"group\"]," +
    "\"order_by\":[{\"field\":\"amount\",\"dir\":\"desc\"," +
    "\"nulls\":\"first\"}],\"functions\":{\"position\":{" +
    "\"fn\":\"row_number\"},\"peer\":{\"fn\":\"rank\"}}}",
  )
  guard @lowering_relation.kernel_analytic(kernel) is Some(analytic) else {
    fail("analytic")
  }
  assert_eq(@lowering_relation.analytic_partition_count(analytic), 2)
  assert_eq(
    @lowering_relation.analytic_partition_at(analytic, 0),
    Some(@schema.Unqualified("group")),
  )
  assert_eq(
    @lowering_relation.analytic_partition_at(analytic, 1),
    Some(@schema.Unqualified("group")),
  )
  assert_eq(@lowering_relation.analytic_peer_term_count(analytic), 1)
  assert_eq(
    @lowering_relation.analytic_peer_term_at(analytic, 0),
    Some((@schema.Unqualified("amount"), true, true)),
  )
  assert_eq(@lowering_relation.analytic_position_term_count(analytic), 2)
  assert_eq(
    @lowering_relation.analytic_position_term_at(analytic, 1),
    Some((@schema.Unqualified("id"), false, false)),
  )
  assert_false(
    @lowering_relation.analytic_uses_retained_position_order(analytic),
  )
  assert_eq(@lowering_relation.analytic_call_count(analytic), 2)
  guard @lowering_relation.analytic_call_at(analytic, 0) is Some(first) &&
    @lowering_relation.analytic_call_at(analytic, 1) is Some(second) else {
    fail("calls")
  }
  assert_eq(@lowering_relation.analytic_call_name(first), "peer")
  assert_true(
    @lowering_relation.analytic_call_function(first)
    is @lowering_relation.PreparedRank,
  )
  assert_eq(@lowering_relation.analytic_call_name(second), "position")
  assert_true(
    @lowering_relation.analytic_call_function(second)
    is @lowering_relation.PreparedRowNumber,
  )
}

///|
test "analytic lowers navigation frame and aggregate expressions" {
  let body = "\"analytic\":{\"partition_by\":[],\"order_by\":[{" +
    "\"id\":\"asc\"}],\"frame\":{\"start\":{\"preceding\":2}," +
    "\"end\":{\"following\":1}},\"functions\":{" +
    "\"before\":{\"fn\":\"lag\",\"expr\":\"amount + 1\"," +
    "\"offset\":0},\"first\":{\"fn\":\"first_value\"," +
    "\"expr\":\"amount\"},\"total\":{\"fn\":\"sum\"," +
    "\"expr\":\"amount + 2\",\"filter\":\"amount > 0\"}}}"
  let kernel = analytic_kernel(body)
  let analytic = @lowering_relation.kernel_analytic(kernel).unwrap()
  let frame = @lowering_relation.analytic_frame(analytic).unwrap()
  assert_eq(
    @lowering_relation.prepared_frame_start(frame),
    @lowering_relation.PreparedPreceding(2L),
  )
  assert_eq(
    @lowering_relation.prepared_frame_end(frame),
    @lowering_relation.PreparedFollowing(1L),
  )
  assert_eq(@lowering_relation.analytic_call_count(analytic), 3)
  let roots = @lowering_relation.prepare_kernel_roots(
    @lowering_relation.prepare_sequence(analytic_owner(body), sequence_limits()).unwrap(),
    0,
    root_limits(),
  ).unwrap()
  assert_eq(@lowering_relation.root_count(roots), 4)
  assert_eq(
    @lowering_relation.root_at(roots, 0).unwrap().parameter_pointer,
    "/functions/before/expr",
  )
  assert_eq(
    @lowering_relation.root_at(roots, 3).unwrap().parameter_pointer,
    "/functions/total/filter",
  )
  let writer = @encode.writer(100000, 10000, 100)
  @lowering_relation.emit_kernel_node(kernel, writer)
  let wire = @encode.finish(writer)
  assert_true(wire.contains("\"op\":\"REL.analytic\""))
  assert_true(wire.contains("\"before\":{\"expr\":"))
  assert_true(wire.contains("\"fn\":\"lag\",\"offset\":0"))
  assert_true(wire.contains("\"fn\":\"sum\""))
}

///|
test "analytic resolves bound offsets frame distances and fractions" {
  let declarations = @parameter.read_declarations(
    Some(
      cursor(
        "{\"n\":{\"type\":\"number\",\"nullable\":false}," +
        "\"f\":{\"type\":\"number\",\"nullable\":false}}",
      ),
    ),
    { max_parameters: 2, max_nodes: 20, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let values = match
    @parameter.bind(declarations, Some(cursor("{\"n\":2,\"f\":0.5}")), {
      max_nodes: 20,
      max_depth: 10,
      max_text_bytes: 1000,
    }).unwrap() {
    Ready(values) => values
    NeedsBindings(_) => abort("fixture is complete")
  }
  let body = "\"analytic\":{\"partition_by\":[],\"order_by\":[{" +
    "\"id\":\"asc\"}],\"frame\":{\"start\":{\"preceding\":{" +
    "\"$param\":\"n\"}},\"end\":\"current_row\"},\"functions\":{" +
    "\"before\":{\"fn\":\"lag\",\"expr\":\"amount\"," +
    "\"offset\":{\"$param\":\"n\"}},\"middle\":{" +
    "\"fn\":\"percentile_cont\",\"field\":\"amount\"," +
    "\"fraction\":{\"$param\":\"f\"}}}}"
  let owner = analytic_owner(
    body,
    declarations=Some(declarations),
    values=Some(values),
  )
  let kernel = @lowering_relation.prepare_kernel(
    owner,
    0,
    max_bindings=100,
    max_name_bytes=1000,
    expression_limits(),
  ).unwrap()
  let analytic = @lowering_relation.kernel_analytic(kernel).unwrap()
  assert_eq(
    @lowering_relation.prepared_frame_start(
      @lowering_relation.analytic_frame(analytic).unwrap(),
    ),
    @lowering_relation.PreparedPreceding(2L),
  )
  guard @lowering_relation.analytic_call_at(analytic, 0) is Some(before) &&
    @lowering_relation.analytic_call_function(before)
    is @lowering_relation.PreparedLag(_, offset) else {
    fail("lag")
  }
  assert_eq(offset, 2L)
  guard @lowering_relation.analytic_call_at(analytic, 1) is Some(middle) &&
    @lowering_relation.analytic_call_function(middle)
    is @lowering_relation.PreparedFrameAggregate(aggregate) else {
    fail("aggregate")
  }
  assert_eq(@lowering_relation.group_aggregate_fraction(aggregate), Some(0.5))
}

///|
test "analytic preparation enforces exact entry and name budgets" {
  let owner = analytic_owner(
    "\"analytic\":{\"partition_by\":[\"group\"],\"order_by\":[{" +
    "\"id\":\"asc\"}],\"functions\":{\"position\":{" +
    "\"fn\":\"row_number\"}}}",
  )
  let full = @lowering_relation.prepare_kernel(
    owner,
    0,
    max_bindings=100,
    max_name_bytes=1000,
    expression_limits(),
  ).unwrap()
  let analytic = @lowering_relation.kernel_analytic(full).unwrap()
  let entries = @lowering_relation.analytic_entry_count(analytic)
  let bytes = @lowering_relation.analytic_name_bytes(analytic)
  assert_true(
    @lowering_relation.prepare_kernel(
      owner,
      0,
      max_bindings=entries,
      max_name_bytes=bytes,
      expression_limits(),
    )
    is Ok(_),
  )
  assert_true(
    @lowering_relation.prepare_kernel(
      owner,
      0,
      max_bindings=entries - 1,
      max_name_bytes=bytes,
      expression_limits(),
    )
    is Err(@lowering_relation.AnalyticFailure(_)),
  )
  assert_true(
    @lowering_relation.prepare_kernel(
      owner,
      0,
      max_bindings=entries,
      max_name_bytes=bytes - 1,
      expression_limits(),
    )
    is Err(@lowering_relation.AnalyticFailure(_)),
  )
}

///|
test "analytic canonical node orders retained nested property source" {
  let kernel = analytic_kernel(
    "\"analytic\":{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}]," +
    "\"functions\":{\"z\":{\"fn\":\"lag\",\"expr\":{" +
    "\"property\":{\"value\":{\"object\":{\"score\":{\"field\":\"amount\"}}},\"name\":\"score\"}}}," +
    "\"a\":{\"fn\":\"lead\",\"expr\":\"amount + 1\"}}}",
  )
  let writer = @encode.writer(100000, 10000, 100)
  @lowering_relation.emit_kernel_node(kernel, writer)
  let wire = @encode.finish(writer)
  assert_true(
    wire.contains(
      "\"property\":{\"name\":\"score\",\"value\":{\"object\":{\"score\":{\"field\":\"amount\"}}}}",
    ),
    msg=wire,
  )
}

///|
test "analytic canonical source shares exact node and work limits across calls" {
  let owner = analytic_owner(
    "\"analytic\":{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}]," +
    "\"functions\":{\"z\":{\"fn\":\"lag\",\"expr\":{" +
    "\"property\":{\"value\":{\"object\":{\"score\":{\"field\":\"amount\"}}},\"name\":\"score\"}}}," +
    "\"a\":{\"fn\":\"lead\",\"expr\":\"amount + 1\"}}}",
  )
  let limits = expression_limits()
  let (_, remaining) = @lowering_relation.prepare_analytic(
    owner, 0, 100, 1000, limits,
  ).unwrap()
  let nodes = limits.max_nodes - remaining.max_nodes
  let work = limits.max_work - remaining.max_work
  let exact = { ..limits, max_nodes: nodes, max_work: work, }
  let (_, empty) = @lowering_relation.prepare_analytic(
    owner, 0, 100, 1000, exact,
  ).unwrap()
  assert_eq(empty.max_nodes, 0)
  assert_eq(empty.max_work, 0)
  for
    short in [
      { ..exact, max_nodes: nodes - 1, },
      { ..exact, max_work: work - 1, },
    ] {
    assert_true(
      @lowering_relation.prepare_analytic(owner, 0, 100, 1000, short)
      is Err(@lowering_relation.AnalyticExpressionFailure(_)),
    )
  }
}

///|
test "analytic canonical source leaves ordinary retained projection unchanged" {
  let kernel = analytic_kernel(
    "\"analytic\":{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}]," +
    "\"functions\":{\"out\":{\"fn\":\"lag\",\"expr\":{" +
    "\"property\":{\"value\":{\"object\":{\"score\":{\"field\":\"amount\"}}},\"name\":\"score\"}}}}}",
  )
  let analytic = @lowering_relation.kernel_analytic(kernel).unwrap()
  let call = @lowering_relation.analytic_call_at(analytic, 0).unwrap()
  guard @lowering_relation.analytic_call_function(call)
    is @lowering_relation.PreparedLag(expression, _) else {
    fail("lag")
  }
  let writer = @encode.writer(100000, 10000, 100)
  @lowering_relation.emit_expression_source(expression, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"property\":{\"value\":{\"object\":{\"score\":{\"field\":\"amount\"}}},\"name\":\"score\"}}",
  )
}

///|
test "analytic canonical source covers nested arguments and aggregate filters" {
  let property = "{\"property\":{\"value\":{\"property\":{\"value\":{\"object\":{\"inner\":{\"object\":{\"score\":{\"field\":\"amount\"}}}}},\"name\":\"inner\"}},\"name\":\"score\"}}"
  let canonical = "{\"property\":{\"name\":\"score\",\"value\":{\"property\":{\"name\":\"inner\",\"value\":{\"object\":{\"inner\":{\"object\":{\"score\":{\"field\":\"amount\"}}}}}}}}}"
  let body = "\"analytic\":{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}]," +
    "\"frame\":{\"start\":\"unbounded_preceding\",\"end\":\"current_row\"},\"functions\":{" +
    "\"z\":{\"fn\":\"sum\",\"expr\":" +
    property +
    ",\"filter\":{\"not_null\":" +
    property +
    "}}," +
    "\"last\":{\"fn\":\"last_value\",\"expr\":" +
    property +
    "}," +
    "\"first\":{\"fn\":\"first_value\",\"expr\":" +
    property +
    "}}}"
  let writer = @encode.writer(100000, 10000, 100)
  @lowering_relation.emit_kernel_node(analytic_kernel(body), writer)
  assert_eq(
    @encode.finish(writer),
    "{\"id\":\"analytic_0\",\"in\":[\"input_0\"],\"op\":\"REL.analytic\",\"params\":{" +
    "\"frame\":{\"end\":\"current_row\",\"start\":\"unbounded_preceding\"},\"functions\":{" +
    "\"first\":{\"expr\":" +
    canonical +
    ",\"fn\":\"first_value\"}," +
    "\"last\":{\"expr\":" +
    canonical +
    ",\"fn\":\"last_value\"}," +
    "\"z\":{\"expr\":" +
    canonical +
    ",\"filter\":{\"not_null\":" +
    canonical +
    "},\"fn\":\"sum\"}}," +
    "\"order_by\":[{\"dir\":\"asc\",\"field\":\"id\",\"nulls\":\"last\"}],\"partition_by\":[]}}",
  )
}

///|
test "analytic canonical source keeps literal objects opaque and parameter references" {
  let declarations = @parameter.read_declarations(
    Some(cursor("{\"n\":{\"type\":\"number\",\"nullable\":false}}")),
    { max_parameters: 1, max_nodes: 10, max_depth: 10, max_text_bytes: 100, },
  ).unwrap()
  let values = match
    @parameter.bind(declarations, Some(cursor("{\"n\":2}")), {
      max_nodes: 10,
      max_depth: 10,
      max_text_bytes: 100,
    }).unwrap() {
    Ready(values) => values
    NeedsBindings(_) => abort("fixture is bound")
  }
  let owner = analytic_owner(
    "\"analytic\":{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"functions\":{" +
    "\"p\":{\"fn\":\"lag\",\"expr\":{\"$param\":\"n\"}}," +
    "\"data\":{\"fn\":\"lag\",\"expr\":{\"literal\":{\"z\":[true,null,3],\"if\":{\"$param\":\"business\"},\"a\":\"é\"}}}}}",
    declarations=Some(declarations),
    values=Some(values),
  )
  let kernel = @lowering_relation.prepare_kernel(
    owner,
    0,
    max_bindings=100,
    max_name_bytes=1000,
    expression_limits(),
  ).unwrap()
  let writer = @encode.writer(100000, 10000, 100)
  @lowering_relation.emit_kernel_node(kernel, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"id\":\"analytic_0\",\"in\":[\"input_0\"],\"op\":\"REL.analytic\",\"params\":{\"functions\":{" +
    "\"data\":{\"expr\":{\"literal\":{\"a\":\"é\",\"if\":{\"$param\":\"business\"},\"z\":[true,null,3]}},\"fn\":\"lag\",\"offset\":1}," +
    "\"p\":{\"expr\":{\"$param\":\"n\"},\"fn\":\"lag\",\"offset\":1}}," +
    "\"order_by\":[{\"dir\":\"asc\",\"field\":\"id\",\"nulls\":\"last\"}],\"partition_by\":[]}}",
  )
}

///|
test "analytic canonical preparation shares limits across sequence steps" {
  let first = "\"analytic\":{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"functions\":{\"a\":{\"fn\":\"lag\",\"expr\":\"amount + 1\"}}}"
  let second = "\"analytic\":{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"functions\":{\"b\":{\"fn\":\"lag\",\"expr\":\"amount + 1\"}}}"
  let owner = analytic_owner(first + "},{" + second)
  let limits = expression_limits()
  let (_, after_first) = @lowering_relation.prepare_analytic(
    owner, 0, 100, 1000, limits,
  ).unwrap()
  let (_, after_both) = @lowering_relation.prepare_analytic(
    owner, 1, 100, 1000, after_first,
  ).unwrap()
  let exact = {
    ..limits,
    max_nodes: limits.max_nodes - after_both.max_nodes,
    max_work: limits.max_work - after_both.max_work,
  }
  assert_true(
    @lowering_relation.prepare_sequence(owner, {
      ..sequence_limits(),
      expressions: exact,
    })
    is Ok(_),
  )
  for
    short in [
      { ..exact, max_nodes: exact.max_nodes - 1, },
      { ..exact, max_work: exact.max_work - 1, },
    ] {
    assert_true(
      @lowering_relation.prepare_sequence(owner, {
        ..sequence_limits(),
        expressions: short,
      })
      is Err(_),
    )
  }
}

///|
test "analytic source ordering preserves semantic expression depth limits" {
  for
    (expression, depth) in [
      ("{\"field\":\"amount\"}", 0),
      (
        "{\"property\":{\"value\":{\"object\":{\"score\":{\"field\":\"amount\"}}},\"name\":\"score\"}}",
        2,
      ),
    ] {
    let owner = analytic_owner(
      "\"analytic\":{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"functions\":{\"out\":{\"fn\":\"lag\",\"expr\":" +
      expression +
      "}}}",
    )
    assert_true(
      @lowering_relation.prepare_analytic(owner, 0, 100, 1000, {
        ..expression_limits(),
        max_depth: depth,
      })
      is Ok(_),
    )
    if depth > 0 {
      assert_true(
        @lowering_relation.prepare_analytic(owner, 0, 100, 1000, {
          ..expression_limits(),
          max_depth: depth - 1,
        })
        is Err(_),
      )
    }
  }
}
