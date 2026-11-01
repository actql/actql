///|
test "single Site missing observation retains original claimed execution Unknown" {
  let definition = single_site_definition()
  let authority = single_site_test_cid("c")
  let task = "original-task"
  let observed = single_site_observation_fixture(
    authority,
    @publication.publication_contract_identity(definition),
    task,
    false,
    false,
  )
  // Isolate an admitted original intent with no returned Site observation.
  // A Host's saved physical-start claim cannot become a retry or publication.
  let intent = @remote.prepare_coordinator_dispatch_intent(
    @remote.create_coordinator_dispatch_journal(authority).unwrap(),
    @remote.durable_coordinator_dispatch_record_request(observed),
  ).unwrap()
  let fields = client_host_project_site_run(
    definition,
    task,
    ["answer"],
    authority,
    @remote.coordinator_dispatch_admission_durable_json(intent).unwrap(),
    "2026-11-01T00:01:00.000Z",
    false,
    true,
  ).unwrap()
  assert_eq(single_site_state_text(fields[0], "status"), "needs_reconciliation")
  assert_eq(fields[1], "unknown")
  assert_eq(fields[2], "pending")
  assert_eq(fields[4], "reconcile")
}
