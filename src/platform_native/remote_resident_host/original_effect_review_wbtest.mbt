///|
/// Codec fixtures, not issued Run, Preview, journal or Store evidence.
fn original_review_codec_request() -> Array[(String, String)] {
  [
    ("authority_scope_cid", "scope"),
    ("request_id", "caller"),
    ("logical_request_scope_cid", "logical"),
    ("intent_fingerprint_cid", "intent"),
    ("program_definition_cid", "program"),
    ("parameter_values_cid", "parameters"),
    ("caller_input_intent_cid", "input"),
  ]
}

///|
fn original_review_codec_wire(review : String) -> String {
  try {
    let writer = @encode.writer(4096, 100, 16)
    @encode.begin_object(writer)
    effect_checkpoint_text(
      writer, "version", "actql-installed-effect-continuation/0.1",
    )
    effect_checkpoint_text(
      writer,
      "run_definition_cid",
      "sha256:" + "a".repeat(64),
    )
    effect_checkpoint_text(writer, "unit_id", "unit")
    effect_checkpoint_text(writer, "preview_cid", "sha256:" + "b".repeat(64))
    @encode.key(writer, "provider")
    @encode.begin_object(writer)
    effect_checkpoint_text(writer, "retained_input_binding", "original input")
    effect_checkpoint_text(writer, "store_authority_cid", "original authority")
    effect_checkpoint_text(writer, "captured_run_wire", "capture codec fixture")
    effect_checkpoint_text(writer, "review_wire", review)
    effect_checkpoint_text(
      writer, "authoring_context_cid", "authoring codec fixture",
    )
    @encode.key(writer, "request")
    @encode.begin_object(writer)
    for (name, value) in original_review_codec_request() {
      effect_checkpoint_text(writer, name, value)
    }
    @encode.end_object(writer)
    @encode.end_object(writer)
    @encode.end_object(writer)
    let value = @canonical.from_json(
      @json.parse(@encode.finish(writer)),
      100,
      16,
      4096,
      data_keys=true,
    )
    @canonical.stringify_value(value, 4096, 100, 16)
  } catch {
    _ => abort("original review codec fixture encoding failed")
  }
}

///|
fn original_review_codec_checkpoint(
  wire : String,
  review : String,
) -> @checkpoint.SealedCheckpoint {
  @checkpoint.seal_checkpoint(
    {
      checkpoint_id: "original-review-codec",
      continuation_state_cid: "sha256:" + @sha.hex(@utf8.encode(wire)),
      subject: @checkpoint.RunUnit(
        run_id="run",
        unit_id="unit",
        run_definition_cid="sha256:" + "a".repeat(64),
      ),
      phase: @checkpoint.Commit,
      kind: @checkpoint.EffectSet,
      required_artifact_cid: "sha256:" + "b".repeat(64),
      review_projection_cid: "sha256:" + @sha.hex(@utf8.encode(review)),
      requirements: [@checkpoint.EffectScopeApproved],
      reason_code: "effect_review",
      human_summary: "Original codec fixture",
      created_at: "2026-10-11T00:00:00.000Z",
      expires_at: "2026-10-11T01:00:00.000Z",
    },
    { max_wire_bytes: 4096, max_nodes: 100, max_depth: 16, },
  ).unwrap()
}

///|
fn original_review_codec_read(
  wire : String,
  checkpoint : @checkpoint.SealedCheckpoint,
  run? : String = "sha256:" + "a".repeat(64),
  unit? : String = "unit",
  binding? : String = "original input",
  authority? : String = "original authority",
  request? : Array[(String, String)] = original_review_codec_request(),
  max_bytes? : Int = 4096,
) -> Result[OriginalEffectReviewFields, ResidentEffectOriginalReviewIssue] {
  original_effect_review_fields(
    wire,
    run,
    unit,
    binding,
    authority,
    request,
    checkpoint,
    { max_wire_bytes: max_bytes, max_nodes: 100, max_depth: 16, },
  )
}

