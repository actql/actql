///|
// Real checked Whole input and serialization components. Source observations
// are synthetic DATA; physical provider, publication and close acceptance are
// separately exercised by the ordinary Host consumer.
fn serialization_whole_capture_document(effect : Bool) -> String {
  let capture =
    #|{"id":"capture","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"select":["id","amount"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","amount"]}}}
  let content =
    #|{"id":"content","inputs":{"rows":{"result":{"stage":"capture","result":"rows"}}},"steps":[{"assert_rows":{"unique_by":["id"]}},{"serialize":{"format":"jsonl","fields":["id","amount"],"order_by":[{"id":"asc"}],"name":"out.jsonl","bounds":{"max_rows":2,"max_bytes":128}},"as":"attachment"}],"results":{"file":{"from":"attachment","fields":["name","content"]}}}
  let apply =
    #|{"id":"apply","inputs":{"attachment":{"result":{"stage":"content","result":"file"}}},"steps":[{"derive":{"value":{"literal":1}},"as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}},"effects":{"save":{"create":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"}}}}}
  "{\"version\":\"actql/0.1\",\"id\":\"whole-content\",\"stages\":[" +
  capture +
  "," +
  content +
  (if effect { "," + apply } else { "" }) +
  "],\"results\":{\"file\":{\"from\":{\"stage\":\"content\",\"result\":\"file\"}}}}"
}

