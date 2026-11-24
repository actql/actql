///|
struct RawSaveFixture {
  active : Execution
  call : @model.ModelPhysicalCall
  registration : @publication_host.ClientModelRawCaptureRegistration
  current : Ref[@authorization.AdmittedAccountConfiguration]
  now : Ref[String]
  available : Ref[Bool]
  ready : Ref[Bool]
  calls : Ref[Int]
  work : Int64
  response : Ref[@model.ModelPhysicalCallPoll]
}

///|
// Ordinary Program/Entry/physical-call owners, with deterministic transport,
// installation and Store-ACK doubles. This does not assert real persistence.
fn raw_save_fixture(
  cleanup_calls? : Array[Bool] = [],
  release? : Ref[Bool] = Ref(true),
  limits? : Limits = standard_limits(),
  structured? : Bool = false,
  foreign_decoder_profile? : Bool = false,
  measured? : Bool = false,
) -> RawSaveFixture raise {
  let calls = Ref(0)
  let current = Ref(
    evidence_account(@authorization.Allow, operations=[
      "infer", "model_raw_capture",
    ]),
  )
  let now = Ref("2026-10-02T00:00:00.000Z")
  let ready = Ref(false)
  let captured : Ref[@model.ModelPhysicalCall?] = Ref(None)
  let response = Ref(
    @model.PhysicalUnknown({ input_tokens: None, output_tokens: None, }),
  )
  let configured = structured || measured
  let profile = if configured {
    structured_raw_fixture_profile()
  } else {
    async_response_profile()
  }
  let (start_original, capacity, provider_original, structured_plan) = if configured {
    let configuration = if measured {
      (
        #|{"adapter_kind":"portable-http","api_mode":"chat-completions","endpoint":"https://fixture.invalid/v1/chat/completions","model_id":"actual-sdk-model","provider_id":"models/fixture","selector":"fixture-risk-model"}
      )
    } else {
      structured_raw_configuration
    }
    let fixture = structured_raw_fixture_binding(configuration)
    (
      Some(() => start_structured_raw_fixture(limits)),
      Some(fixture_quantity_capacity(33L, 500L)),
      Some(fixture),
      Some((active, request, start) => {
        structured_raw_fixture_plan(
          active,
          request,
          fixture.0,
          profile,
          start,
          foreign_decoder_profile,
          configuration,
          measured,
        )
      }),
    )
  } else {
    (None, None, None, None)
  }
  let (active, prefix) = async_response_fixture(
    calls,
    Ref(0),
    Ref(0),
    cleanup_calls,
    ready,
    release,
    response.val,
    current~,
    now~,
    limits~,
    slots=if configured { 1 } else { 2 },
    start_original~,
    capacity?,
    profile~,
    provider_original?,
    structured_plan?,
    observe_call=call => captured.val = Some(call),
    observe_response=Some(() => response.val),
  )
  let prepared = prepared_call_set(active).unwrap()
  let scope = @model.prepared_model_scope(prepared).unwrap()
  let available = Ref(true)
  let registration = @publication_host.register_client_model_raw_capture(
    active.dispatch_admission.unwrap(),
    scope,
    raw_registration_policy(active, prepared, response_profile=profile),
    profile,
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
    now,
    available,
    ready,
    calls,
    work,
    response,
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
test "measured HTTP authenticates the same complete Raw once and retains unobserved transfer" {
  let complete_raw = (value : RawSaveFixture, eof : Bool) => {
    let save = @model.observe_model_raw_capture(
      value.call,
      value.registration,
      "sha256:" + @sha.hex(b"{}"),
      2,
      503,
      eof,
      value.now.val,
    ).unwrap()
    @model.acknowledge_saved_model_raw_capture(save).unwrap()
  }
  let foreign = raw_save_fixture(measured=true)
  let foreign_receipt = complete_raw(foreign, true)
  for
    (scenario, eof, upload, download) in [
      ("complete", true, 1L, 2L),
      ("absent", true, -1L, -1L),
      ("partial", false, 1L, 2L),
      ("size-mismatch", true, 1L, 1L),
      ("foreign", true, 1L, 2L),
    ] {
    let release = Ref(false)
    let value = raw_save_fixture(release~, measured=true)
    let original = value.active.model.unwrap()
    let before = @model.model_execution_resource_usage(original)
    assert_eq(before.attempts, 1)
    assert_eq(before.uncertain_transfer_bytes, 0L)
    assert_true(before.reserved_transfer_bytes > 3L)
    let receipt = if scenario == "foreign" {
      foreign_receipt
    } else {
      complete_raw(value, eof)
    }
    value.response.val = @model.PhysicalIoQuiescent(
      value.call,
      @model.PhysicalMeasuredHttp(
        receipt,
        upload,
        download,
        @model.PhysicalRejected(ProviderError, {
          input_tokens: None,
          output_tokens: None,
        }),
      ),
    )
    value.ready.val = true
    let poll = fixture_finish(value.active, initial_work=value.work)
    if scenario == "foreign" {
      assert_true(poll is Failed(Model(@model.UnknownCalls), ..))
    } else {
      guard poll is Settling(0, work~) else {
        abort("original provider refusal")
      }
      // Another observation of the original terminal cannot reconcile twice.
      assert_true(
        fixture_finish(value.active, initial_work=work) is Settling(0, ..),
      )
      assert_true(
        @model.acknowledge_model_call_settlement(
          call_settlement(value.active).unwrap(),
        ),
      )
      assert_true(
        fixture_finish(value.active, initial_work=work) is AwaitIo(..),
      )
    }
    let pending = @model.model_execution_resource_usage(original)
    assert_eq(
      pending.transferred_bytes,
      if scenario == "complete" {
        3L
      } else {
        0L
      },
    )
    assert_eq(
      pending.reserved_transfer_bytes,
      if scenario == "complete" {
        0L
      } else {
        before.reserved_transfer_bytes
      },
    )
    assert_false(cleanup(value.active).unwrap())
    release.val = true
    async_io_stop_and_cleanup(value.active)
    let after = @model.model_execution_resource_usage(original)
    assert_eq(after.reserved_transfer_bytes, 0L)
    assert_eq(after.attempts, 1)
    assert_eq(after.transferred_bytes, pending.transferred_bytes)
    assert_eq(
      after.uncertain_transfer_bytes,
      if scenario == "complete" {
        0L
      } else {
        before.reserved_transfer_bytes
      },
    )
    assert_eq(value.calls.val, 1)
  }
  foreign.ready.val = true
  async_io_stop_and_cleanup(foreign.active)
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
