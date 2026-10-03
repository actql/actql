///|
fn invocation_fixture_compiled(
  active : Execution,
  alternate_plan? : Bool = false,
) -> (@publication_host.ClientCompiledRun, @publication.PublicationContract) {
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    100000,
    10000,
    100,
  ).unwrap()
  let plan = if alternate_plan {
    call_identity_plan(active.prepared.unwrap())
  } else {
    active.plan.unwrap()
  }
  let compilation = @publication_host.issue_prepared_client_infer_compilation(
    active.prepared.unwrap(),
    plan,
    manifests,
    1000,
    10000,
    1000000,
    100000,
    100,
  ).unwrap()
  let compiled = @publication_host.issue_client_task_compiled_run(
    active.prepared.unwrap(),
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "infer-scope", "infer-run", "2026-10-02T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  if !alternate_plan && active.phase is Input && active.work == 0L {
    bind_run(active, compiled, definition).unwrap()
  }
  (compiled, definition)
}

///|
fn invocation_fixture_observation(
  active : Execution,
  compiled : @publication_host.ClientCompiledRun,
  records : Array[@publication.RunEvidenceValue],
  changed? : String = "",
) -> @publication.RunEvidenceValue raise {
  let template = @publication_host.client_compiled_run_template(compiled)
  let artifact = @publication_host.client_infer_call_scope_artifact(
    active.call_scope.unwrap(),
  )
  let root : Json = Json::string("sha256:" + "a".repeat(64))
  let fields : Map[String, Json] = {
    "version": Json::string("actql-observation-set/0.1"),
    "invocation_template_cid": Json::string(
      @publication.run_evidence_value_identity(template),
    ),
    "captured_input_artifact_cids": Json::array([
      Json::string(@publication.run_evidence_value_identity(artifact)),
    ]),
    "source_evidence_cids": Json::array([]),
    "data_policy_cid": root,
    "consistency": Json::string("independent_snapshots"),
    "capture_started_at": Json::string("2026-10-02T00:00:00.000Z"),
    "capture_completed_at": Json::string("2026-10-02T00:00:00.000Z"),
    "replayability": Json::object({
      "materialized": Json::boolean(false),
      "availability_evidence_cids": Json::array([]),
    }),
    "model_slot_capture_cids": Json::array(
      records.map(value => {
        Json::string(@publication.run_evidence_value_identity(value))
      }),
    ),
  }
  match changed {
    "input" => fields["captured_input_artifact_cids"] = Json::array([root])
    "missing_input" => fields["captured_input_artifact_cids"] = Json::array([])
    "extra_input" =>
      fields["captured_input_artifact_cids"] = Json::array([
        Json::string(@publication.run_evidence_value_identity(artifact)),
        root,
      ])
    "source" => fields["source_evidence_cids"] = Json::array([root])
    "policy" =>
      fields["data_policy_cid"] = Json::string("sha256:" + "b".repeat(64))
    _ => ()
  }
  @publication.seal_run_evidence_value(
    "observation_set",
    fixture_canonical(Json::object(fields)),
    16384,
    1024,
    20,
  ).unwrap()
}

///|
fn invocation_fixture_verification(
  capture : @model.VerifiedModelCapture,
  observation : @publication.RunEvidenceValue,
  records : Array[@publication.RunEvidenceValue],
) -> @model.ModelObservationVerification raise {
  let verified = @model.start_model_observation_verification(
    capture,
    observation,
    records,
    {
      max_slots: 10,
      max_slot_wire_units: 16384,
      max_work: records.length() + 1,
    },
  ).unwrap()
  for _ in 0..<records.length() {
    assert_true(
      !@model.advance_model_observation_verification(verified, 1).unwrap().0,
    )
  }
  assert_true(
    @model.advance_model_observation_verification(verified, 1).unwrap().0,
  )
  verified
}