///|
fn serialization_whole_effect_run() -> (
  PreparedClientEffectComputation,
  ClientCompiledRun,
) raise {
  let (_, _, limits) = client_composed_effect_base_fixture()
  let base = admit_client_check_environment(
    local_normalization_environment_wire,
    "sha256:afebeb63f2e0e48434bf005f65ab0af8a0c2704f0afb5a8c70df72e91b26e86e",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let owner = prepare_client_effect_computation(
    serialization_whole_capture_document(true),
    Json,
    client_composed_effect_test_environment(base),
    None,
    [],
    { ..limits, program: client_standard_program_preparation_limits(), },
  ).unwrap()
  let compilation = issue_prepared_client_effect_compilation(
    owner,
    run_materials_manifests(),
    run_materials_limits().sequence,
    1000,
    10000,
    1000000,
    100000,
    100,
  ).unwrap()
  let allowed = issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  (owner, client_effect_allowed_serialization_run(allowed).unwrap())
}

///|
test "Whole serialization retains the original direct Source without a Query requirement" {
  let owner = multi_source_prepared(serialization_whole_capture_document(false))
  let component = issue_prepared_client_acquired_serialization_plan_graph(
    owner,
    1,
    1,
    2,
    128,
    10000,
    run_materials_limits().sequence,
    1000000,
    100000,
    100,
  ).unwrap()
  let captured = mixed_whole_infer_capture(owner, 0, Ref(true))
  let admitted = admit_client_serialization_whole_captured_input(
    owner,
    component,
    captured.0,
    captured.1,
    captured.2,
    captured.3,
    captured.4,
    "sha256:" + "a".repeat(64),
    "2026-11-12T00:00:00.000Z",
    "2026-11-12T00:00:02.000Z",
  ).unwrap()
  assert_true(physical_equal(admitted.owner, owner))
  assert_true(physical_equal(admitted.source, captured.0))
  assert_true(physical_equal(admitted.identity, captured.1))
  assert_eq((admitted.task, admitted.step), (1, 1))
  assert_eq(admitted.named_sources.length(), 1)
  assert_eq(admitted.named_sources[0].0, "remote")
  assert_true(admitted.keyed is None)
}

///|
test "Whole Effect serialization uses the retained original compiled component" {
  let (owner, run) = serialization_whole_effect_run()
  let live = Ref(true)
  let captured = mixed_whole_infer_capture(run.owner, 0, live)
  let admitted = admit_client_effect_serialization_whole_captured_input(
    run,
    owner,
    captured.0,
    captured.1,
    captured.2,
    captured.3,
    captured.4,
    "sha256:" + "a".repeat(64),
    "2026-11-12T00:00:00.000Z",
    "2026-11-12T00:00:02.000Z",
  ).unwrap()
  assert_true(physical_equal(admitted.owner, run.owner))
  assert_true(physical_equal(admitted.source, captured.0))
  assert_true(physical_equal(admitted.identity, captured.1))
  assert_eq(admitted.named_sources[0].0, "remote")
  assert_eq(admitted.named_sources.length(), 1)
  assert_true(admitted.keyed is None)
  live.val = false
  assert_true(
    admit_client_effect_serialization_whole_captured_input(
      run,
      owner,
      captured.0,
      captured.1,
      captured.2,
      captured.3,
      captured.4,
      "sha256:" + "a".repeat(64),
      "2026-11-12T00:00:00.000Z",
      "2026-11-12T00:00:02.000Z",
    )
    is Err(
      @publication.RunEvidenceReferenceMismatch("content_whole_source_owner")
    ),
  )
}

///|
test "Whole serialization refuses foreign owner capacity identity and observation" {
  let (owner, run) = serialization_whole_effect_run()
  let (foreign_owner, foreign_run) = serialization_whole_effect_run()
  let captured = mixed_whole_infer_capture(run.owner, 0, Ref(true))
  let foreign = mixed_whole_infer_capture(foreign_run.owner, 0, Ref(true))
  assert_true(
    admit_client_effect_serialization_whole_captured_input(
      run,
      foreign_owner,
      captured.0,
      captured.1,
      captured.2,
      captured.3,
      captured.4,
      "sha256:" + "a".repeat(64),
      "2026-11-12T00:00:00.000Z",
      "2026-11-12T00:00:02.000Z",
    )
    is Err(@publication.RunEvidenceReferenceMismatch("content_effect_owner")),
  )
  for
    (source, identity, capacity) in [
      (captured.0, captured.1, foreign.2),
      (foreign.0, captured.1, captured.2),
      (captured.0, foreign.1, captured.2),
    ] {
    assert_true(
      admit_client_effect_serialization_whole_captured_input(
        run,
        owner,
        source,
        identity,
        capacity,
        captured.3,
        captured.4,
        "sha256:" + "a".repeat(64),
        "2026-11-12T00:00:00.000Z",
        "2026-11-12T00:00:02.000Z",
      )
      is Err(
        @publication.RunEvidenceReferenceMismatch("content_whole_source_owner")
      ),
    )
  }
  assert_true(
    admit_client_effect_serialization_whole_captured_input(
      run,
      owner,
      captured.0,
      captured.1,
      captured.2,
      captured.3,
      captured.4,
      "sha256:" + "c".repeat(64),
      "2026-11-12T00:00:00.000Z",
      "2026-11-12T00:00:02.000Z",
    )
    is Err(_),
  )
  assert_true(
    admit_client_effect_serialization_whole_captured_input(
      run,
      owner,
      captured.0,
      captured.1,
      captured.2,
      captured.4,
      captured.3,
      "sha256:" + "a".repeat(64),
      "2026-11-12T00:00:00.000Z",
      "2026-11-12T00:00:02.000Z",
    )
    is Err(@publication.RunEvidenceReferenceMismatch("content_source_input")),
  )
}

///|
test "Query serialization still retains its genuine Query capture and cannot become Whole" {
  let owner = multi_source_prepared(
    serialization_whole_capture_document(false).replace(
      old="\"steps\":[{\"select\":[\"id\",\"amount\"]",
      new="\"steps\":[{\"filter\":\"id >= 0\"},{\"select\":[\"id\",\"amount\"]",
    ),
  )
  let component = issue_prepared_client_acquired_serialization_plan_graph(
    owner,
    1,
    1,
    2,
    128,
    10000,
    run_materials_limits().sequence,
    1000000,
    100000,
    100,
  ).unwrap()
  let captured = pure_three_source_capture(owner, 0, Ref(true))
  let admitted = admit_client_serialization_captured_input(
    owner,
    component,
    captured.0,
    captured.1,
    captured.2,
    captured.4,
    captured.3,
    "sha256:" + "a".repeat(64),
    "2026-11-11T00:00:00.000Z",
    "2026-11-11T00:00:02.000Z",
  ).unwrap()
  assert_true(physical_equal(admitted.source, captured.0))
  assert_eq(admitted.named_sources[0].0, "remote")
  assert_true(
    admit_client_serialization_whole_captured_input(
      owner,
      component,
      captured.0,
      captured.1,
      prepare_client_source_acquisition(owner, 0, 0).unwrap(),
      captured.4,
      captured.3,
      "sha256:" + "a".repeat(64),
      "2026-11-11T00:00:00.000Z",
      "2026-11-11T00:00:02.000Z",
    )
    is Err(
      @publication.RunEvidenceReferenceMismatch("content_whole_source_owner")
    ),
  )
}
