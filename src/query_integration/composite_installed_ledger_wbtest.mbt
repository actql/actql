///|
// The original independent composite JSON control is legal before any Source
// read. Its two installed budgets must retain the same checked requirements.
test "original composite Vector Sources prepare the installed multi-capture ledger" {
  let (environment, context) = composite_vector_source_preparation_context()
  let original = @local_input.prepare_local_submitted_input(
    composite_vector_source_preparation_normal_inputs()[0],
    environment,
    Some(context),
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  let prepared = @local_input.local_prepared_program(
    @local_input.local_submitted_preparation_input(original),
  )
  let graph = @publication_host.prepared_client_graph(prepared)
  assert_eq(@strategy.graph_captured_prefix(graph), 2)
  let (registry, values, fragment, ordered) = acquired_serialization_contracts()
  for count in 1..<=@strategy.graph_task_count(graph) {
    let prefix = @client_local_host.prepare_client_local_sequences(
      prepared,
      registry,
      values,
      fragment,
      ordered,
      task_count=Some(count),
    )
    println("COMPOSITE_SEQUENCE prefix=\{count} ready=\{prefix is Some(_)}")
    let owner = @strategy.graph_task_owner(graph, count - 1).unwrap()
    match
      @lower.prepare_sequence(
        owner,
        @publication_host.prepared_client_values_sequence_limits(prepared),
      ) {
      Ok(_) => ()
      Err(VectorFailure(index, issue)) =>
        println(
          "COMPOSITE_LOWER task=\{count - 1} vector=\{index} " +
          @debug.to_string(issue),
        )
      Err(KernelFailure(index, _)) =>
        println("COMPOSITE_LOWER task=\{count - 1} kernel=\{index}")
      Err(_) =>
        println("COMPOSITE_LOWER task=\{count - 1} other_sequence_issue")
    }
    if prefix is None {
      composite_installed_fragment_counter(prepared, count - 1)
      break
    }
  }
  let sequences = @client_local_host.prepare_client_local_sequences(
    prepared, registry, values, fragment, ordered,
  )
  assert_true(
    sequences is Some(_),
    msg="original composite generated sequences",
  )
  let declaration = composite_vector_source_test_declaration(true).unwrap()
  let (query, evidence) = query_evidence_test_bodies()
  let capacities = Array::makei(2, task => {
    let requirement = @client_local_host.prepare_local_query_requirement(
      prepared, task, 0, registry, values, fragment, ordered,
    ).unwrap()
    let acquisition = @row_host.prepare_row_acquisition(
      declaration,
      requirement,
      @identity.stringify_value(query, 100000, 10000, 100),
      @identity.stringify_value(evidence, 100000, 10000, 100),
    ).unwrap()
    @client_local_host.installed_row_capture_capacity(acquisition).unwrap()
  })
  let ledger = @client_local_host.prepare_multi_captured_local_installed_ledger(
    prepared,
    capacities,
    [4096L, 4096L],
    [4096L, 4096L],
    registry,
    values,
    fragment,
    ordered,
  )
  assert_true(ledger is Some(_), msg="original composite installed ledger")
  let usage = @resources.ledger_usage(ledger.unwrap())
  assert_eq(usage.attempts, 0)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_transfer_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
}

///|
// Reproduce the existing Local context preparation with its original ceilings.
// This diagnostic neither executes a task nor supplies a replacement context.
fn composite_installed_fragment_counter(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
) -> Unit raise {
  let graph = @publication_host.prepared_client_graph(prepared)
  let owner = @strategy.graph_task_owner(graph, task).unwrap()
  let sequence = @lower.prepare_sequence(
    owner,
    @publication_host.prepared_client_values_sequence_limits(prepared),
  ).unwrap()
  let contexts = []
  for step in 0..<@lower.sequence_count(sequence) {
    guard @lower.sequence_step(sequence, step) is Some(@lower.RowStep(kernel)) else {
      continue
    }
    let ordered = @lower.kernel_body(kernel) is @lower.OrderedBindings(_)
    let required = match @lower.kernel_body(kernel) {
      @lower.SnapshotMap(_)
      | @lower.OrderedBindings(_)
      | @lower.Filter(_)
      | @lower.AssertAll(_) => true
      _ => false
    }
    if !required {
      continue
    }
    println("COMPOSITE_FRAGMENT step=\{step} start")
    let fragment = @lower.prepare_fragment_pipeline(sequence, step, {
      max_roots: 100,
      max_pointer_bytes: 10000,
      max_work: 100000,
    }).unwrap()
    println("COMPOSITE_FRAGMENT step=\{step} pipeline")
    let logical : @lower.FragmentRowLimits = {
      max_input_rows: 100L,
      max_value_bytes: 10000L,
      max_live_value_bytes: 100000L,
      max_work: 10000000L,
    }
    let request = @lower.prepare_fragment_request(
      fragment,
      100L,
      10000L,
      row_limits=if ordered { Some(logical) } else { None },
    ).unwrap()
    println("COMPOSITE_FRAGMENT step=\{step} request")
    let context = @execution.prepare_runtime_fragment(
      request,
      test_fragment_contract(),
      {
        max_roots: 100,
        max_nodes: 10000,
        max_work: 100000,
        max_text_bytes: 10000,
        max_links: 10000,
      },
      registry_limits(),
      logical,
      ordered=if ordered {
        Some(
          @execution.admit_ordered_contract(
            registered_relation_contracts(),
            registered_ordered(),
            registry_limits(),
          ).unwrap(),
        )
      } else {
        None
      },
    )
    match context {
      Ok(value) => contexts.push(value)
      Err(Material(_)) => println("COMPOSITE_FRAGMENT material_failure")
      Err(Candidate(_)) => println("COMPOSITE_FRAGMENT candidate_failure")
      Err(Admission(_)) => println("COMPOSITE_FRAGMENT admission_failure")
      Err(Runtime(_)) => println("COMPOSITE_FRAGMENT runtime_failure")
    }
    assert_true(context is Ok(_), msg="original composite fragment context")
  }
  let generated = @publication_host.prepare_client_task_sequence(
    prepared,
    task,
    registered_relation_contracts(),
    contexts,
    @publication_host.prepared_client_values_sequence_limits(prepared),
    100000,
    10000,
    prepared_sequence=Some(sequence),
  )
  println("COMPOSITE_GENERATED task=\{task} ready=\{generated is Ok(_)}")
}