///|
fn invocation_fixture_invocation(
  compiled : @publication_host.ClientCompiledRun,
  observation : @publication.RunEvidenceValue,
  capture : @model.VerifiedModelCapture,
  records : Array[@publication.RunEvidenceValue],
) -> @publication.PublicationContract {
  let bindings : Array[@publication.BoundModelSlotCapture] = []
  for index, record in records {
    bindings.push(
      @model.bind_verified_model_slot_capture(capture, index, record).unwrap(),
    )
  }
  @publication.issue_model_run_invocation(
    @publication_host.client_compiled_run_template(compiled),
    observation,
    bindings,
    16384,
    1024,
    20,
  ).unwrap()
}

///|
// These fixtures verify Run/execution references only. Their external roots
// do not attest to attempt adoption, accounting, authorization or Store sync.
test "Infer invocation binding retains the exact Run output independently" {
  let calls = Ref(0)
  let active = failed_outcome_start(
    @model.Timeout,
    calls,
    rows="[{\"id\":\"b\",\"text\":\"second\"},{\"id\":\"a\",\"text\":\"first\"}]",
    mixed=true,
  )
  let (compiled, definition) = invocation_fixture_compiled(active)
  assert_true(fixture_finish(active) is Complete(_, ..))
  let capture = acquire_capture(active).unwrap()
  let records = [
    observation_failure_record(capture, 0),
    slot_binding_seal(
      slot_binding_record(invocation_evidence(active, 1).unwrap()),
    ),
  ]
  let observation = invocation_fixture_observation(active, compiled, records)
  let verified = invocation_fixture_verification(capture, observation, records)
  let invocation = invocation_fixture_invocation(
    compiled, observation, capture, records,
  )
  let binding = bind_invocation(
    active,
    compiled,
    definition,
    verified,
    invocation,
    "sha256:" + "a".repeat(64),
  ).unwrap()
  let consumer = acquire_output(active).unwrap()
  let completed = invocation_binding_output(binding).unwrap()
  assert_eq(@relation.completed_row_count(completed), 2)
  assert_true(
    @relation.completed_cell(completed, 0, 0) is Some(@relation.Text("a")),
  )
  assert_true(
    @relation.completed_cell(completed, 0, 1)
    is Some(@relation.Text("failed:timeout")),
  )
  assert_true(@relation.completed_cell(completed, 0, 2) is Some(@relation.Null))
  assert_true(
    @relation.completed_cell(completed, 1, 0) is Some(@relation.Text("b")),
  )
  assert_true(
    @relation.completed_cell(completed, 1, 1) is Some(@relation.Text("ok")),
  )
  assert_true(
    physical_equal(
      invocation_binding_observation(binding).unwrap(),
      observation,
    ),
  )
  assert_true(
    physical_equal(invocation_binding_invocation(binding).unwrap(), invocation),
  )
  assert_true(@model.cleanup_model_observation_verification(verified).unwrap())
  assert_true(@model.release_verified_model_capture(capture))
  assert_true(!cleanup(active).unwrap())
  assert_true(release_invocation_binding(binding))
  assert_true(!release_invocation_binding(binding))
  assert_true(invocation_binding_output(binding) is None)
  assert_true(invocation_binding_observation(binding) is None)
  assert_true(invocation_binding_invocation(binding) is None)
  assert_true(output(consumer) is Some(_))
  assert_true(!cleanup(active).unwrap())
  assert_true(release_output(consumer))
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 2)
}

