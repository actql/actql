///|
fn sealed_binding_export() -> (
  PublicationOutputExport,
  @publication.PublicationContract,
  @publication.PublicationContract,
  @publication.PublicationContract,
  @payload.PublicationPayloadRequest,
) {
  let parent = retry_export()
  let (run, invocation, retention) = storage_binding_context()
  while parent.next().unwrap() is Some(_) {

  }
  parent.finish().unwrap() |> ignore
  let cid = fn(ch : String) { "sha256:" + ch.repeat(64) }
  parent
  .issue_result_evidence(
    cid("1"),
    [cid("2")],
    @publication.publication_contract_identity(run),
    cid("4"),
    cid("5"),
    100000,
    10000,
    100,
  )
  .unwrap()
  parent.issue_artifact(invocation, retention, 100000, 10000, 100).unwrap()
  |> ignore
  let request = parent
    .prepare_payload_request(cid("a"), cid("b"), cid("c"), 19L)
    .unwrap()
  (parent, run, invocation, retention, request)
}

///|
fn sealed_binding_writing(
  request : @payload.PublicationPayloadRequest,
) -> @payload.PublicationPayloadRecord {
  let record = @payload.prepare_publication_payload_record(request)
  @payload.commit_publication_payload_transition(
    @payload.prepare_publication_payload_reserved(record).unwrap(),
    true,
  ).unwrap()
  |> ignore
  @payload.commit_publication_payload_transition(
    @payload.prepare_publication_payload_writing(record).unwrap(),
    true,
  ).unwrap()
  |> ignore
  @payload.commit_publication_payload_transition(
    @payload.prepare_publication_payload_owned(record, {
      device: 7UL,
      inode: 9UL,
    }).unwrap(),
    true,
  ).unwrap()
  |> ignore
  record
}

///|
fn sealed_binding_finish(
  request : @payload.PublicationPayloadRequest,
  bytes : Int64,
  digest : String,
) -> @payload.PublicationPayloadRecord {
  let record = sealed_binding_writing(request)
  @payload.commit_publication_payload_transition(
    @payload.prepare_publication_payload_sealed(
      record,
      { device: 7UL, inode: 9UL, size: bytes, },
      "sha256:" + digest,
    ).unwrap(),
    true,
  ).unwrap()
  |> ignore
  record
}

///|
test "original Sealed record feeds existing Result binding with fixed content and schema" {
  let (parent, run, invocation, retention, request) = sealed_binding_export()
  // Independent SHA256 of the original UTF-8 [{"id":1},{"id":2}] (19 bytes).
  let digest = "7dcee6a0c50483d0fb68d53b37822d55409a37928ffa228c6b9a482e3373e770"
  let record = sealed_binding_finish(request, 19L, digest)
  let original = @payload.publication_payload_record_durable_json(record).unwrap()
  let binding = parent
    .issue_sealed_durable_binding(
      run, invocation, retention, record, 100000, 10000, 100,
    )
    .unwrap()
  let wire = @publication.publication_contract_json(binding)
  for
    expected in [
      "\"byte_count\":19",
      "\"row_count\":2",
      "\"result_fields\":[\"id\"]",
      "\"physical_sha256\":\"" + digest + "\"",
      "\"result_schema_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\"",
      "\"codec_contract_cid\":\"sha256:5a95e60847276d02229eba9550dd9808a8a8c2764decd4dad667954f020db7cc\"",
      "\"material_generation_cid\":\"sha256:" + "c".repeat(64) + "\"",
      "\"store_authority_cid\":\"sha256:" + "b".repeat(64) + "\"",
    ] {
    assert_true(wire.contains(expected))
  }
  assert_eq(@payload.publication_payload_record_revision(record), 4)
  assert_eq(
    @payload.publication_payload_record_durable_json(record).unwrap(),
    original,
  )
  assert_true(
    parent.issue_sealed_durable_binding(
      run, invocation, retention, record, 1, 10000, 100,
    )
    is Err(Binding(DurableBinding(_))),
  )
  let borrowed = parent.start_captured_snapshot(100000, 10000, 100).unwrap()
  assert_eq(borrowed.advance(1).unwrap(), (false, 1))
  borrowed.cancel()
  assert_eq(
    @publication.publication_contract_json(
      parent
      .issue_sealed_durable_binding(
        run, invocation, retention, record, 100000, 10000, 100,
      )
      .unwrap(),
    ),
    wire,
  )
  parent.cancel()
}

