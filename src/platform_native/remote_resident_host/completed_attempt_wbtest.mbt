///|
fn completed_envelope_fixture() -> (
  ResidentRunAdmission,
  @resident.ResidentSiteDelegation,
  @remote.DispatchRequest,
  String,
) {
  let (admission, request, materials, binding, _) = resident_source_dispatch_fixture()
  let scope = @remote.dispatch_request_execution_scope(request)
  let delegation : @resident.ResidentSiteDelegation = {
    coordinator_authority: @remote.dispatch_request_journal_key(request)[0],
    site_key: scope[0],
    runtime_bundle_cid: scope[2],
    connector_registration: scope[3],
    connector_revision: scope[4],
    strategy_revision: scope[5],
    grant_cid: scope[6],
    evidence_issuer_capability_cid: scope[7],
    budget_cids: [@remote.dispatch_request_budget_cid(request)],
  }
  (
    admission,
    delegation,
    request,
    @remote.remote_poll_dispatch_materials_json(request, binding, materials).unwrap(),
  )
}

///|
test "resident completed envelope keeps the original checked producer and binding" {
  let (admission, delegation, original, envelope) = completed_envelope_fixture()
  let (request, binding, materials) = admit_resident_completed_envelope(
    admission,
    delegation,
    1,
    @remote.dispatch_request_attempt_identity(original).unwrap(),
    envelope,
    "2026-10-06T00:00:00.000Z",
  ).unwrap()
  assert_eq(
    @remote.dispatch_request_identity(request),
    @remote.dispatch_request_identity(original),
  )
  assert_true(@remote.remote_input_binding_matches_dispatch(binding, original))
  assert_true(
    resident_source_dispatch_role(materials, original)
    is Ok(InternalSourceProducer),
  )
  assert_eq(
    @strategy.graph_task_count(@host.prepared_client_graph(materials.prepared)),
    2,
  )
}

///|
test "resident completed envelope refuses another attempt generation and authority before native selection" {
  let (admission, delegation, request, envelope) = completed_envelope_fixture()
  let attempt = @remote.dispatch_request_attempt_identity(request).unwrap()
  assert_true(
    admit_resident_completed_envelope(
      admission, delegation, 1, "another-attempt", envelope, "2026-10-06T00:00:00.000Z",
    )
    is Err(EnvelopeMissing),
  )
  assert_true(
    admit_resident_completed_envelope(
      admission, delegation, 2, attempt, envelope, "2026-10-06T00:00:00.000Z",
    )
    is Err(Refused(@resident.StaleGeneration)),
  )
  assert_true(
    admit_resident_completed_envelope(
      admission,
      { ..delegation, coordinator_authority: "foreign-authority", },
      1,
      attempt,
      envelope,
      "2026-10-06T00:00:00.000Z",
    )
    is Err(Refused(@resident.ForeignCoordinator)),
  )
  assert_true(
    admit_resident_completed_envelope(
      admission,
      { ..delegation, grant_cid: "sha256:" + "f".repeat(64), },
      1,
      attempt,
      envelope,
      "2026-10-06T00:00:00.000Z",
    )
    is Err(Refused(@resident.ForeignGrant)),
  )
}

///|
test "resident completed envelope refuses expired run foreign Source and missing materials" {
  let (admission, delegation, request, envelope) = completed_envelope_fixture()
  let attempt = @remote.dispatch_request_attempt_identity(request).unwrap()
  assert_true(
    admit_resident_completed_envelope(
      admission, delegation, 1, attempt, envelope, "2100-01-01T00:00:00.000Z",
    )
    is Err(Refused(@resident.NotCurrent)),
  )
  assert_true(
    admit_resident_completed_envelope(
      {
        ..admission,
        source: Some(("connector://other/source#v", "sha256:" + "f".repeat(64))),
      },
      delegation,
      1,
      attempt,
      envelope,
      "2026-10-06T00:00:00.000Z",
    )
    is Err(Refused(@resident.ForeignSource)),
  )
  let (_, _, _, binding, _) = resident_source_dispatch_fixture()
  assert_true(
    admit_resident_completed_envelope(
      admission,
      delegation,
      1,
      attempt,
      @remote.remote_poll_dispatch_json(request, binding).unwrap(),
      "2026-10-06T00:00:00.000Z",
    )
    is Err(EnvelopeMissing),
  )
}
