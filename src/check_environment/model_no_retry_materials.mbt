///|
/// Existing no-retry/no-backoff policy bodies are shared DATA. They select no
/// physical implementation, Mock mode, capacity, Account or retry permission.
fn model_no_retry_wire() -> String {
  (
    #|{"retryable_failures":[],"self_cid":"sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90","version":"actql-model-retry-policy/0.1"}
  )
}

///|
fn model_no_backoff_wire() -> String {
  (
    #|{"delays_ms":[],"self_cid":"sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56","version":"actql-model-backoff/0.1"}
  )
}

///|
fn emit_no_retry_model_execution(
  writer : @encode.Writer,
  normalized : NormalizedPublicModelTask,
  bounds : Array[(String, Int64)],
  self_cid : String?,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "backoff_contract_cid")
  @encode.string_value(
    writer, "sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56",
  )
  @encode.key(writer, "default_publication")
  @encode.string_value(writer, "outcomes")
  for (name, value) in bounds {
    @encode.key(writer, name)
    @encode.number_value(writer, value.to_double())
  }
  @encode.key(writer, "media_input_contracts")
  @encode.begin_object(writer)
  @encode.end_object(writer)
  @encode.key(writer, "model_task_contract_cid")
  @encode.string_value(writer, normalized.task_cid)
  @encode.key(writer, "retry_classification_contract_cid")
  @encode.string_value(
    writer, "sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90",
  )
  if self_cid is Some(cid) {
    @encode.key(writer, "self_cid")
    @encode.string_value(writer, cid)
  }
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-model-execution-contract/0.1")
  @encode.end_object(writer)
}

///|
/// Canonical execution originals for an actual non-Mock normalized Task and
/// explicit finite Host ceilings. The existing execution/dependency readers
/// must still admit these bodies at the same checked Request/Run boundary.
/// Cost is an accounting ceiling, never an assertion that unknown fees are
/// free; a physical provider recipe must supply its truthful pricing policy.
pub fn normalized_public_model_task_no_retry_materials(
  normalized : NormalizedPublicModelTask,
  max_attempts : Int64,
  max_cost_units : Int64,
  max_duration_ms : Int64,
  max_wire_bytes : Int64,
  max_tokens : Int64,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_work : Int,
) -> Result[(String, String, String, String, String, String), ModelTaskIssue] {
  let source = Some(normalized.declaration.original)
  if normalized.mock_profile is Some(_) {
    return Err({ kind: ReferenceMismatch, source, })
  }
  if max_attempts <= 0L ||
    max_cost_units < 0L ||
    max_duration_ms <= 0L ||
    max_wire_bytes <= 0L ||
    max_tokens <= 0L ||
    max_bytes < 0 ||
    max_nodes < 0 ||
    max_depth < 0 ||
    max_work < 0 {
    return Err({ kind: InvalidLimits, source, })
  }
  // Match the existing execution reader's safe_integer domain before binary64
  // emission. A normal recipe cannot round a larger accounting ceiling.
  for
    ceiling in [
      max_attempts, max_cost_units, max_duration_ms, max_wire_bytes, max_tokens,
    ] {
    if ceiling > 9007199254740991L {
      return Err({ kind: InvalidLimits, source, })
    }
  }
  if 2L * (max_bytes.to_int64() + max_nodes.to_int64()) > max_work.to_int64() {
    return Err({ kind: WorkLimit, source, })
  }
  let bounds = [
    ("max_attempts_per_slot", 1L),
    ("max_total_attempts", max_attempts),
    ("max_total_cost_units", max_cost_units),
    ("max_total_duration_ms", max_duration_ms),
    ("max_total_token_reservation", max_tokens),
    ("max_total_wire_bytes", max_wire_bytes),
  ]
  try {
    let hash = @encode.hashing_writer(max_bytes, max_nodes, max_depth)
    emit_no_retry_model_execution(hash, normalized, bounds, None)
    let cid = "sha256:" + @encode.finish_hash(hash)
    let writer = @encode.writer(max_bytes, max_nodes, max_depth)
    emit_no_retry_model_execution(writer, normalized, bounds, Some(cid))
    Ok(
      (
        @encode.finish(writer),
        cid,
        model_no_retry_wire(),
        "sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90",
        model_no_backoff_wire(),
        "sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56",
      ),
    )
  } catch {
    _ => Err({ kind: BodyLimit, source, })
  }
}
