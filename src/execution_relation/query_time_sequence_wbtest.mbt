///|
fn query_frame_admission_cid(digit : String) -> String {
  "sha256:" + digit.repeat(64)
}

///|
fn query_frame_admission_template() -> @publication.RunEvidenceValue {
  @publication.seal_run_evidence_value(
    "bound_invocation_template",
    "{\"version\":\"actql-bound-invocation-template/0.1\"," +
    "\"program_definition_cid\":\"" +
    query_frame_admission_cid("1") +
    "\",\"parameter_values_cid\":\"" +
    query_frame_admission_cid("2") +
    "\",\"invocation_bindings_cid\":\"" +
    query_frame_admission_cid("3") +
    "\",\"check_environment_cid\":\"" +
    query_frame_admission_cid("4") +
    "\",\"grammar_manifest_cid\":\"" +
    query_frame_admission_cid("5") +
    "\",\"required_profile_contracts\":[]," +
    "\"barrier_contract_manifest_cid\":\"" +
    query_frame_admission_cid("6") +
    "\",\"source_evidence\":\"unbound\"}",
    16384,
    128,
    8,
  ).unwrap()
}

///|
fn query_frame_admission_plan(
  program : String,
) -> @publication.PublicationContract {
  @publication.seal_publication_contract(
    "compiled_plan",
    "{\"version\":\"actql-compiled-plan/0.1\"," +
    "\"compiler_version\":\"compiler-0.1\"," +
    "\"aoa_ir_version\":\"aoa-ir-0.1\"," +
    "\"executable_plan_cid\":\"" +
    query_frame_admission_cid("0") +
    "\",\"program_definition_cid\":\"" +
    program +
    "\",\"program_semantics_cid\":\"" +
    query_frame_admission_cid("a") +
    "\",\"aoa_contract_cid\":\"" +
    query_frame_admission_cid("b") +
    "\",\"aoa_logical_cid\":\"" +
    query_frame_admission_cid("c") +
    "\"}",
    16384,
    128,
    8,
  ).unwrap()
}

///|
fn query_frame_admission_prepared(
  template : @publication.RunEvidenceValue,
  plan : @publication.PublicationContract,
  decision : String,
) -> @publication.RunEvidenceValue {
  @publication.seal_run_evidence_value(
    "prepared_invocation",
    "{\"version\":\"actql-prepared-invocation/0.1\"," +
    "\"invocation_template_cid\":\"" +
    @publication.run_evidence_value_identity(template) +
    "\",\"compiled_plan_cid\":\"" +
    @publication.publication_contract_identity(plan) +
    "\",\"execution_context_cid\":\"" +
    query_frame_admission_cid("8") +
    "\",\"host_policy_cid\":\"" +
    query_frame_admission_cid("9") +
    "\",\"policy_decision\":\"" +
    decision +
    "\",\"expires_at\":\"2026-09-18T03:00:00.000Z\"}",
    16384,
    128,
    8,
  ).unwrap()
}

///|
fn query_frame_admission_authorization(
  prepared : @publication.RunEvidenceValue,
  decision : String,
  approval : Bool,
) -> @publication.RunEvidenceValue {
  let approval_field = if approval {
    ",\"run_scope_approval_cid\":\"" + query_frame_admission_cid("a") + "\""
  } else {
    ""
  }
  @publication.seal_run_evidence_value(
    "run_authorization",
    "{\"version\":\"actql-run-authorization/0.1\"," +
    "\"prepared_invocation_cid\":\"" +
    @publication.run_evidence_value_identity(prepared) +
    "\",\"execution_context_cid\":\"" +
    query_frame_admission_cid("8") +
    "\",\"host_policy_cid\":\"" +
    query_frame_admission_cid("9") +
    "\",\"decision\":\"" +
    decision +
    "\"" +
    approval_field +
    "}",
    16384,
    128,
    8,
  ).unwrap()
}

///|
fn query_frame_original() -> (
  @publication.RunPublicationAdmission,
  @publication.PublicationContract,
) {
  let template = query_frame_admission_template()
  let plan = query_frame_admission_plan(query_frame_admission_cid("1"))
  let prepared = query_frame_admission_prepared(template, plan, "allow")
  let authorization = query_frame_admission_authorization(
    prepared, "allowed", false,
  )
  let admission = @publication.admit_run_publication(
    template, prepared, authorization, plan,
  ).unwrap()
  let definition = @publication.issue_run_definition(
    admission,
    "scope",
    "original-query",
    query_frame_admission_cid("b"),
    "2026-09-18T00:00:00.000Z",
    "2026-09-18T02:00:00.000Z",
    16384,
    128,
    8,
  ).unwrap()
  (admission, definition)
}

///|
fn query_frame_time() -> @publication.QueryEvaluationTime {
  let (admission, definition) = query_frame_original()
  @publication.bind_query_evaluation_time(
    admission,
    definition,
    query_frame_admission_cid("1"),
    query_frame_admission_cid("a"),
    query_frame_admission_cid("4"),
  ).unwrap()
}

