///|
fn decode_phase_request(identity : String, attempt : Int) -> DispatchRequest {
  let cid = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  prepare_dispatch_request(
    "coordinator-a", cid, "task-a", attempt, identity, "site-a", 1, cid, "local",
    "local/1", "strategy/1", cid, cid, cid, cid, cid,
  ).unwrap()
}

///|
fn decode_phase_accepted(request : DispatchRequest) -> DispatchRecord {
  let cid = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let site = @site.create_site("site-a", 1, cid, 4, 4, 1048576L, 1048576L).unwrap()
  let journal = create_site_dispatch_journal(site, "actql-remote-site/0.1").unwrap()
  let admission = prepare_dispatch_acceptance(journal, request).unwrap()
  commit_dispatch_acceptance(admission, true).unwrap().1
}

///|
test "durable outer phase returns only original typed fields" {
  let original = decode_phase_request("decode-phases", 41)
  let record = decode_phase_accepted(original)
  let wire = dispatch_record_durable_json(record).unwrap()
  let fields = decode_durable_dispatch_fields(@utf8.encode(wire)) catch {
    _ => fail("expected original outer fields")
  }
  assert_eq(fields.request_json, dispatch_request_json(original).unwrap())
  assert_eq(fields.dispatch_request_cid, dispatch_request_identity(original))
  assert_eq(fields.revision, 0)
  assert_eq(fields.execution_code, 0)
  assert_eq(fields.evidence_code, 0)
  assert_eq(fields.cleanup_code, 0)
  assert_false(fields.material_available)
  assert_false(fields.quarantined_capacity)
  assert_eq(fields.material_generation, "")
  assert_eq(fields.holding_evidence_cid, "")
  assert_eq(fields.execution_evidence_cid, "")
  let admitted = admit_durable_dispatch_record(@utf8.encode(wire)).unwrap()
  assert_eq(
    durable_dispatch_record_request_identity(admitted),
    fields.dispatch_request_cid,
  )
  assert_eq(admitted.body, wire)
}

///|
test "durable decoded fields do not admit foreign request or invalid scalars" {
  let record = decode_phase_accepted(
    decode_phase_request("decode-refusals", 42),
  )
  let wire = dispatch_record_durable_json(record).unwrap()
  for
    changed in [
      wire.replace(old="\"revision\":0", new="\"revision\":-1"),
      wire.replace(old="\"revision\":0", new="\"revision\":2147483648"),
      wire.replace(
        old="\"material_available\":false",
        new="\"material_available\":0",
      ),
      wire.replace(
        old="\"quarantined_capacity\":false",
        new="\"quarantined_capacity\":null",
      ),
      wire.replace(old="actql-remote-dispatch-record/0.1", new="foreign"),
      wire.replace(old="\"request_json\":", new="\"foreign_request\":"),
    ] {
    assert_true(changed != wire)
    assert_true(
      admit_durable_dispatch_record(@utf8.encode(changed))
      is Err(InvalidJournal),
    )
  }
  let foreign = wire.replace(
    old="\"dispatch_request_cid\":\"" +
      dispatch_request_identity(record.request) +
      "\"",
    new="\"dispatch_request_cid\":\"" +
      "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" +
      "\"",
  )
  assert_true(foreign != wire)
  // The first phase is only a typed field projection, never nominal admission.
  assert_true(
    (decode_durable_dispatch_fields(@utf8.encode(foreign)) catch {
      _ => fail("expected outer shape")
    }).dispatch_request_cid !=
    dispatch_request_identity(record.request),
  )
  assert_true(
    admit_durable_dispatch_record(@utf8.encode(foreign)) is Err(InvalidJournal),
  )
  assert_eq(dispatch_record_durable_json(record), Ok(wire))
}
