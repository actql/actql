///|
/// Physical envelopes, not a reservation or a simultaneous-retention proof.
pub(all) struct ModelResponseProfileLimits {
  request_bytes : Int
  response_bytes : Int
  chunk_bytes : Int
  chunks : Int
  header_bytes : Int
  metadata_bytes : Int
  metadata_nodes : Int
  metadata_depth : Int
  parse_nodes : Int
  parse_depth : Int
  parse_work : Int
  adapter_holding_bytes : Int
  adapter_workspace_bytes : Int
  active_slots : Int
  unsettled_slots : Int
} derive(Eq, Debug)

///|
/// An exact SDK dependency-closure original, not an SDK model object.
pub(all) struct ModelResponseProfileSDK {
  package_name : String
  version : String
  interface : String
  lock_artifact_cid : String
} derive(Eq, Debug)

///|
/// Facts supplied by the existing trusted installation boundary. Constructing
/// this record or matching it grants neither installation nor send authority.
pub(all) struct ModelResponseProfileInstallation {
  builder_id : String
  builder_revision : String
  codec_id : String
  codec_revision : String
  build_artifact_cid : String
  sdk : ModelResponseProfileSDK?
  endpoint : String
  http_method : String
  streaming : Bool
  validator_id : String
  validator_revision : String
  validator_artifact_cid : String
  completion_basis : String
}

///|
/// Canonical support declaration. No observed completion, permission, captured
/// response or funded public capability can be obtained from this value.
struct ModelResponseProfile {
  cid : String
  installation : ModelResponseProfileInstallation
  task_cid : String
  kind : ModelTaskKind
  input_schema_cid : String
  output_schema_cid : String
  probability_source : String?
  probability_profile_cid : String?
  observations : Array[String]
  limits : ModelResponseProfileLimits
  bytes : Int
  nodes : Int
  work : Int
}

///|
fn response_profile_object(
  parent : @decode.ObjectView,
  name : String,
  root : @decode.Cursor,
  names : Array[String],
  b : ModelTaskBudget,
) -> (@decode.Cursor, @decode.ObjectView) raise ModelTaskStop {
  let source = model_task_required(parent, name, root)
  (source, model_task_object(source, names, b))
}

///|
fn response_profile_constant(
  object : @decode.ObjectView,
  name : String,
  root : @decode.Cursor,
  expected : String,
  b : ModelTaskBudget,
) -> Unit raise ModelTaskStop {
  if model_task_string(object, name, root, b) != expected {
    model_task_fail(InvalidBody, root)
  }
}

///|
fn response_profile_bool(
  object : @decode.ObjectView,
  name : String,
  root : @decode.Cursor,
  expected : Bool,
  b : ModelTaskBudget,
) -> Unit raise ModelTaskStop {
  let source = model_task_required(object, name, root)
  model_task_charge(b, 1, source)
  if @decode.boolean(source) != Ok(expected) {
    model_task_fail(InvalidBody, source)
  }
}

///|
fn response_profile_limit(
  object : @decode.ObjectView,
  name : String,
  root : @decode.Cursor,
  b : ModelTaskBudget,
) -> Int raise ModelTaskStop {
  let source = model_task_required(object, name, root)
  let n = model_task_integer(source, true, b)
  if n > 2147483647L {
    model_task_fail(InvalidBody, source)
  }
  n.to_int()
}

///|
fn response_profile_nullable(
  object : @decode.ObjectView,
  name : String,
  root : @decode.Cursor,
) -> @decode.Cursor raise ModelTaskStop {
  match @decode.lookup(object, name) {
    Some(value) => value
    None => model_task_fail(InvalidBody, root)
  }
}