///|
test "Infer invocation binding refuses substituted Run plan and execution owners" {
  let calls = Ref(0)
  let active = failed_outcome_start(@model.Timeout, calls)
  let (compiled, definition) = invocation_fixture_compiled(active)
  assert_true(fixture_finish(active) is Complete(_, ..))
  let capture = acquire_capture(active).unwrap()
  let records = [observation_failure_record(capture, 0)]
  let observation = invocation_fixture_observation(active, compiled, records)
  let unverified = @model.start_model_observation_verification(
    capture,
    observation,
    records,
    observation_verification_limits(),
  ).unwrap()
  let invocation = invocation_fixture_invocation(
    compiled, observation, capture, records,
  )
  assert_true(
    bind_invocation(
      active,
      compiled,
      definition,
      unverified,
      invocation,
      "sha256:" + "a".repeat(64),
    )
    is Err(UnverifiedSlots),
  )
  assert_true(@model.cancel_model_observation_verification(unverified))
  assert_true(
    @model.advance_model_observation_verification(unverified, 1)
    is Err(@model.Cancelled),
  )
  assert_true(
    @model.cleanup_model_observation_verification(unverified).unwrap(),
  )
  let verified = invocation_fixture_verification(capture, observation, records)
  let (another_plan, another_definition) = invocation_fixture_compiled(
    active,
    alternate_plan=true,
  )
  assert_true(
    bind_invocation(
      active,
      another_plan,
      another_definition,
      verified,
      invocation,
      "sha256:" + "a".repeat(64),
    )
    is Err(ForeignRun),
  )
  let another = failed_outcome_start(@model.Timeout, calls)
  let (foreign, foreign_definition) = invocation_fixture_compiled(another)
  assert_true(
    bind_invocation(
      active,
      foreign,
      foreign_definition,
      verified,
      invocation,
      "sha256:" + "a".repeat(64),
    )
    is Err(ForeignRun),
  )
  assert_true(fixture_finish(another) is Complete(_, ..))
  let other_capture = acquire_capture(another).unwrap()
  let other_verified = invocation_fixture_verification(
    other_capture, observation, records,
  )
  assert_true(
    bind_invocation(
      active,
      compiled,
      definition,
      other_verified,
      invocation,
      "sha256:" + "a".repeat(64),
    )
    is Err(UnverifiedSlots),
  )
  assert_eq(active.output_uses, 0)
  assert_true(
    @model.cleanup_model_observation_verification(other_verified).unwrap(),
  )
  assert_true(@model.release_verified_model_capture(other_capture))
  assert_true(cleanup(another).unwrap())
  assert_true(@model.cleanup_model_observation_verification(verified).unwrap())
  assert_true(@model.release_verified_model_capture(capture))
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 2)
}

///|
test "Infer invocation binding checks actual input policy and observation references" {
  let calls = Ref(0)
  let active = failed_outcome_start(@model.Timeout, calls)
  let (compiled, definition) = invocation_fixture_compiled(active)
  assert_true(fixture_finish(active) is Complete(_, ..))
  let capture = acquire_capture(active).unwrap()
  let records = [observation_failure_record(capture, 0)]
  let original = invocation_fixture_observation(active, compiled, records)
  let original_invocation = invocation_fixture_invocation(
    compiled, original, capture, records,
  )
  for
    (changed, field) in [
      ("input", "observation.captured_input_artifact_cids"),
      ("missing_input", "observation.captured_input_artifact_cids"),
      ("extra_input", "observation.captured_input_artifact_cids"),
      ("source", "observation.source_evidence_cids"),
      ("policy", "observation.data_policy_cid"),
    ] {
    let observation = invocation_fixture_observation(
      active,
      compiled,
      records,
      changed~,
    )
    let verified = invocation_fixture_verification(
      capture, observation, records,
    )
    let invocation = invocation_fixture_invocation(
      compiled, observation, capture, records,
    )
    guard bind_invocation(
        active,
        compiled,
        definition,
        verified,
        invocation,
        "sha256:" + "a".repeat(64),
      )
      is Err(Evidence(@publication.RunEvidenceReferenceMismatch(actual))) else {
      abort("the changed observation must fail with its exact typed cause")
    }
    assert_eq(actual, field)
    assert_true(
      bind_invocation(
        active,
        compiled,
        definition,
        verified,
        original_invocation,
        "sha256:" + "a".repeat(64),
      )
      is Err(
        Evidence(
          @publication.RunEvidenceReferenceMismatch(
            "invocation.observation_set_cid"
          )
        )
      ),
    )
    assert_eq(active.output_uses, 0)
    assert_true(
      @model.cleanup_model_observation_verification(verified).unwrap(),
    )
  }
  assert_true(@model.release_verified_model_capture(capture))
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 1)
}

