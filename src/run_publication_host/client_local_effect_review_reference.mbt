///|
/// Select the adopted private continuation domain. This carries no provider,
/// Store or Checkpoint authority.
pub(all) enum ClientLocalEffectReviewProfile {
  NativeMock
  PythonMock
}

///|
/// The installed Mock review uses the existing complete display policy.
pub fn client_local_effect_review_redaction_policy_cid() -> String {
  "sha256:" +
  @sha.hex(
    b"{\"redacted\":[],\"version\":\"actql-remote-review-redaction/0.1\"}",
  )
}

///|
// One emitter supplies both the allocation-free measurement and exact private
// continuation bytes. It borrows the already captured originals; it performs
// no semantic checking, Source read, compilation, Model or Result execution.
pub fn emit_client_local_effect_review_reference(
  writer : @encode.Writer,
  profile : ClientLocalEffectReviewProfile,
  request : ClientRequestIdentity,
  definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  derivations : Array[@publication.PublicationContract],
  orderings : Array[@publication.PublicationContract],
  retentions : Array[@publication.PublicationContract],
  schema_wires : Array[String],
  codec_cids : Array[String],
  manifest : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  captured : @publication.PublicationContract,
  preview_wire : String,
  authoring_cid : String,
  review_projection_cid : String,
  unit_definition_cid? : String? = None,
  program_id? : String? = None,
) -> Unit raise @encode.EncodeFailure {
  let (version, provider) = match profile {
    NativeMock =>
      (
        "actql-native-local-effect-review-reference/0.1", "native-local-project-mock",
      )
    PythonMock =>
      (
        "actql-python-local-effect-review-reference/0.1", "python-local-project-mock",
      )
  }
  @encode.begin_object(writer)
  for
    (key, value) in [
      ("version", version),
      ("provider", provider),
      ("request_scope_cid", client_request_scope_cid(request)),
      ("authority_scope_cid", client_request_authority_scope_cid(request)),
      ("request_id", client_request_caller_id(request)),
      (
        "run_definition_wire",
        @publication.publication_contract_json(definition),
      ),
      ("invocation_wire", @publication.publication_contract_json(invocation)),
      ("result_manifest_wire", @publication.publication_contract_json(manifest)),
      (
        "computation_receipt_wire",
        @publication.publication_contract_json(receipt),
      ),
      ("captured_run_cid", @publication.publication_contract_identity(captured)),
      ("preview_wire", preview_wire),
      ("review_projection_cid", review_projection_cid),
      ("authoring_context_cid", authoring_cid),
    ] {
    @encode.key(writer, key)
    @encode.string_value(writer, value)
  }
  if unit_definition_cid is Some(unit) {
    @encode.key(writer, "unit_definition_cid")
    @encode.string_value(writer, unit)
  }
  if program_id is Some(program) {
    @encode.key(writer, "program_id")
    @encode.string_value(writer, program)
  }
  @encode.key(writer, "result_definition_wires")
  @encode.begin_array(writer)
  for value in definitions {
    @encode.string_value(writer, @publication.publication_contract_json(value))
  }
  @encode.end_array(writer)
  @encode.key(writer, "result_artifact_wires")
  @encode.begin_array(writer)
  for value in artifacts {
    @encode.string_value(writer, @publication.publication_contract_json(value))
  }
  @encode.end_array(writer)
  for
    (name, originals) in [
      ("result_derivation_wires", derivations),
      ("result_ordering_wires", orderings),
      ("result_retention_wires", retentions),
    ] {
    @encode.key(writer, name)
    @encode.begin_array(writer)
    for original in originals {
      @encode.string_value(
        writer,
        @publication.publication_contract_json(original),
      )
    }
    @encode.end_array(writer)
  }
  for
    (name, originals) in [
      ("result_schema_wires", schema_wires),
      ("result_codec_cids", codec_cids),
    ] {
    @encode.key(writer, name)
    @encode.begin_array(writer)
    for original in originals {
      @encode.string_value(writer, original)
    }
    @encode.end_array(writer)
  }
  @encode.end_object(writer)
}

///|
/// This Checkpoint emits fixed fields, two copies of the Run ID plus its
/// suffixed ID, and one copy of each other original text. Bound JSON escaping
/// independently of the continuation volume and of the admission ceilings.
pub fn client_local_effect_review_checkpoint_wire_bound(
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  created_at : String,
) -> Int? {
  guard @publication.run_definition_run_id(definition) is Ok(run_id) &&
    @publication.run_definition_lifetime(definition) is Some((_, expires)) else {
    return None
  }
  let text = 3L * run_id.length().to_int64() +
    client_effect_compilation_unit_id(allowed.compilation).length().to_int64() +
    created_at.length().to_int64() +
    expires.length().to_int64()
  let bound = 1536L + 6L * text
  Some(Int64::min(65536L, bound).to_int())
}

///|
/// Seal the original Effect review subject and both retained wire identities.
/// The Clock is an already observed caller value. Store confirmation and the
/// waiting Journal CAS use the sealed original separately.
pub fn seal_client_local_effect_review_checkpoint(
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  required_artifact_cid : String,
  continuation_state_cid : String,
  created_at : String,
  review_projection_cid : String,
) -> Result[@checkpoint.SealedCheckpoint, ClientEffectCheckpointBindingIssue] {
  guard @publication.run_definition_run_id(definition) is Ok(run_id) &&
    @publication.run_definition_lifetime(definition) is Some((_, until)) else {
    return Err(ForeignSubject)
  }
  if !client_effect_run_start_current(allowed, definition, created_at) {
    return Err(OriginalLifetime)
  }
  @checkpoint.seal_checkpoint(
    {
      checkpoint_id: run_id + "/effect-review",
      continuation_state_cid,
      subject: @checkpoint.RunUnit(
        run_id~,
        unit_id=client_effect_compilation_unit_id(allowed.compilation),
        run_definition_cid=@publication.publication_contract_identity(
          definition,
        ),
      ),
      phase: @checkpoint.Commit,
      kind: @checkpoint.EffectSet,
      required_artifact_cid,
      review_projection_cid,
      requirements: [@checkpoint.EffectScopeApproved],
      reason_code: "effect_review",
      human_summary: "Approve the complete Effect Set",
      created_at,
      expires_at: until,
    },
    { max_wire_bytes: 65536, max_nodes: 4096, max_depth: 64, },
  ).map_err(issue => Checkpoint(issue))
}

///|
/// Select the checked Program name from the same bound original.
pub fn client_local_effect_review_program_id(
  allowed : ClientEffectAllowedRun,
) -> String {
  allowed.compilation.owner.source.id
}
