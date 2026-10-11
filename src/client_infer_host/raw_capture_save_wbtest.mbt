///|
struct RawSaveFixture {
  active : Execution
  call : @model.ModelPhysicalCall
  registration : @publication_host.ClientModelRawCaptureRegistration
  current : Ref[@authorization.AdmittedAccountConfiguration]
  available : Ref[Bool]
  ready : Ref[Bool]
  calls : Ref[Int]
  work : Int64
}

///|
// Ordinary Program/Entry/physical-call owners, with deterministic transport,
// installation and Store-ACK doubles. This does not assert real persistence.
fn raw_save_fixture() -> RawSaveFixture raise {
  let calls = Ref(0)
  let current = Ref(
    evidence_account(@authorization.Allow, operations=[
      "infer", "model_raw_capture",
    ]),
  )
  let now = Ref("2026-10-02T00:00:00.000Z")
  let ready = Ref(false)
  let captured : Ref[@model.ModelPhysicalCall?] = Ref(None)
  let (active, prefix) = async_response_fixture(
    calls,
    Ref(0),
    Ref(0),
    [],
    ready,
    Ref(true),
    @model.PhysicalUnknown({ input_tokens: None, output_tokens: None, }),
    current~,
    now~,
    observe_call=call => captured.val = Some(call),
  )
  let prepared = prepared_call_set(active).unwrap()
  let scope = @model.prepared_model_scope(prepared).unwrap()
  let available = Ref(true)
  let registration = @publication_host.register_client_model_raw_capture(
    active.dispatch_admission.unwrap(),
    scope,
    raw_registration_policy(active, prepared),
    async_response_profile(),
    async_response_installation(),
    None,
    current.val,
    now.val,
    "sha256:" + "e".repeat(64),
    () => available.val,
    () => Ok((current.val, now.val)),
  ).unwrap()
  let work = match fixture_finish(active, initial_work=prefix) {
    AwaitIo(work~) => work
    _ => abort("original transport must remain pending")
  }
  assert_eq(calls.val, 1)
  {
    active,
    call: captured.val.unwrap(),
    registration,
    current,
    available,
    ready,
    calls,
    work,
  }
}

///|
fn raw_save_fixture_cleanup(value : RawSaveFixture) -> Unit raise {
  if !value.active.cancelled {
    assert_true(cancel(value.active))
  }
  value.ready.val = true
  assert_true(
    fixture_finish(value.active, initial_work=value.work)
    is Failed(Model(@model.UnknownCalls), ..),
  )
  assert_true(!cleanup(value.active).unwrap())
  assert_true(cleanup(value.active).unwrap())
  assert_eq(value.calls.val, 1)
}

///|
test "nominal raw receipt binds the original call and preserves partial raw observations" {
  let original = raw_save_fixture()
  let foreign = raw_save_fixture()
  let content_cid = "sha256:06381b7d11954460d9785b4831b0a42eaa9fdabfb55b3071c107002733517a08"
  let save = @model.observe_model_raw_capture(
    original.call,
    original.registration,
    content_cid,
    4,
    503,
    false,
    "2026-10-02T00:00:00.000Z",
  ).unwrap()
  let bound = @model.model_raw_capture_save_binding(save)
  let (semantic, holding, wire, content, count) = @publication.model_raw_response_store_binding(
    bound,
  )
  assert_true(semantic != content && holding != semantic)
  assert_eq(content, content_cid)
  assert_eq(count, 4)
  assert_true(wire.contains("\"http_status\":503"))
  assert_true(wire.contains("\"transport_eof\":false"))
  assert_true(!wire.contains("response_complete"))
  // The trusted Store port is doubled here; no bare CID constructs a receipt.
  let receipt = @model.acknowledge_saved_model_raw_capture(save).unwrap()
  assert_true(
    physical_equal(
      receipt,
      @model.acknowledge_saved_model_raw_capture(save).unwrap(),
    ),
  )
  let response = @publication.model_raw_response_value(bound)
  assert_true(
    @model.model_saved_raw_receipt_matches(receipt, original.call, response),
  )
  assert_true(
    !@model.model_saved_raw_receipt_matches(receipt, foreign.call, response),
  )
  assert_true(
    @model.observe_model_raw_capture(
      foreign.call,
      original.registration,
      content_cid,
      4,
      503,
      false,
      "2026-10-02T00:00:00.000Z",
    )
    is Err(@model.ForeignCall),
  )
  for count in [-1, 2049] {
    assert_true(
      @model.observe_model_raw_capture(
        original.call,
        original.registration,
        content_cid,
        count,
        503,
        false,
        "2026-10-02T00:00:00.000Z",
      )
      is Err(_),
    )
  }
  assert_true(
    @model.observe_model_raw_capture(
      original.call,
      original.registration,
      content_cid,
      4,
      99,
      false,
      "2026-10-02T00:00:00.000Z",
    )
    is Err(_),
  )
  original.available.val = false
  assert_true(
    @model.acknowledge_saved_model_raw_capture(save)
    is Err(@model.Capture(@publication_host.UnavailableSelection)),
  )
  assert_true(
    @model.model_saved_raw_receipt_matches(receipt, original.call, response),
  )
  assert_eq(@publication.model_raw_response_store_binding(bound).2, wire)
  original.available.val = true
  raw_save_fixture_cleanup(original)
  assert_true(
    !@model.model_saved_raw_receipt_matches(receipt, original.call, response),
  )
  raw_save_fixture_cleanup(foreign)
}

///|
test "raw save acknowledgement refuses revocation and cancellation without erasing custody" {
  for cancel_first in [false, true] {
    let original = raw_save_fixture()
    let save = @model.observe_model_raw_capture(
      original.call,
      original.registration,
      "sha256:06381b7d11954460d9785b4831b0a42eaa9fdabfb55b3071c107002733517a08",
      4,
      503,
      false,
      "2026-10-02T00:00:00.000Z",
    ).unwrap()
    let binding = @publication.model_raw_response_store_binding(
      @model.model_raw_capture_save_binding(save),
    )
    if cancel_first {
      assert_true(cancel(original.active))
      assert_true(
        @model.acknowledge_saved_model_raw_capture(save) is Err(@model.Stopped),
      )
    } else {
      original.current.val = evidence_account(@authorization.Deny, operations=[
        "infer", "model_raw_capture",
      ])
      assert_true(
        @model.acknowledge_saved_model_raw_capture(save)
        is Err(
          @model.Capture(
            @publication_host.Authorization(@authorization.ForeignDecision)
          )
        ),
      )
    }
    assert_eq(
      @publication.model_raw_response_store_binding(
        @model.model_raw_capture_save_binding(save),
      ),
      binding,
    )
    assert_eq(original.calls.val, 1)
    raw_save_fixture_cleanup(original)
  }
}