///|
// Publication bodies here are explicit component fixtures. They do not prove
// a Host sample or that this diagnostic sequence is the bound compiled Run.
test "query time invocation copy preserves the original and rejects replacement" {
  let sequence = prepared_sequence(
    row_owner(",{\"derive\":{\"now\":\"current_timestamp()\"}}"),
  )
  let context = sequence_fragment_context(sequence, 1, 2L)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [context],
    ["derive_1"],
    100000,
    10000,
  ).unwrap()
  let time = query_frame_time()
  assert_true(
    bind_generated_sequence_query_time(generated, time, 0, 4) is Err(InputLimit),
  )
  assert_true(
    bind_generated_sequence_query_time(generated, time, 1, 3) is Err(InputLimit),
  )
  let bound = bind_generated_sequence_query_time(generated, time, 1, 4).unwrap()
  assert_true(generated.query_time is None)
  assert_true(context.query_time is None)
  assert_false(physical_equal(bound, generated))
  assert_false(physical_equal(bound.contexts[0], context))
  assert_true(
    bound.query_time is Some(original) && physical_equal(original, time),
  )
  assert_true(
    physical_equal(
      bind_generated_sequence_query_time(bound, time, 0, 0).unwrap(),
      bound,
    ),
  )
  assert_true(
    bind_generated_sequence_query_time(bound, query_frame_time(), 100, 100)
    is Err(InputSet),
  )
  for _ in 0..<2 {
    let complete = execute_generated_sequence(bound, [], {
      rows: run_limits(),
      max_work: 1000000,
      max_frames: 100,
    }).unwrap()
    let output = test_row_output(completed_output(complete, Step(1)).unwrap())
    assert_eq(output.names, ["a", "b", "now"])
    assert_true(
      output.rows[0][2]
      is Captured(@admitted.Timestamp("2026-09-18T00:00:00.000Z")),
    )
  }
}

///|
test "query time invocation bounded rows preserve one original through every advance" {
  let source_owner = row_owner("")
  let source_generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(source_owner),
    [],
    ["values_0"],
    100000,
    10000,
  ).unwrap()
  let source = completed_output(
    execute_generated_sequence(source_generated, [], compute_test_limits()).unwrap(),
    Step(0),
  ).unwrap()
  let receiver = bounded_binding_rows_receiver(
    source_owner,
    metadata_operation=Some(
      "{\"derive\":[{\"now\":\"current_timestamp()\"},{\"same\":\"now = current_timestamp()\"}],\"from\":\"rows\",\"as\":\"derived\"}",
    ),
  )
  let sequence = prepared_sequence(receiver)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [bounded_binding_rows_ordered_context(sequence)],
    [
      @lower.node_id(
        @lower.node_at(@lower.bound_preparation(receiver), 0).unwrap(),
      ),
    ],
    100000,
    10000,
  ).unwrap()
  let generated = bind_generated_sequence_query_time(
    generated,
    query_frame_time(),
    1,
    4,
  ).unwrap()
  let input = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, source_owner, source).unwrap(),
    100,
    10000,
  ).unwrap()
  let execution = start_bounded_binding_rows(
    @bounded.control(),
    generated,
    input,
    100,
    run_limits().input_values,
    run_limits().output_values,
    100000,
    100,
    10000,
    10000,
  ).unwrap()
  let mut completed : CompletedOutput? = None
  for _ in 0..<10000 {
    if completed is None {
      match advance_bounded_binding_rows(execution, 1).unwrap() {
        BoundedBindingRowsContinue(..) => ()
        BoundedBindingRowsComplete(output, ..) => completed = Some(output)
        _ => fail("bound query-time rows did not complete")
      }
    }
  }
  let output = completed.unwrap()
  assert_eq(completed_row_count(output), 2)
  for row in 0..<2 {
    assert_true(
      completed_cell(output, row, 2)
      is Some(Captured(@admitted.Timestamp("2026-09-18T00:00:00.000Z"))),
    )
    assert_true(completed_cell(output, row, 3) is Some(Boolean(true)))
  }
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
}

///|
test "query time invocation aggregate argument retains the same original frame context" {
  let time = query_frame_time()
  let (_, execution, _) = bounded_relation_start(
    "{\"k\":{\"type\":\"number\",\"nullable\":false}}",
    "[{\"k\":1},{\"k\":2}]",
    "\"group\":{\"by\":[],\"aggregates\":{\"newest\":{\"fn\":\"max\",\"expr\":\"current_timestamp()\"}}}",
    "group_0",
    true,
    max_work=100000,
    max_entries=10000,
    constrain=generated => {
      bind_generated_sequence_query_time(generated, time, 1, 4).unwrap()
    },
  )
  match drive_bounded_group(execution.unwrap()) {
    BoundedGroupComplete(output, ..) => {
      assert_eq(completed_row_count(output), 1)
      assert_true(
        completed_cell(output, 0, 0)
        is Some(Captured(@admitted.Timestamp("2026-09-18T00:00:00.000Z"))),
      )
    }
    _ => fail("bound query-time aggregate did not complete")
  }
}