///|
test "original review codec preserves decomposed values and line endings" {
  let review = "e\u0301\r\n\u00e9\n"
  let wire = original_review_codec_wire(review)
  let checkpoint = original_review_codec_checkpoint(wire, review)
  let fields = original_review_codec_read(wire, checkpoint).unwrap()
  assert_eq(fields.review_wire, review)
  assert_eq(fields.captured_wire, "capture codec fixture")
  assert_eq(fields.authoring_cid, "authoring codec fixture")
}

///|
test "original review codec rejects every substituted original request field" {
  let wire = original_review_codec_wire("review")
  let checkpoint = original_review_codec_checkpoint(wire, "review")
  for index in 0..<7 {
    let foreign = original_review_codec_request()
    foreign[index] = (foreign[index].0, "foreign")
    assert_true(
      original_review_codec_read(wire, checkpoint, request=foreign)
      is Err(BindingMismatch),
    )
  }
  assert_true(
    original_review_codec_read(wire, checkpoint, request=[])
    is Err(BindingMismatch),
  )
}

///|
test "original review codec rejects foreign Run unit consumer input and authority" {
  let wire = original_review_codec_wire("review")
  let checkpoint = original_review_codec_checkpoint(wire, "review")
  assert_true(
    original_review_codec_read(wire, checkpoint, run="foreign")
    is Err(BindingMismatch),
  )
  assert_true(
    original_review_codec_read(wire, checkpoint, unit="foreign")
    is Err(BindingMismatch),
  )
  assert_true(
    original_review_codec_read(wire, checkpoint, binding="producer input")
    is Err(BindingMismatch),
  )
  assert_true(
    original_review_codec_read(wire, checkpoint, authority="foreign")
    is Err(BindingMismatch),
  )
}

///|
test "original review codec rejects replacement projection and continuation bytes" {
  let wire = original_review_codec_wire("e\u0301\r\n")
  let checkpoint = original_review_codec_checkpoint(wire, "e\u0301\r\n")
  let normalized = original_review_codec_wire("\u00e9\r\n")
  assert_true(
    original_review_codec_read(normalized, checkpoint) is Err(BindingMismatch),
  )
  let wrong_review = original_review_codec_checkpoint(wire, "foreign")
  assert_true(
    original_review_codec_read(wire, wrong_review) is Err(BindingMismatch),
  )
  let foreign_preview = @checkpoint.seal_checkpoint(
    {
      ..checkpoint.checkpoint,
      required_artifact_cid: "sha256:" + "c".repeat(64),
    },
    { max_wire_bytes: 4096, max_nodes: 100, max_depth: 16, },
  ).unwrap()
  assert_true(
    original_review_codec_read(wire, foreign_preview) is Err(BindingMismatch),
  )
}

///|
test "original review codec rejects noncanonical duplicate and extra fields within original limits" {
  let wire = original_review_codec_wire("review")
  let checkpoint = original_review_codec_checkpoint(wire, "review")
  for
    candidate in [wire + "\n", "{\"unit_id\":\"unit\"," + wire[1:].to_owned()] {
    assert_true(
      original_review_codec_read(candidate, checkpoint)
      is Err(MalformedContinuation),
    )
  }
  let extra = "{\"extra\":\"value\"," + wire[1:].to_owned()
  let value = @canonical.from_json(
    @json.parse(extra),
    100,
    16,
    4096,
    data_keys=true,
  )
  let closed = @canonical.stringify_value(value, 4096, 100, 16)
  assert_true(
    original_review_codec_read(closed, checkpoint) is Err(BindingMismatch),
  )
  assert_true(
    original_review_codec_read(wire, checkpoint, max_bytes=wire.length() - 1)
    is Err(InvalidLimits),
  )
  assert_true(
    original_review_codec_read(wire, checkpoint, max_bytes=0)
    is Err(InvalidLimits),
  )
}
