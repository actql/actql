///|
// Independent ASCII canonical fixture and the known SHA-256 of exactly abc.
// The fixture issuer owns the occurrence; no Program authors this envelope.
fn model_content_preflight_fixture(live : Ref[Bool]) -> ModelContentInput {
  let wire =
    #|{"$actql_ref":"content","content_ref_cid":"sha256:e8f5cd0533cdbd53146aa119851d1da90cbf3c5a4a40103077d49ad79fac3e2a","media_type":"application/pdf","metadata":{"availability_evidence_cid":"sha256:8888888888888888888888888888888888888888888888888888888888888888","capture_authority":"read_content","content_cid":"sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","content_store_id":"fixture","data_classification":"internal","effective_data_policy_cid":"sha256:6666666666666666666666666666666666666666666666666666666666666666","issuer_evidence":{},"media_type":"application/pdf","retention_class":"fixture","size_bytes":3,"storage_scope":"workspace","truncated":false},"version":"actql-content-ref/0.1"}
  let checked = @admitted.issue_reference(
    @admitted.bind_reference_issuer((_, actual) => actual == wire, _ => live.val),
    @contract.content_reference_contract(
      Some("application/pdf"),
      nullable=false,
      max_name_bytes=128,
    ).unwrap(),
    wire,
    { max_bytes: 4096, max_nodes: 100, max_depth: 8, max_text_units: 4096, },
  ).unwrap()
  guard checked.value is @admitted.Reference(reference) else {
    abort("fixture Ref")
  }
  let dependency = @environment.read_model_dependency(
    @environment.ModelMediaInput("document"),
    @utf8.encode(
      (
        #|{"payload":{"classifications":["internal"],"complete":true,"egress_scope_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","max_bytes":4096,"max_frames":null,"max_pages":4,"media_type":"application/pdf","regions":["fixture-region"],"transfer_method":"inline_bytes"},"self_cid":"sha256:ece55a0064625c262ee09ae48b8293377848469876c77b1c19718dab759280fe","version":"actql-model-media-input/0.1"}
      ),
    ),
    "sha256:ece55a0064625c262ee09ae48b8293377848469876c77b1c19718dab759280fe",
    { max_bytes: 4096, max_nodes: 100, max_depth: 8, max_members: 10, },
    4096,
  ).unwrap()
  let task = @environment.model_execution_task(provider_admission_fixture().0)
  let request : ModelRequest = {
    task,
    slot: 0,
    slot_cid: "sha256:1111111111111111111111111111111111111111111111111111111111111111",
    fixed_request_cid: "sha256:2222222222222222222222222222222222222222222222222222222222222222",
    key: [],
    inputs: [("document", checked)],
  }
  // Whitebox construction isolates physical validation. Static declared-role
  // admission is tested through real task/dependency readers in check_environment;
  // this scalar fixture Task is not a public typed-media execution proof.
  {
    request,
    role: "document",
    item: -1,
    reference,
    dependency,
    media_type: "application/pdf",
    content_cid: "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    size_bytes: 3L,
    classification: "internal",
    policy_cid: "sha256:6666666666666666666666666666666666666666666666666666666666666666",
  }
}

///|
fn model_content_preflight_check(
  input : ModelContentInput,
  physical_live : Ref[Bool],
) -> ModelContentByteCheck {
  start_model_content_byte_check(
    input,
    "fixture-region",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    Some(1L),
    None,
    () => physical_live.val,
  ).unwrap()
}

///|
test "Model Content preflight validates exact bytes without another payload copy" {
  let live = Ref(true)
  let physical_live = Ref(true)
  let input = model_content_preflight_fixture(live)
  let check = model_content_preflight_check(input, physical_live)
  assert_eq(update_model_content_bytes(check, @utf8.encode("a")).unwrap(), 1)
  assert_eq(update_model_content_bytes(check, @utf8.encode("bc")).unwrap(), 2)
  let admission = finish_model_content_bytes(check).unwrap()
  assert_true(model_content_admission_current(admission))
  assert_true(finish_model_content_bytes(check) is Err(Closed))
  assert_true(
    update_model_content_bytes(check, @utf8.encode("")) is Err(Closed),
  )
  // Independent 3 bytes + 128 metadata reservation, not measured from a run.
  assert_true(
    model_content_admissions_match(input.request, [admission], 131L) is Ok(_),
  )
  assert_true(
    model_content_admissions_match(input.request, [admission], 130L)
    is Err(ByteLimit),
  )
}

