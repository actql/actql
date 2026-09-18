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
