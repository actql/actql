///|
// Actual checked Run/Scope/read/Model request. Accounting amounts remain the
// existing synthetic custody fixture; no SDK allocation or physical I/O occurs.
fn first_m1_original_request_check(
  projection_work : Int,
  two_eligible? : Bool = false,
) -> Unit raise {
  let environment = @publication_host.admit_client_check_environment(
    first_m1_current_environment,
    first_m1_current_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  assert_eq(first_m1_current_program, first_m1_input_program)
  let program = if two_eligible {
    first_m1_current_program.replace(
      old="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"}]",
      new="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"},{\"id\":\"b\",\"text\":\"hello\"}]",
    )
  } else {
    first_m1_current_program
  }
  let prepared = @publication_host.prepare_effect_free_client_program(
    program,
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  let execution = @publication_host.read_prepared_client_infer_model_execution(
    prepared,
    2,
    @utf8.encode(first_m1_current_execution),
    first_m1_current_execution_cid,
    { max_bytes: 10000, max_nodes: 1000, max_depth: 30, max_members: 1000, },
    100000,
  ).unwrap()
  // This is the admitted original execution ceiling, not the observed row,
  // Slot concurrency, quantity budget or a changed Host/Task limit.
  assert_eq(
    @environment.model_execution_ceiling(execution, @environment.TotalAttempts),
    1L,
  )
  let plan = @publication_host.issue_prepared_client_infer_plan_graph(
    prepared,
    2,
    execution,
    "sha256:" + "b".repeat(64),
    "sha256:" + "c".repeat(64),
    @publication_host.client_standard_values_sequence_limits(),
    100000,
    10000,
    100,
  ).unwrap()
  let dependencies = @environment.read_single_attempt_model_dependencies(
    execution,
    Some(@utf8.encode(first_m1_current_prompt)),
    Some(@utf8.encode(first_m1_current_retry)),
    Some(@utf8.encode(first_m1_current_backoff)),
    { max_bytes: 10000, max_nodes: 1000, max_depth: 30, max_members: 1000, },
    100000,
  ).unwrap()
  let provider = @model.install_async_model_provider("models/fixture").unwrap()
  let admitted = @model.admit_model_provider(
    provider,
    execution,
    dependencies,
    (_, prompt) => {
      @environment.model_openai_chat_instructions(prompt)
      is Some("Original é\r\n")
    },
  ).unwrap()
  let (compiled, definition) = original_input_capacity_run(prepared, plan)
  let limits = standard_limits()
  assert_eq(limits.model.ledger.attempts, 100)
  assert_eq(original_model_ledger_limits(plan, limits.model).attempts, 1)
  let quantities : @model.ModelQuantityCapacity = {
    limits: { tokens: 33L, cost_units: 0L, duration_ms: 500L, },
    per_attempt: { tokens: 33L, cost_units: 0L, duration_ms: 500L, },
  }
  let scope = begin_original_model_read_scope(
    compiled,
    definition,
    plan,
    limits.model,
    Some(quantities),
    3L,
    2L,
    4,
    2,
    0,
  ).unwrap()
  let read = @publication_host.prepare_client_model_read(scope, 7L, 5L).unwrap()
  let started = original_funded_start_from_read(
    prepared,
    2,
    infer_fixture_installed_contracts(),
    infer_fixture_values,
    provider,
    limits,
    compiled,
    definition,
    plan,
    read,
    7L,
    5L,
    100L,
    5L,
  )
  let active = match started {
    Ok(value) => value
    Err(OriginalCapacity(issue)) =>
      abort("OriginalCapacity: " + @debug.to_string(issue))
    Err(Input(issue)) => {
      let label = match issue {
        @input.UnsupportedProgram => "UnsupportedProgram"
        @input.InvalidLimits => "InvalidLimits"
        @input.Preparation(_) => "Preparation"
        @input.Local(_) => "Local"
        @input.Mapping(_) => "Mapping"
        @input.ProducerRead(_) => "ProducerRead"
        @input.ProducerBinding(_) => "ProducerBinding"
        @input.Capture(_) => "Capture"
        @input.RetainedInput(_) => "RetainedInput"
      }
      println("M1_START_REFUSAL Input: " + label)
      abort("Input: " + label)
    }
    Err(Model(issue)) => abort("Model: " + @debug.to_string(issue))
    Err(_) => abort("other original startup refusal")
  }
  assert_eq(active.limits.model.ledger.attempts, 1)
  require_model_call_entry(active).unwrap()
  bind_quantity_capacity(active, quantities).unwrap()
  let egress = @publication_host.admit_prepared_client_infer_egress(
    prepared,
    2,
    execution,
    () => Some(egress_fixture_observation()),
  ).unwrap()
  bind_egress_admission(active, egress).unwrap()
  let starts = Ref(0)
  let advances = Ref(0)
  let observed = Ref(false)
  let rejected = Ref(false)
  let release = Ref(false)
  let original_matches = Ref(false)
  let projection_matches = Ref(false)
  bind_physical_preflight(active, request => {
    starts.val += 1
    original_matches.val = request.slot == 0 &&
      request.key.length() == 1 &&
      @admitted.canonical_scalar_text(request.key[0], 100) == Some("a") &&
      request.inputs.length() == 1 &&
      request.inputs[0].0 == "text" &&
      @node_fixture.client_program_model_request_input(request, "text") ==
      Some("\"hello\"") &&
      @node_fixture.client_program_model_request_generation(request) ==
      Some(("fixture-risk-model", 0.0, 1.0, 32L, Some(-7L)))
    let cursor = @model.start_openai_chat_projection(
      admitted, request, 10000, 1000, 40, 100, projection_work,
    ).unwrap()
    Ok({
      advance: () => {
        advances.val += 1
        if observed.val || rejected.val {
          return Ok(None)
        }
        match @model.advance_openai_chat_projection(cursor) {
          Ok(Some(value)) => {
            projection_matches.val = value ==
              (
                "Original é\r\n", "{\"text\":\"hello\"}", "{\"additionalProperties\":false,\"properties\":{\"reason\":{\"anyOf\":[{\"type\":\"string\"},{\"type\":\"null\"}]},\"risk\":{\"type\":\"string\"}},\"required\":[\"reason\",\"risk\"],\"type\":\"object\"}",
                "sha256:96ac9b2a06dae7a547aba6db6011d92bf6649a8832f65b1b986068b9561c8b31",
                "sha256:6510cda280e9beee95537f359641df15e566d5abf101c85bf3e6a77eba7b3240",
                "sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3",
                "fixture-risk-model",
              )
            @model.retire_openai_chat_projection(cursor)
            observed.val = true
          }
          Err(@model.Limit) => rejected.val = true
          Err(_) => abort("foreign original request")
          Ok(None) => ()
        }
        // No physical Plan/Entry/SDK is created from a read-only projection.
        Ok(None)
      },
      cleanup: () => {
        if !release.val {
          return false
        }
        @model.retire_openai_chat_projection(cursor)
        true
      },
    })
  }).unwrap()
  if two_eligible {
    // Every eligible reservation precedes ALL physical preparation. Keep both
    // actual rows/keys, but the second reserve fails before SDK cursor creation.
    assert_true(
      fixture_finish(active)
      is Failed(Model(@model.Ledger(@resources.AttemptLimit)), ..),
    )
    let rows = active.rows.unwrap()
    assert_eq(@relation.prepared_infer_rows_count(rows), 2)
    for index in 0..<2 {
      assert_true(@relation.prepared_infer_rows_key(rows, index, 0) is Some(_))
      assert_true(
        @relation.prepared_infer_rows_value(rows, index, 0) is Some(_),
      )
    }
    assert_eq(starts.val, 0)
    assert_eq(advances.val, 0)
    let usage = @model.model_execution_resource_usage(active.model.unwrap())
    assert_eq(usage.attempts, 0)
    assert_eq(usage.reserved_attempts, 1)
    assert_true(usage.reserved_retention_bytes > 0L)
    assert_true(usage.reserved_transfer_bytes > 0L)
    assert_true(acquire_output(active) is None)
    assert_true(cleanup(active).unwrap())
    @publication_host.settle_client_model_read(read, true).unwrap()
    assert_true(
      @publication_host.finish_client_model_read_scope(
        scope, compiled, definition, plan, true,
      ).unwrap(),
    )
    assert_eq(starts.val, 0)
    return
  }
  let mut last = 0L
  for _ in 0..<2000 {
    guard advance(active, 1).unwrap() is Continue(work~) else {
      abort("original preparation cannot dispatch without a physical Plan")
    }
    assert_true(work >= last && work - last <= 1L)
    last = work
    if observed.val || rejected.val {
      break
    }
  }
  assert_eq(starts.val, 1)
  // A prepared physical cursor is not an entered Model attempt.
  let usage = @model.model_execution_resource_usage(active.model.unwrap())
  assert_eq(usage.attempts, 0)
  assert_eq(usage.reserved_attempts, 1)
  assert_true(original_matches.val)
  assert_true(advances.val > 0)
  assert_eq(observed.val, projection_work == 10000)
  assert_eq(rejected.val, projection_work == 13)
  assert_eq(projection_matches.val, projection_work == 10000)
  assert_true(active.original_preparation.unwrap().startup is Some(_))
  let rows = active.rows.unwrap()
  assert_eq(@relation.prepared_infer_rows_count(rows), 1)
  assert_true(
    @publication_host.client_infer_call_scope_matches_rows(
      active.call_scope.unwrap(),
      rows,
      active.fixed_request_cid,
    ),
  )
  assert_true(prepared_call_set(active) is None)
  assert_true(cancel(active))
  assert_true(fixture_finish(active, initial_work=last) is Stopped(..))
  let held = @model.model_execution_resource_usage(active.model.unwrap())
  assert_false(cleanup(active).unwrap())
  assert_eq(@model.model_execution_resource_usage(active.model.unwrap()), held)
  assert_true(
    @publication_host.client_model_read_scope_live(
      scope, compiled, definition, plan,
    ),
  )
  release.val = true
  assert_true(cleanup(active).unwrap())
  @publication_host.settle_client_model_read(read, true).unwrap()
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope, compiled, definition, plan, true,
    ).unwrap(),
  )
  assert_true(cleanup(active).unwrap())
  assert_false(
    @publication_host.client_model_read_scope_live(
      scope, compiled, definition, plan,
    ),
  )
  assert_eq(starts.val, 1)
}

///|
test "first M1 original Scope request reaches bounded Common projection before SDK or Entry" {
  first_m1_original_request_check(10000)
}

///|
test "first M1 original Scope projection work refusal keeps same cleanup custody" {
  first_m1_original_request_check(13)
}

///|
test "first M1 original cumulative attempt ceiling rejects two eligible rows before SDK preparation" {
  first_m1_original_request_check(10000, two_eligible=true)
}