///|
test "unconfirmed Sealed candidate and opaque custody do not become filesystem binding" {
  let (parent, run, invocation, retention, request) = sealed_binding_export()
  let digest = "7dcee6a0c50483d0fb68d53b37822d55409a37928ffa228c6b9a482e3373e770"
  let record = sealed_binding_writing(request)
  let candidate = @payload.prepare_publication_payload_sealed(
    record,
    { device: 7UL, inode: 9UL, size: 19L, },
    "sha256:" + digest,
  ).unwrap()
  assert_true(
    parent.issue_sealed_durable_binding(
      run, invocation, retention, record, 100000, 10000, 100,
    )
    is Err(InvalidState),
  )
  assert_eq(@payload.publication_payload_record_revision(record), 3)
  @payload.commit_publication_payload_transition(candidate, true).unwrap()
  |> ignore
  let opaque_record = @payload.prepare_publication_payload_record(request)
  @payload.commit_publication_payload_transition(
    @payload.prepare_publication_payload_reserved(opaque_record).unwrap(),
    true,
  ).unwrap()
  |> ignore
  @payload.commit_publication_payload_transition(
    @payload.prepare_publication_payload_writing(opaque_record).unwrap(),
    true,
  ).unwrap()
  |> ignore
  let custody = "sha256:" + "d".repeat(64)
  @payload.commit_publication_payload_transition(
    @payload.prepare_publication_payload_opaque_owned(opaque_record, custody).unwrap(),
    true,
  ).unwrap()
  |> ignore
  @payload.commit_publication_payload_transition(
    @payload.prepare_publication_payload_opaque_sealed(
      opaque_record,
      custody,
      19L,
      "sha256:" + digest,
    ).unwrap(),
    true,
  ).unwrap()
  |> ignore
  assert_true(
    parent.issue_sealed_durable_binding(
      run, invocation, retention, opaque_record, 100000, 10000, 100,
    )
    is Err(InvalidState),
  )
  parent.cancel()
}

///|
test "foreign semantic payload request cannot borrow equal sized original Result binding" {
  let (parent, run, invocation, retention, request) = sealed_binding_export()
  let digest = "7dcee6a0c50483d0fb68d53b37822d55409a37928ffa228c6b9a482e3373e770"
  let fields = [
    @payload.publication_payload_request_result_definition(request),
    @payload.publication_payload_request_logical_relation(request),
    @payload.publication_payload_request_schema(request),
    @payload.publication_payload_request_ordering_evidence(request),
    @payload.publication_payload_request_codec(request),
  ]
  // Change each semantic identity, the expected rows and the exact payload
  // bound independently. Bytes and SHA remain the same original fixed values.
  for changed in 0..<7 {
    let observed = fields.copy()
    if changed < 5 {
      observed[changed] = "sha256:" + "e".repeat(64)
    }
    let foreign = @payload.prepare_publication_payload_request(
      @payload.publication_payload_request_store_authority(request),
      @payload.publication_payload_request_attempt(request),
      @payload.publication_payload_material_identity(request),
      observed[0],
      observed[1],
      observed[2],
      observed[3],
      observed[4],
      if changed == 6 {
        20L
      } else {
        19L
      },
      if changed == 5 {
        3L
      } else {
        2L
      },
    ).unwrap()
    let record = sealed_binding_finish(foreign, 19L, digest)
    assert_true(
      parent.issue_sealed_durable_binding(
        run, invocation, retention, record, 100000, 10000, 100,
      )
      is Err(RequestMismatch),
    )
    assert_eq(@payload.publication_payload_record_revision(record), 4)
  }
  parent.cancel()
}

///|
test "Sealed physical mismatch or original parent close cannot revive Result binding" {
  let (parent, run, invocation, retention, request) = sealed_binding_export()
  let digest = "7dcee6a0c50483d0fb68d53b37822d55409a37928ffa228c6b9a482e3373e770"
  for
    record in [
      sealed_binding_finish(request, 18L, digest),
      sealed_binding_finish(request, 19L, "0".repeat(64)),
    ] {
    assert_true(
      parent.issue_sealed_durable_binding(
        run, invocation, retention, record, 100000, 10000, 100,
      )
      is Err(Binding(Output(ForeignMaterial))),
    )
  }
  let record = sealed_binding_finish(request, 19L, digest)
  assert_true(
    parent.issue_sealed_durable_binding(
      run, run, retention, record, 100000, 10000, 100,
    )
    is Err(
      Binding(
        DurableBinding(
          @publication.DurableBindingWrongContract("run_invocation")
        )
      )
    ),
  )
  parent.cancel()
  assert_true(
    parent.issue_sealed_durable_binding(
      run, invocation, retention, record, 100000, 10000, 100,
    )
    is Err(InvalidState),
  )
  assert_eq(@payload.publication_payload_record_state(record), @payload.Sealed)
}