///|
test "an Infer execution cannot acquire a Run retrospectively or switch Runs" {
  let calls = Ref(0)
  let active = failed_outcome_start(@model.Timeout, calls)
  let (compiled, definition) = invocation_fixture_compiled(active)
  bind_run(active, compiled, definition).unwrap()
  let other_definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "infer-scope", "other-run", "2026-10-02T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  assert_true(bind_run(active, compiled, other_definition) is Err(ForeignRun))
  assert_true(fixture_finish(active) is Complete(_, ..))
  bind_run(active, compiled, definition).unwrap()
  let (another_compilation, same_definition) = invocation_fixture_compiled(
    active,
  )
  assert_eq(
    @publication.publication_contract_identity(same_definition),
    @publication.publication_contract_identity(definition),
  )
  assert_true(
    bind_run(active, another_compilation, same_definition) is Err(ForeignRun),
  )
  assert_true(cleanup(active).unwrap())
  assert_true(
    bind_run(active, compiled, definition) is Err(IncompleteExecution),
  )
  let late = failed_outcome_start(@model.Timeout, calls)
  assert_true(fixture_finish(late) is Complete(_, ..))
  let (late_compiled, late_definition) = invocation_fixture_compiled(late)
  assert_true(
    bind_run(late, late_compiled, late_definition) is Err(IncompleteExecution),
  )
  let capture = acquire_capture(late).unwrap()
  let records = [observation_failure_record(capture, 0)]
  let observation = invocation_fixture_observation(late, late_compiled, records)
  let verified = invocation_fixture_verification(capture, observation, records)
  let invocation = invocation_fixture_invocation(
    late_compiled, observation, capture, records,
  )
  assert_true(
    bind_invocation(
      late,
      late_compiled,
      late_definition,
      verified,
      invocation,
      "sha256:" + "a".repeat(64),
    )
    is Err(ForeignRun),
  )
  assert_eq(late.output_uses, 0)
  assert_true(@model.cleanup_model_observation_verification(verified).unwrap())
  assert_true(@model.release_verified_model_capture(capture))
  assert_true(cleanup(late).unwrap())
  assert_eq(calls.val, 2)
}

///|
test "zero-key Infer keeps an explicit empty slot inventory at the Run boundary" {
  let calls = Ref(0)
  let active = failed_outcome_start(@model.Timeout, calls, rows="[]")
  let (compiled, definition) = invocation_fixture_compiled(active)
  assert_true(fixture_finish(active) is Complete(_, ..))
  let capture = acquire_capture(active).unwrap()
  let records : Array[@publication.RunEvidenceValue] = []
  let observation = invocation_fixture_observation(active, compiled, records)
  let verified = invocation_fixture_verification(capture, observation, records)
  let invocation = invocation_fixture_invocation(
    compiled, observation, capture, records,
  )
  let binding = bind_invocation(
    active,
    compiled,
    definition,
    verified,
    invocation,
    "sha256:" + "a".repeat(64),
  ).unwrap()
  assert_eq(@publication.model_observation_slot_count(observation), Some(0))
  assert_eq(
    @relation.completed_row_count(invocation_binding_output(binding).unwrap()),
    0,
  )
  assert_true(@model.cleanup_model_observation_verification(verified).unwrap())
  assert_true(@model.release_verified_model_capture(capture))
  assert_true(!cleanup(active).unwrap())
  assert_true(release_invocation_binding(binding))
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 0)
}