///|
/// Bounded canonical admission, independent of runtime truth. Every nullable
/// declaration is explicitly present; response observations remain separately
/// nullable at runtime, even when the codec supports reporting them.
pub fn read_model_response_profile(
  bytes : Bytes,
  expected_cid : String,
  limits : Limits,
  max_work : Int,
) -> Result[ModelResponseProfile, ModelTaskIssue] {
  if limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    max_work < 0 {
    return Err({ kind: InvalidLimits, source: None, })
  }
  if bytes.length() > limits.max_bytes {
    return Err({ kind: BodyLimit, source: None, })
  }
  if bytes.length() > max_work {
    return Err({ kind: WorkLimit, source: None, })
  }
  let tree = match
    @source.parse_json_bytes(bytes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err({
        kind: match issue.issue {
          InputLimit | NodeLimit | DepthLimit => BodyLimit
          _ => InvalidBody
        },
        source: None,
      })
  }
  let root = match
    @decode.admit(tree, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err({ kind: BodyLimit, source: None, })
  }
  let b : ModelTaskBudget = {
    limits: {
      bodies: limits,
      contracts: { max_nodes: 0, max_depth: 0, max_text_bytes: 0, },
      max_work,
    },
    work: bytes.length(),
    contract_nodes: 0,
    contract_text: 0,
  }
  try {
    model_task_charge(b, bytes.length(), root)
    let (full, size, nodes) = hash(root, limits, false) catch {
      _ => model_task_fail(InvalidBody, root)
    }
    if full != "sha256:" + @sha.hex(bytes) {
      model_task_fail(InvalidBody, root)
    }
    let o = model_task_object(
      root,
      [
        "version", "adapter", "operation", "task", "completion", "probability", "observations",
        "limits", "controls", "self_cid",
      ],
      b,
    )
    response_profile_constant(
      o, "version", root, "actql-model-response-profile/0.1", b,
    )
    let cid = model_task_cid(o, "self_cid", root, b)
    if cid != expected_cid {
      model_task_fail(IdentityMismatch, root)
    }
    model_task_charge(b, bytes.length(), root)
    let computed = try {
      let writer = @encode.hashing_writer(
        limits.max_bytes,
        limits.max_nodes,
        limits.max_depth,
      )
      emit_except(root, writer, Some("self_cid"))
      let (hex, _, _) = @encode.finish_hash_usage(writer)
      "sha256:" + hex
    } catch {
      _ => model_task_fail(BodyLimit, root)
    }
    if cid != computed {
      model_task_fail(IdentityMismatch, root)
    }
    let (a, adapter) = response_profile_object(
      o,
      "adapter",
      root,
      [
        "builder_id", "builder_revision", "codec_id", "codec_revision", "build_artifact_cid",
        "port_abi", "sdk",
      ],
      b,
    )
    response_profile_constant(
      adapter, "port_abi", a, "model-physical-port/1", b,
    )
    let sdk_source = response_profile_nullable(adapter, "sdk", a)
    let sdk = if @decode.is_null(sdk_source) {
      None
    } else {
      let s = model_task_object(
        sdk_source,
        ["package", "version", "interface", "lock_artifact_cid"],
        b,
      )
      response_profile_constant(s, "interface", sdk_source, "v4", b)
      Some({
        package_name: model_task_string(s, "package", sdk_source, b),
        version: model_task_string(s, "version", sdk_source, b),
        interface: "v4",
        lock_artifact_cid: model_task_cid(s, "lock_artifact_cid", sdk_source, b),
      })
    }
    let (p, operation) = response_profile_object(
      o,
      "operation",
      root,
      ["endpoint", "method", "streaming"],
      b,
    )
    response_profile_constant(operation, "method", p, "POST", b)
    response_profile_bool(operation, "streaming", p, false, b)
    let (c, completion) = response_profile_object(
      o,
      "completion",
      root,
      [
        "validator_id", "validator_revision", "validator_artifact_cid", "basis",
        "transport_eof", "endpoint_envelope", "output_contract",
      ],
      b,
    )
    let basis = model_task_string(completion, "basis", c, b)
    if basis != "generation_finish" && basis != "native_decision" {
      model_task_fail(InvalidBody, c)
    }
    for name in ["transport_eof", "endpoint_envelope", "output_contract"] {
      response_profile_bool(completion, name, c, true, b)
    }
    let installation : ModelResponseProfileInstallation = {
      builder_id: model_task_string(adapter, "builder_id", a, b),
      builder_revision: model_task_string(adapter, "builder_revision", a, b),
      codec_id: model_task_string(adapter, "codec_id", a, b),
      codec_revision: model_task_string(adapter, "codec_revision", a, b),
      build_artifact_cid: model_task_cid(adapter, "build_artifact_cid", a, b),
      sdk,
      endpoint: model_task_string(operation, "endpoint", p, b),
      http_method: "POST",
      streaming: false,
      validator_id: model_task_string(completion, "validator_id", c, b),
      validator_revision: model_task_string(
        completion, "validator_revision", c, b,
      ),
      validator_artifact_cid: model_task_cid(
        completion, "validator_artifact_cid", c, b,
      ),
      completion_basis: basis,
    }
    let (t, task) = response_profile_object(
      o,
      "task",
      root,
      ["contract_cid", "kind", "input_schema_cid", "output_schema_cid"],
      b,
    )
    let kind = match model_task_string(task, "kind", t, b) {
      "structured_generate" => StructuredGenerate
      "decision" => Decision
      _ => model_task_fail(InvalidBody, t)
    }
    let probability = response_profile_nullable(o, "probability", root)
    let (probability_source, probability_profile_cid) = if @decode.is_null(
        probability,
      ) {
      if kind == Decision {
        model_task_fail(InvalidBody, probability)
      }
      (None, None)
    } else {
      if kind != Decision {
        model_task_fail(InvalidBody, probability)
      }
      let prob = model_task_object(
        probability,
        ["source", "validation_profile_cid"],
        b,
      )
      let source = model_task_string(prob, "source", probability, b)
      if source != "native" && source != "estimated" {
        model_task_fail(InvalidBody, probability)
      }
      (
        Some(source),
        Some(model_task_cid(prob, "validation_profile_cid", probability, b)),
      )
    }
    if basis == "native_decision" &&
      (kind != Decision || probability_source != Some("native")) {
      model_task_fail(InvalidBody, c)
    }
    let obs = model_task_required(o, "observations", root)
    let count = match @decode.array_length(obs) {
      Some(count) if count <= 8 => count
      _ => model_task_fail(InvalidBody, obs)
    }
    model_task_charge(b, count, obs)
    let order = [
      "provider_request_id", "provider_reported_model_id", "finish_reason", "input_tokens",
      "output_tokens", "cached_input_tokens", "reasoning_tokens", "provider_metadata",
    ]
    let observations = []
    let mut previous = -1
    for i in 0..<count {
      let item = @decode.element_at(obs, i).unwrap()
      let name = model_task_text(item, b)
      model_task_charge(b, order.length(), item)
      let mut rank = -1
      for j in 0..<order.length() {
        if order[j] == name {
          rank = j
        }
      }
      if rank <= previous {
        model_task_fail(InvalidBody, item)
      }
      previous = rank
      observations.push(name)
    }
    let (l, envelope) = response_profile_object(
      o,
      "limits",
      root,
      [
        "request_bytes", "response_bytes", "chunk_bytes", "chunks", "header_bytes",
        "metadata_bytes", "metadata_nodes", "metadata_depth", "parse_nodes", "parse_depth",
        "parse_work", "adapter_holding_bytes", "adapter_workspace_bytes", "active_slots",
        "unsettled_slots",
      ],
      b,
    )
    let bounded : ModelResponseProfileLimits = {
      request_bytes: response_profile_limit(envelope, "request_bytes", l, b),
      response_bytes: response_profile_limit(envelope, "response_bytes", l, b),
      chunk_bytes: response_profile_limit(envelope, "chunk_bytes", l, b),
      chunks: response_profile_limit(envelope, "chunks", l, b),
      header_bytes: response_profile_limit(envelope, "header_bytes", l, b),
      metadata_bytes: response_profile_limit(envelope, "metadata_bytes", l, b),
      metadata_nodes: response_profile_limit(envelope, "metadata_nodes", l, b),
      metadata_depth: response_profile_limit(envelope, "metadata_depth", l, b),
      parse_nodes: response_profile_limit(envelope, "parse_nodes", l, b),
      parse_depth: response_profile_limit(envelope, "parse_depth", l, b),
      parse_work: response_profile_limit(envelope, "parse_work", l, b),
      adapter_holding_bytes: response_profile_limit(
        envelope, "adapter_holding_bytes", l, b,
      ),
      adapter_workspace_bytes: response_profile_limit(
        envelope, "adapter_workspace_bytes", l, b,
      ),
      active_slots: response_profile_limit(envelope, "active_slots", l, b),
      unsettled_slots: response_profile_limit(envelope, "unsettled_slots", l, b),
    }
    // This minimum does not establish the complete simultaneous sum. SDK parse
    // holdings, Promise/reader/record objects and original Core custody remain
    // subject to the installed derivation and existing quantity reservation.
    let minimum = bounded.response_bytes.to_int64() +
      bounded.chunk_bytes.to_int64() +
      bounded.header_bytes.to_int64()
    if bounded.adapter_holding_bytes.to_int64() < minimum ||
      bounded.active_slots > 4 ||
      bounded.unsettled_slots > 4 {
      model_task_fail(InvalidBody, l)
    }
    let (ctrl, controls) = response_profile_object(
      o,
      "controls",
      root,
      [
        "model_requests", "retry", "fallback", "hedging", "tools", "repair", "cache",
        "media_fetch", "workflow_restore", "sdk_telemetry", "redirect",
      ],
      b,
    )
    if response_profile_limit(controls, "model_requests", ctrl, b) != 1 {
      model_task_fail(InvalidBody, ctrl)
    }
    for
      name in [
        "retry", "fallback", "hedging", "tools", "repair", "cache", "media_fetch",
        "workflow_restore", "sdk_telemetry", "redirect",
      ] {
      response_profile_bool(controls, name, ctrl, false, b)
    }
    Ok({
      cid,
      installation,
      task_cid: model_task_cid(task, "contract_cid", t, b),
      kind,
      input_schema_cid: model_task_cid(task, "input_schema_cid", t, b),
      output_schema_cid: model_task_cid(task, "output_schema_cid", t, b),
      probability_source,
      probability_profile_cid,
      observations,
      limits: bounded,
      bytes: size,
      nodes,
      work: b.work,
    })
  } catch {
    ModelTaskStop(issue) => Err(issue)
  }
}

