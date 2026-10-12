///|
/// The external Native harness runs this case in separate, exited processes.
/// This is original-journal custody acceptance, not public CLI execution or
/// Provider success. The receiver uses only the saved original reference.
test "Native saved Effect response handoff reads original custody without preparation or dispatch" {
  let phase = @env.get_env_var("ACTQL_TEST_NATIVE_EFFECT_RESPONSE_PHASE")
  assert_true(phase is None || phase == Some("write") || phase == Some("read"))
  let name = "client-effect-response-process"
  if phase != Some("read") {
    let (database, journal, request, _, dispatch) = response_test_dispatch(name)
    journal.record_effect_row_unknown(dispatch).unwrap() |> ignore
    journal
    .record_effect_row_response(dispatch, response_test_value(), 4096)
    .unwrap()
    let record = journal.lookup(request, true).unwrap()
    guard record is Retained(record) else { fail("original Run missing") }
    for
      (key, value) in [
        ("request", @host.client_request_identity_record_wire(request).unwrap()),
        ("dispatch", dispatch.dispatching.cid),
        (
          "definition",
          @publication.publication_contract_identity(record.definition),
        ),
        ("revision", record.revision.to_string()),
      ] {
      database
      .insert("test_effect_response_reference", key, @utf8.encode(value))
      .unwrap()
      |> ignore
    }
    database.close_checked().unwrap()
  }
  if phase != Some("write") {
    let database = epoch_test_database(name)
    let saved = (key : String) => {
      @utf8.decode(
        database.read("test_effect_response_reference", key).unwrap().body,
      )
    }
    // No preparation, compilation, admission, resume claim or Provider occurs.
    let request = @host.admit_client_request_identity_record_wire(
      saved("request"),
    ).unwrap()
    let journal = open_native_client_run_journal(database, 8).unwrap()
    let (locator, _, _) = effect_row_test_binding(request)
    for _ in 0..<2 {
      let original = journal
        .restore_effect_row_observation(request, locator, () => true)
        .unwrap()
        .unwrap()
      assert_eq(original.dispatching.cid, saved("dispatch"))
      assert_eq(original.dispatching.attempt_sequence, 1L)
      let response = journal
        .effect_row_response(original, () => true, 4096)
        .unwrap()
        .unwrap()
      assert_eq(response.body, b"\x00\xffe\xcc\x81\xc3\xa9\rX\nY\r\nZ")
      assert_eq(response.status_code, 409)
      assert_eq(response.credential_use_cid, "sha256:" + "7".repeat(64))
      assert_true(
        journal.effect_row_response(original, () => false, 4096)
        is Err(AuthorizationDenied),
      )
      let row = journal
        .lookup_effect_row(request, locator, () => true)
        .unwrap()
        .unwrap()
      assert_eq(@effect.effect_ledger_entry_state_code(row), 5)
      guard journal.lookup(request, true) is Ok(Retained(record)) else {
        fail("original Run missing")
      }
      assert_eq(
        @publication.publication_contract_identity(record.definition),
        saved("definition"),
      )
      assert_eq(record.revision.to_string(), saved("revision"))
      assert_false(journal.claim_physical_start(request, true).unwrap())
    }
    database.close_checked().unwrap()
  }
}