///|
test "Model Content preflight rejects incomplete wrong and excess bytes" {
  let input = model_content_preflight_fixture(Ref(true))
  for body in ["ab", "abd"] {
    let check = model_content_preflight_check(input, Ref(true))
    ignore(update_model_content_bytes(check, @utf8.encode(body)).unwrap())
    assert_true(finish_model_content_bytes(check) is Err(ContentIdentity))
  }
  let check = model_content_preflight_check(input, Ref(true))
  assert_true(
    update_model_content_bytes(check, @utf8.encode("abcd")) is Err(ByteLimit),
  )
  assert_true(finish_model_content_bytes(check) is Err(Closed))
  let chunk = model_content_preflight_check(input, Ref(true))
  assert_true(
    update_model_content_bytes(chunk, Bytes::make(257, b'a')) is Err(ChunkLimit),
  )
}

///|
test "Model Content preflight preserves media classification region and applicable limits" {
  let input = model_content_preflight_fixture(Ref(true))
  let egress = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  assert_true(
    start_model_content_byte_check(
      { ..input, classification: "public", },
      "fixture-region",
      egress,
      Some(1L),
      None,
      () => true,
    )
    is Err(Classification),
  )
  assert_true(
    start_model_content_byte_check(
      input,
      "foreign-region",
      egress,
      Some(1L),
      None,
      () => true,
    )
    is Err(Region),
  )
  assert_true(
    start_model_content_byte_check(
      input,
      "fixture-region",
      "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      Some(1L),
      None,
      () => true,
    )
    is Err(EgressScope),
  )
  for pages in [None, Some(0L), Some(5L)] {
    assert_true(
      start_model_content_byte_check(
        input,
        "fixture-region",
        egress,
        pages,
        None,
        () => true,
      )
      is Err(PageLimit),
    )
  }
  assert_true(
    start_model_content_byte_check(
      input,
      "fixture-region",
      egress,
      Some(1L),
      Some(1L),
      () => true,
    )
    is Err(FrameLimit),
  )
}

///|
test "Model Content preflight rechecks original Ref and physical custody" {
  for original in [true, false] {
    let live = Ref(true)
    let physical_live = Ref(true)
    let input = model_content_preflight_fixture(live)
    let check = model_content_preflight_check(input, physical_live)
    if original {
      live.val = false
    } else {
      physical_live.val = false
    }
    assert_true(
      update_model_content_bytes(check, @utf8.encode("abc"))
      is Err(ReferenceUnavailable),
    )
    assert_true(finish_model_content_bytes(check) is Err(Closed))
  }
  for original in [true, false] {
    let live = Ref(true)
    let physical_live = Ref(true)
    let input = model_content_preflight_fixture(live)
    let check = model_content_preflight_check(input, physical_live)
    ignore(update_model_content_bytes(check, @utf8.encode("abc")).unwrap())
    let admission = finish_model_content_bytes(check).unwrap()
    if original {
      live.val = false
    } else {
      physical_live.val = false
    }
    assert_false(model_content_admission_current(admission))
    assert_true(
      model_content_admissions_match(input.request, [admission], 131L)
      is Err(ReferenceUnavailable),
    )
  }
}

///|
test "Model physical plans cannot omit or substitute a Content occurrence" {
  let input = model_content_preflight_fixture(Ref(true))
  let check = model_content_preflight_check(input, Ref(true))
  ignore(update_model_content_bytes(check, @utf8.encode("abc")).unwrap())
  let admission = finish_model_content_bytes(check).unwrap()
  let mut sends = 0
  let invoke = () => {
    sends += 1
    Err(ProviderError)
  }
  let quantities : @resources.QuantityAmounts = {
    tokens: 33L,
    cost_units: 0L,
    duration_ms: 500L,
  }
  assert_true(
    model_physical_request_plan(input.request, 131L, quantities, invoke)
    is Err(Content(Request)),
  )
  let plan = model_physical_request_plan(
    input.request,
    131L,
    quantities,
    invoke,
    attachments=[admission],
  ).unwrap()
  assert_true(physical_equal(plan.request, input.request))
  let substituted = { ..input.request, slot: 1, }
  assert_true(
    model_physical_request_plan(substituted, 131L, quantities, invoke, attachments=[
      admission,
    ])
    is Err(Content(Request)),
  )
  let other = model_content_preflight_fixture(Ref(true))
  let equal_envelope = { ..input.request, inputs: other.request.inputs, }
  assert_true(
    model_physical_request_plan(equal_envelope, 131L, quantities, invoke, attachments=[
      admission,
    ])
    is Err(Content(Request)),
  )
  assert_true(
    model_physical_request_plan(input.request, 262L, quantities, invoke, attachments=[
      admission, admission,
    ])
    is Err(Content(Request)),
  )
  assert_eq(sends, 0)
}