///|
/// Cross-reference validation only. The existing installation Owner must first
/// verify original build/lock/configuration bodies and operational conformance.
/// No callback, dispatch, completion issuance or resource claim occurs here.
pub fn check_model_response_profile_binding(
  profile : ModelResponseProfile,
  task : ModelTaskContract,
  installation : ModelResponseProfileInstallation,
  probability : DecisionProbabilityProfile?,
) -> Result[Unit, ModelTaskIssueKind] {
  if profile.task_cid != task.cid || profile.kind != task.kind {
    return Err(ReferenceMismatch)
  }
  if profile.input_schema_cid != task.input_schema_cid {
    return Err(InputSchemaMismatch)
  }
  if profile.output_schema_cid != task.output_schema_cid {
    return Err(OutputSchemaMismatch)
  }
  let actual = profile.installation
  if actual.builder_id != installation.builder_id ||
    actual.builder_revision != installation.builder_revision ||
    actual.codec_id != installation.codec_id ||
    actual.codec_revision != installation.codec_revision ||
    actual.build_artifact_cid != installation.build_artifact_cid ||
    actual.sdk != installation.sdk ||
    actual.endpoint != installation.endpoint ||
    actual.http_method != installation.http_method ||
    actual.streaming != installation.streaming ||
    actual.validator_id != installation.validator_id ||
    actual.validator_revision != installation.validator_revision ||
    actual.validator_artifact_cid != installation.validator_artifact_cid ||
    actual.completion_basis != installation.completion_basis {
    return Err(ReferenceMismatch)
  }
  match task.kind {
    StructuredGenerate =>
      if probability is Some(_) {
        return Err(ReferenceMismatch)
      }
    Decision => {
      guard probability is Some(probability) else {
        return Err(ReferenceMismatch)
      }
      // The currently admitted Task requires native probability. A profile may
      // describe estimated support but cannot broaden that Task's contract.
      if profile.probability_source != Some("native") ||
        profile.probability_profile_cid !=
        Some(decision_probability_profile_cid(probability)) {
        return Err(ReferenceMismatch)
      }
    }
  }
  Ok(())
}

