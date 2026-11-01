///|
// Pure codec boundary. No Host permission, SQL transaction, checkpoint
// approval, native resource or durable acceptance is supplied by this case.
test "Native Run admission consumes the canonical Common row without rebuilding it" {
  let (request, _, _, definition) = journal_test_run(
    "canonical-read-request", "canonical-read-run",
  )
  let record : NativeClientRunRecord = {
    request,
    definition,
    dispatch_reserved: false,
    physical_start_claimed: false,
    cancellation_requested: false,
    publication_binding: None,
    publication_policy_originals: None,
    effect_material_originals: None,
    task_materials_cid: None,
    local_run_policy_originals: None,
    run_observation_originals: None,
    observation_original: None,
    revision: 0L,
    checkpoint: None,
  }
  // The one explicit write below encodes once. Reads retain that complete
  // Common canonical comparison; they add zero Native outer encodings.
  let body = run_record_body(record).unwrap()
  let decoded = read_run_record({ body, revision: 0L, }).unwrap()
  assert_eq(
    @host.client_request_scope_cid(decoded.request),
    @host.client_request_scope_cid(request),
  )
  assert_eq(
    @publication.publication_contract_identity(decoded.definition),
    @publication.publication_contract_identity(definition),
  )
  assert_false(decoded.dispatch_reserved)
  assert_false(decoded.physical_start_claimed)
  assert_true(decoded.checkpoint is None)
  let wire = @utf8.decode(body)
  assert_true(
    read_run_record({ body: @utf8.encode(" " + wire), revision: 0L, })
    is Err(CustodyLost),
  )
  let unknown = wire.replace_all(
    old="\"version\":",
    new="\"unrecognized\":null,\"version\":",
  )
  assert_true(
    read_run_record({ body: @utf8.encode(unknown), revision: 0L, })
    is Err(CustodyLost),
  )
  let duplicate = "{\"dispatch_reserved\":false," + wire[1:].to_owned()
  assert_true(
    read_run_record({ body: @utf8.encode(duplicate), revision: 0L, })
    is Err(CustodyLost),
  )
  let physical : @host.ClientRunJournalEncoding = {
    request,
    definition,
    dispatch_reserved: true,
    physical_start_claimed: true,
    cancellation_requested: false,
    publication_binding: None,
    publication_policy_originals: None,
    effect_material_originals: None,
    task_materials_cid: None,
    checkpoint: Some("{}"),
  }
  let invalid_checkpoint = @host.client_run_journal_row_body(physical).unwrap()
  // The outer codec accepts its own canonical string. The Native nested
  // Checkpoint validator must still reject the incomplete original.
  assert_true(
    @host.decode_client_run_journal_row_with_observation_originals(
      invalid_checkpoint,
    )
    is Ok(_),
  )
  assert_true(
    read_run_record({ body: invalid_checkpoint, revision: 0L, })
    is Err(CustodyLost),
  )
  let invalid_claim = @host.client_run_journal_row_body({
    ..physical,
    dispatch_reserved: false,
    checkpoint: None,
  }).unwrap()
  assert_true(
    read_run_record({ body: invalid_claim, revision: 0L, }) is Err(CustodyLost),
  )
  let invalid_observation = @host.client_run_journal_row_body(
    { ..physical, checkpoint: None, },
    run_observation_originals=Some("{}"),
  ).unwrap()
  assert_true(
    @host.decode_client_run_journal_row_with_observation_originals(
      invalid_observation,
    )
    is Ok(_),
  )
  assert_true(
    read_run_record({ body: invalid_observation, revision: 0L, })
    is Err(CustodyLost),
  )
}
