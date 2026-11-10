///|
// Exact original public SQL/parameter DATA. This test constructs checked
// Source/Query/Plan originals but does not open an account or physical reader.
// This route uses the existing JS invocation-material test fixtures.
#cfg(target="js")
test "source-free expanded left preserves the independent acquired right capture plan" {
  let prepared = before_limit_standard_prepared(
    "SELECT p.id, element, position FROM UNNEST(@parents) p CROSS JOIN UNNEST(p.items) element WITH OFFSET position CROSS JOIN records r MAX_OUTPUT_ROWS 10 ORDER BY p.id, position",
    @frontend.Text,
    parameter_declarations=Some(
      "{\"parents\":{\"type\":\"array\",\"max_items\":4,\"items\":{\"type\":\"object\",\"fields\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"items\":{\"type\":\"array\",\"nullable\":true,\"max_items\":3,\"items\":{\"type\":\"number\",\"nullable\":true}}}}}}",
    ),
    parameter_values=Some(
      funded_value_cursor(
        "{\"parents\":[{\"id\":2,\"items\":[2,null,2]},{\"id\":1,\"items\":[1]},{\"id\":3,\"items\":[]},{\"id\":4,\"items\":null}]}",
      ),
    ),
  )
  let graph = @publication_host.prepared_client_graph(prepared)
  let direct = installed_direct_occurrences_owned(Pure(prepared)).unwrap()
  println(
    "capture-plan tasks=\{@strategy.graph_task_count(graph)} captured=\{@strategy.graph_captured_prefix(graph)} acquisitions=\{@publication_host.prepared_client_acquisition_count(prepared)} direct=\{@publication_host.client_direct_acquisition_occurrence_count(direct)} supported=\{installed_managed_owner_shape_supported(Pure(prepared), false)}",
  )
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "join-after-expansion-source-only",
  ).unwrap()
  assert_eq(
    @publication_host.client_direct_acquisition_occurrence_count(direct),
    1,
  )
  let (stage, input, task) = @publication_host.client_direct_acquisition_occurrence_at(
    direct, 0,
  ).unwrap()
  println("capture-plan original stage=\{stage} input=\{input} task=\{task}")
  // Match the ordinary Host's existing original invocation route, even
  // though this SQL uses no clock expression. No authority is supplied here.
  let compilation_limits = @publication_host.client_standard_pure_compilation_limits()
  let compilation = @publication_host.issue_prepared_client_task_compilation(
    prepared,
    request_program_module_manifests(),
    @publication_host.prepared_client_values_sequence_limits(prepared),
    compilation_limits.max_facts,
    compilation_limits.max_witnesses,
    compilation_limits.max_wire_bytes,
    compilation_limits.max_nodes,
    compilation_limits.max_depth,
  ).unwrap()
  let compiled = request_invocation_issue_run(
    prepared,
    @publication_host.Tasks(compilation),
  )
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "join-after-expansion-source-only", "original", "2026-10-31T00:00:00.000Z",
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let time = @publication_host.prepare_client_query_time(
    prepared, request, "2026-10-31T00:00:00.000Z",
  ).unwrap()
  @publication_host.bind_client_query_evaluation_time(
    time, prepared, compiled, definition, request,
  ).unwrap()
  |> ignore
  guard select_installed_source_input(prepared, request, stage, input).unwrap()
    is @sourceviews.WholeInputRoute(original) else {
    fail("same original SQL must select its Whole input route")
  }
  let policy = installed_row_input_policy(10000, 10000000, 110101, 2, 10000)
  let source = prepare_installed_catalog_whole_source_capacity(
    prepared, original, contracts, policy,
  ).unwrap()
  let plan = prepare_installed_managed_whole_source_plan_at_query_time(
    prepared,
    request,
    source,
    10000000L,
    239908928L,
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    Some((time, request, compiled, definition)),
    retained_output=false,
    provider_factory=_ => [],
    runtime_admission=true,
  )
  match plan {
    Ok(value) => {
      assert_true(physical_equal(value.prepared, prepared))
      assert_true(physical_equal(value.request, request))
      assert_eq(value.whole_sources.length(), 1)
      let sequences = value.compute_sequences
      let physical = value.graph
      let inputs = []
      for task in 0..<sequences.length() {
        inputs.push(@strategy.graph_task_input_count(physical, task).unwrap())
      }
      let max_rows = @row_source_host.row_input_acquisition_max_rows(
        source.acquisition,
      )
      let configuration = value.capacity_plan
      assert_true(
        client_local_sequence_capacity_original(
          sequences,
          @strategy.graph_task_count(physical),
          capacity_plan=Some(configuration),
          retained_inputs=Some(inputs),
          max_rows~,
          runtime_admission=true,
        )
        is Some(_),
      )
      assert_true(
        client_local_sequence_capacity_original(
          sequences,
          @strategy.graph_task_count(physical),
          capacity_plan=Some(configuration),
          retained_inputs=Some(inputs),
          max_rows~,
          runtime_admission=false,
        )
        is None,
      )
      assert_true(
        client_local_sequence_capacity_original(
          sequences,
          @strategy.graph_task_count(physical),
          capacity_plan=Some(configuration),
          retained_inputs=Some(inputs),
          max_rows~,
          runtime_admission=true,
          include_simultaneous=true,
          simultaneous_graph=Some(physical),
        )
        is None,
      )
      assert_true(
        client_local_sequence_capacity_original(
          sequences,
          @strategy.graph_task_count(physical),
          capacity_plan=Some(configuration),
          retained_inputs=Some([]),
          max_rows~,
          runtime_admission=true,
        )
        is None,
      )
      assert_true(
        client_local_sequence_capacity_original(
          sequences,
          @strategy.graph_task_count(physical),
          capacity_plan=Some(configuration),
          retained_inputs=Some(inputs.map(_ => -1)),
          max_rows~,
          runtime_admission=true,
        )
        is None,
      )
    }
    Err(issue) =>
      match issue {
        Unsupported =>
          fail("original independent Whole Input Plan: Unsupported")
        ForeignOriginal =>
          fail("original independent capture Plan: ForeignOriginal")
        InsufficientCapacity =>
          fail("original independent capture Plan: InsufficientCapacity")
        Sequence(_) => fail("original independent capture Plan: Sequence")
        _ => fail("original independent capture Plan: another original issue")
      }
  }
}
