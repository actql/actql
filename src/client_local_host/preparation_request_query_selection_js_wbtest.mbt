///|
test "normal Source caller keeps its explicit small Program input policy at the original parser" {
  let document = "SELECT 7 AS n"
  let (parent, input) = native_driver_parent(document)
  let (environment, publication) = request_query_publication_fixture()
  let standard = @publication_host.client_standard_program_preparation_limits()
  let selected = {
    ..standard,
    checking: {
      ..standard.checking,
      input: {
        ..standard.checking.input,
        source: { ..standard.checking.input.source, max_input_bytes: 4, },
      },
    },
  }
  let outcome = prepare_request_native_source_computation_check(
    parent,
    input,
    request_document_test_source(document, "sql"),
    native_json_reader,
    environment,
    publication,
    [],
    selected,
    @publication_host.client_standard_effect_computation_limits(),
  )
  assert_true(outcome is Err(QuerySyntax(Frontend(QuerySyntax(_)))))
  assert_eq(parent._observed_query_parse_calls, 1L)
  assert_eq(parent._observed_query_lower_calls, 0L)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "default Source caller keeps captured byte selection beyond the old standard wire envelope" {
  let document = "SELECT '" + "x".repeat(70000) + "' AS payload"
  let input = [1]
  let held : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let observed = Ref((-1, -1))
  let parent = begin_request_preparation(
    request_parent_fixture(input, current=() => {
      if observed.val.0 == -1 &&
        held.val is Some(owner) &&
        owner.query_syntax is Some(query) &&
        query.query is None &&
        owner.computation_limits is Some(selected) {
        observed.val = (
          selected.checking.input.source.max_input_bytes,
          selected.checking.input.tree.max_string_bytes,
        )
      }
      true
    }),
    input,
    client_local_resource_policy(),
  ).unwrap()
  held.val = Some(parent)
  // Same conservative component envelope as native_driver_parent; no SDK
  // capture or physical-allocation qualification is inferred from these DATA.
  reserve_request_snapshot(
    parent,
    input,
    document.length().to_int64() + 32L,
    document.length().to_int64() + 32L,
  ).unwrap()
  let (environment, publication) = request_query_publication_fixture()
  let expected = request_default_program_preparation_limits(parent, input).unwrap()
  assert_true(expected.checking.input.source.max_input_bytes > 70000)
  prepare_request_default_source_computation_check(
    parent,
    input,
    request_document_test_source(document, "sql"),
    native_json_reader,
    environment,
    publication,
    [],
    None,
    @publication_host.client_standard_effect_computation_limits(),
  ).unwrap()
  let selected = parent.computation_limits.unwrap()
  assert_eq(
    observed.val,
    (
      expected.checking.input.source.max_input_bytes,
      expected.checking.input.tree.max_string_bytes,
    ),
  )
  assert_eq(
    selected.checking.input.source.max_input_bytes,
    expected.checking.compilation.artifacts.bytes,
  )
  assert_eq(
    selected.checking.input.source.max_nodes,
    expected.checking.compilation.artifacts.nodes,
  )
  assert_eq(parent._observed_query_parse_calls, 1L)
  assert_eq(parent._observed_query_lower_calls, 1L)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "default Source large flat literal reaches the same compiler under selected finite memory" {
  let document = "SELECT [" + "0,".repeat(19999) + "0] AS payload"
  let limits = client_local_preparation_initial_limits(
    client_local_resource_policy(),
    retained_bytes=Some(1073741824L),
    execution_bytes=Some(1073741824L),
  ).unwrap()
  let (parent, input) = native_driver_parent(
    document,
    initial_limits=Some(limits),
  )
  let ledger = parent.ledger
  let (environment, publication) = request_query_publication_fixture()
  prepare_request_default_source_computation_check(
    parent,
    input,
    request_document_test_source(document, "sql"),
    native_json_reader,
    environment,
    publication,
    [],
    None,
    @publication_host.client_standard_effect_computation_limits(),
  ).unwrap()
  let original = parent.held_program.unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(before.reserved_retention_bytes < limits.retained_bytes)
  let kind = finish_request_checked_computation(
    parent, input, environment, publication,
  ).unwrap()
  assert_eq(kind, Pure)
  let prepared = parent.compiled_program.unwrap()
  assert_true(
    physical_equal(
      original,
      @checked.checked_source_program(
        @strategy.graph_program(
          @publication_host.prepared_client_graph(prepared),
        ),
      ),
    ),
  )
  assert_true(physical_equal(parent.ledger, ledger))
  assert_eq(@resources.ledger_limits(ledger), limits)
  let after = @resources.ledger_usage(ledger)
  assert_true(after.reserved_retention_bytes > before.reserved_retention_bytes)
  assert_true(after.reserved_retention_bytes < limits.retained_bytes)
  assert_true(after.reserved_execution_bytes < limits.execution_bytes)
  assert_eq(parent._observed_query_parse_calls, 1L)
  assert_eq(parent._observed_query_lower_calls, 1L)
  assert_eq(parent._observed_program_compile_calls, 1L)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
test "large Source keeps explicitly smaller memory refusal before compiler and returns the same reservation" {
  let document = "SELECT [" + "0,".repeat(19999) + "0] AS payload"
  let limits = client_local_preparation_initial_limits(
    client_local_resource_policy(),
    retained_bytes=Some(67108864L),
    execution_bytes=Some(67108864L),
  ).unwrap()
  let (parent, input) = native_driver_parent(
    document,
    initial_limits=Some(limits),
  )
  let ledger = parent.ledger
  let (environment, publication) = request_query_publication_fixture()
  prepare_request_default_source_computation_check(
    parent,
    input,
    request_document_test_source(document, "sql"),
    native_json_reader,
    environment,
    publication,
    [],
    None,
    @publication_host.client_standard_effect_computation_limits(),
  ).unwrap()
  let original = parent.held_program.unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    finish_request_checked_computation(parent, input, environment, publication)
    is Err(Preparation(ProgramCheck(Capacity(Resource(RetentionLimit))))),
  )
  let child = parent.program_check.unwrap()
  let (required, _) = child.compilation_quote.unwrap()
  assert_true(required > @resources.ledger_limits(ledger).retained_bytes)
  assert_eq(
    @resources.ledger_usage(ledger).reserved_retention_bytes,
    before.reserved_retention_bytes,
  )
  assert_true(physical_equal(parent.ledger, ledger))
  assert_true(physical_equal(parent.held_program.unwrap(), original))
  assert_eq(parent._observed_query_parse_calls, 1L)
  assert_eq(parent._observed_query_lower_calls, 1L)
  assert_eq(child._observed_program_compile_calls, 0L)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
test "selected large Source retains its original through funded Plan input borrow" {
  let document = "SELECT [" + "0,".repeat(19999) + "0] AS cells"
  let limits = client_local_preparation_initial_limits(
    client_local_resource_policy(),
    retained_bytes=Some(1073741824L),
    execution_bytes=Some(1073741824L),
  ).unwrap()
  let (parent, input) = native_driver_parent(
    document,
    initial_limits=Some(limits),
  )
  let (environment, publication) = request_query_publication_fixture()
  prepare_request_default_source_computation_check(
    parent,
    input,
    request_document_test_source(document, "sql"),
    native_json_reader,
    environment,
    publication,
    [],
    None,
    @publication_host.client_standard_effect_computation_limits(),
  ).unwrap()
  finish_request_checked_computation(parent, input, environment, publication).unwrap()
  |> ignore
  let original = parent.compiled_program.unwrap()
  let before = @resources.ledger_usage(parent.ledger)
  let data = program_check_data_extent_cost(parent.program_data.unwrap()).unwrap()
  let holder = match borrow_request_program_plan_input(parent, input) {
    Ok(value) => value
    Err(issue) => {
      let (required, execution) = parent.program_plan_quote.unwrap()
      let syntax = parent.held_program.unwrap()
      let estimate = parent.program_data.unwrap()
      let details = @debug.to_string(
          (
            issue,
            (required, execution),
            (limits.retained_bytes, limits.execution_bytes),
            (before.reserved_retention_bytes, before.reserved_execution_bytes),
            data,
            client_local_value_node_proof_retained_bytes(),
            client_local_value_node_proof_scratch_bytes(),
          ),
        ) +
        @debug.to_string(
          (
            @syntax.program_usage(syntax),
            @syntax.program_preparation_data(syntax),
            estimate.collections,
            estimate.utf16_units,
          ),
        )
      abort_request_preparation_after_cleanup(parent).unwrap()
      assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
      fail(
        "original Plan borrow (issue,required,selected,before,checkData,proofRetained,proofScratch): " +
        details,
      )
    }
  }
  assert_true(
    physical_equal(
      @resources.preparation_body_borrow_value(holder).unwrap(),
      original,
    ),
  )
  // Returning a constructor input is not the owner's retirement ACK.
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  assert_eq(parent._observed_query_parse_calls, 1L)
  assert_eq(parent._observed_query_lower_calls, 1L)
  assert_eq(parent._observed_program_compile_calls, 1L)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