///|
pub fn model_response_profile_identity(value : ModelResponseProfile) -> String {
  value.cid
}

///|
pub fn model_response_profile_limits(
  value : ModelResponseProfile,
) -> ModelResponseProfileLimits {
  value.limits
}

///|
// Match positive acquisition ceilings within this already admitted profile.
// Tighter controls remain valid; matching is not capacity, permission or
// completion. Do not expose a mutable copy of the original limit record.
pub fn model_response_profile_transport_matches(
  value : ModelResponseProfile,
  request_bytes : Int,
  response_bytes : Int,
  chunk_bytes : Int,
  chunks : Int,
  header_bytes : Int,
) -> Bool {
  let original = value.limits
  request_bytes > 0 &&
  request_bytes <= original.request_bytes &&
  response_bytes > 0 &&
  response_bytes <= original.response_bytes &&
  chunk_bytes > 0 &&
  chunk_bytes <= original.chunk_bytes &&
  chunks > 0 &&
  chunks <= original.chunks &&
  header_bytes > 0 &&
  header_bytes <= original.header_bytes
}

///|
pub fn model_response_profile_completion_basis(
  value : ModelResponseProfile,
) -> String {
  value.installation.completion_basis
}

///|
// DATA cross-references of an already selected profile, not an installation or
// completion grant. Runtime callers still require the original entered call.
pub fn check_model_response_profile_probability(
  profile : ModelResponseProfile,
  task : ModelTaskContract,
  probability : DecisionProbabilityProfile,
) -> Result[Unit, ModelTaskIssueKind] {
  check_model_response_profile_binding(
    profile,
    task,
    profile.installation,
    Some(probability),
  )
}

///|
pub fn model_response_profile_usage(
  value : ModelResponseProfile,
) -> (Int, Int, Int) {
  (value.bytes, value.nodes, value.work)
}

///|
pub fn model_response_profile_observation_count(
  value : ModelResponseProfile,
) -> Int {
  value.observations.length()
}

///|
pub fn model_response_profile_observation_at(
  value : ModelResponseProfile,
  index : Int,
) -> String? {
  if index < 0 || index >= value.observations.length() {
    None
  } else {
    Some(value.observations[index])
  }
}
