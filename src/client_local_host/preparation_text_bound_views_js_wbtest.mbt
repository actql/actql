///|
fn request_text_bound_views_fixture(
  timestamp : Bool,
) -> (
  ClientRequestPreparation[Array[Int]],
  Array[Int],
  @publication_host.PreparedClientProgram,
  @checked.CheckedProgram,
) raise {
  let expression = if timestamp {
    "parse_timestamp('2026-01-02', 'yyyy-MM-dd')"
  } else {
    "try_number('1')"
  }
  let document = "{\"version\":\"actql/0.1\",\"id\":\"text-bound-views\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"input\"},{\"derive\":{\"value\":\"" +
    expression +
    "\"},\"as\":\"derived\"}],\"results\":{\"r\":{\"from\":\"derived\",\"fields\":[\"value\"]}}}],\"results\":{\"r\":{\"from\":{\"stage\":\"main\",\"result\":\"r\"}}}}"
  let (parent, child, _, input) = registration_parent_fixture(text=document)
  guard finish_program_check_preparation(child).unwrap()
    is @checked.Checked(checked) else {
    fail("original text-bound Program must check")
  }
  let prepared = compile_program_check_preparation(
    child,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  assert_true(
    physical_equal(
      continue_request_program_preparation(parent, input).unwrap(),
      prepared,
    ),
  )
  (parent, input, prepared, checked)
}

///|
// Independent source census: the view owns one header/two references; its
// optional Timestamp pattern owns another header, one scalar tag and reference.
// The pre-existing outer Some(view) is not part of this representation delta.
fn expected_text_bound_views_plan_quote(
  parent : ClientRequestPreparation[Array[Int]],
  input : Array[Int],
  prepared : @publication_host.PreparedClientProgram,
) -> (Int64, Int64) {
  let graph = @publication_host.prepared_client_graph(prepared)
  let tasks = @strategy.graph_task_count(graph)
  let count = @checked.expression_bound_count(@strategy.graph_program(graph)).to_int64() *
    tasks.to_int64()
  let base = original_request_plan_construction_quote(
    parent.program_capacity.unwrap(),
    input,
    parent.program_data.unwrap(),
    tasks~,
  ).unwrap()
  let selectors = installed_direct_occurrences_layout(0).unwrap()
  let increment = (16L * 2L + 8L * 3L + 8L) * count
  (
    base.0 + selectors.0 + increment,
    base.1 +
    selectors.1 +
    installed_compute_tail_inventory_bytes +
    2L * increment,
  )
}

///|
test "Request Plan adds original text-bound view and timestamp Option backing before sequence construction" {
  for timestamp in [false, true] {
    let (parent, input, prepared, checked) = request_text_bound_views_fixture(
      timestamp,
    )
    let graph = @publication_host.prepared_client_graph(prepared)
    assert_true(physical_equal(@strategy.graph_program(graph), checked))
    assert_eq(@checked.expression_bound_count(checked), 1)
    // The literal 64-byte per-item oracle above is independent of the layout.
    assert_eq(
      request_program_plan_quote(parent, input).unwrap(),
      expected_text_bound_views_plan_quote(parent, input, prepared),
    )
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
fn inspect_original_text_bound_view(
  prepared : @publication_host.PreparedClientProgram,
  checked : @checked.CheckedProgram,
  timestamp : Bool,
) -> Unit raise {
  let owner = @strategy.graph_task_owner(
    @publication_host.prepared_client_graph(prepared),
    0,
  ).unwrap()
  let expression = @lower.lower_expression(
    owner,
    1,
    0,
    @publication_host.prepared_client_values_sequence_limits(prepared).expressions,
  ).unwrap()
  let view = @lower.expression_text_bound(expression).unwrap()
  let original = @checked.expression_bound_at(checked, 0).unwrap()
  assert_true(
    physical_equal(
      @lower.text_bound_output(view),
      @context.text_bound_output(original),
    ),
  )
  assert_true(
    physical_equal(
      @lower.text_bound_policy(view),
      @context.text_bound_policy(original),
    ),
  )
  if timestamp {
    let pattern = @lower.text_bound_timestamp_pattern(view).unwrap()
    let closure = @checked.expression_closure(checked).unwrap()
    let mut matched = false
    for index in 0..<@context.expression_closure_count(closure) {
      if @context.expression_closure_at(closure, index).unwrap().resolution
        is @context.Pattern(@context.Timestamp(selected)) {
        assert_true(
          physical_equal(pattern, @context.timestamp_pattern_ast(selected)),
        )
        matched = true
      }
    }
    assert_true(matched)
  } else {
    assert_true(@lower.text_bound_timestamp_pattern(view) is None)
  }
}

///|
test "text-bound view grow keeps same parent on both one-short boundaries and exact admitted originals" {
  for timestamp in [false, true] {
    for retention in [true, false] {
      let (parent, input, prepared, checked) = request_text_bound_views_fixture(
        timestamp,
      )
      let capacity = parent.program_capacity.unwrap()
      let expected = expected_text_bound_views_plan_quote(
        parent, input, prepared,
      )
      let before = @resources.preparation_capacity_working_extents(
        capacity, input,
      ).unwrap()
      let limits = @resources.ledger_limits(parent.ledger)
      let blocker = @resources.reserve_capacity(
        parent.ledger,
        if retention {
          limits.retained_bytes - before.0
        } else {
          0L
        },
        if retention {
          0L
        } else {
          limits.execution_bytes - before.1
        },
      ).unwrap()
      assert_true(
        reserve_request_program_plan(parent, input) is Err(Capacity(_)),
      )
      let quote = parent.program_plan_quote.unwrap()
      assert_eq(quote, expected)
      @resources.settle_capacity(parent.ledger, blocker).unwrap()
      let short = @resources.reserve_capacity(
        parent.ledger,
        if retention {
          limits.retained_bytes - quote.0 + 1L
        } else {
          0L
        },
        if retention {
          0L
        } else {
          limits.execution_bytes - quote.1 + 1L
        },
      ).unwrap()
      let result = reserve_request_program_plan(parent, input)
      assert_true(
        if retention {
          result is Err(Capacity(Resource(RetentionLimit)))
        } else {
          result is Err(Capacity(Resource(ExecutionLimit)))
        },
      )
      assert_eq(parent.program_plan_quote, Some(quote))
      assert_eq(
        @resources.preparation_capacity_working_extents(capacity, input),
        Ok(before),
      )
      assert_true(physical_equal(parent.program_capacity.unwrap(), capacity))
      assert_true(physical_equal(parent.compiled_program.unwrap(), prepared))
      assert_true(!parent.program_body_attempted)
      assert_true(
        reserve_request_program_plan(parent, [1]) is Err(ForeignOriginal),
      )
      @resources.settle_capacity(parent.ledger, short).unwrap()
      let exact = @resources.reserve_capacity(
        parent.ledger,
        if retention {
          limits.retained_bytes - quote.0
        } else {
          0L
        },
        if retention {
          0L
        } else {
          limits.execution_bytes - quote.1
        },
      ).unwrap()
      reserve_request_program_plan(parent, input).unwrap()
      assert_eq(
        @resources.preparation_capacity_working_extents(capacity, input),
        Ok(quote),
      )
      inspect_original_text_bound_view(prepared, checked, timestamp)
      @resources.settle_capacity(parent.ledger, exact).unwrap()
      abort_request_preparation_after_cleanup(parent).unwrap()
      assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
    }
  }
}

///|
test "a checked Program without text envelopes adds no view construction charge" {
  let (parent, _, prepared) = request_program_body_fixture()
  let graph = @publication_host.prepared_client_graph(prepared)
  assert_eq(@checked.expression_bound_count(@strategy.graph_program(graph)), 0)
  assert_eq(installed_text_bound_views_layout(graph), Some((0L, 0L)))
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "failed text-bound sequence replacement retains original cache and Request construction backing" {
  for timestamp in [false, true] {
    let (parent, input, prepared, _) = request_text_bound_views_fixture(
      timestamp,
    )
    let expected = expected_text_bound_views_plan_quote(parent, input, prepared)
    reserve_request_program_plan(parent, input).unwrap()
    let capacity = parent.program_capacity.unwrap()
    let held = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
    // Both the old cached view and a failed replacement's nested Option tag
    // stay covered by the independent 64R/128E per-item quote.
    assert_eq(held, expected)
    let limits = @publication_host.prepared_client_values_sequence_limits(
      prepared,
    )
    let original = @publication_host.prepare_prepared_client_full_sequence(
      prepared, 0, limits,
    ).unwrap()
    // The same task/owner keeps its old full sequence while constructing the
    // changed-limit attempt. Its literal admission fails; no replacement wins.
    let short = {
      ..limits,
      expressions: { ..limits.expressions, max_literal_text_bytes: 0, },
    }
    assert_true(
      @publication_host.prepare_prepared_client_full_sequence(
        prepared, 0, short,
      )
      is Err(_),
    )
    assert_true(
      physical_equal(
        @publication_host.prepare_prepared_client_full_sequence(
          prepared, 0, limits,
        ).unwrap(),
        original,
      ),
    )
    assert_true(physical_equal(parent.compiled_program.unwrap(), prepared))
    assert_true(physical_equal(parent.program_capacity.unwrap(), capacity))
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input),
      Ok(held),
    )
    assert_true(!parent.program_body_attempted)
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}
