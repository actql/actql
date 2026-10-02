///|
pub(all) enum ModelExecutionCeiling {
  AttemptsPerSlot
  TotalAttempts
  TotalCostUnits
  TotalDurationMs
  TotalWireBytes
  TotalTokenReservation
} derive(Eq, Debug)

///|
struct ModelExecutionContract {
  task : ModelTaskContract
  source : @decode.Cursor
  cid : String
  retry_classification_cid : String
  backoff_cid : String
  ceilings : Array[Int64]
  media : Array[(String, String)]
  bytes : Int
  nodes : Int
  work : Int
}

///|
/// Admits the existing 0.1 execution body and its exact task reference. Retry,
/// backoff and media references remain explicit dependencies, not admitted
/// policy or Connector authority. No absent ceiling is filled with a default.
pub fn read_model_execution_contract(
  task : ModelTaskContract,
  bytes : Bytes,
  expected_cid : String,
  limits : Limits,
  max_work : Int,
) -> Result[ModelExecutionContract, ModelTaskIssue] {
  if limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    max_work < 0 {
    return Err({ kind: InvalidLimits, source: None, })
  }
  if bytes.length() > limits.max_bytes {
    return Err({ kind: BodyLimit, source: None, })
  }
  // Byte work bounds parsing and both canonical hash passes, independently of
  // later semantic inspection. Reserve each pass before entering it.
  if bytes.length() > max_work {
    return Err({ kind: WorkLimit, source: None, })
  }
  let tree = match
    @source.parse_json_bytes(bytes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(v) => v
    Err(e) =>
      return Err({
        kind: match e.issue {
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
    Ok(v) => v
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
        "version", "model_task_contract_cid", "retry_classification_contract_cid",
        "max_attempts_per_slot", "max_total_attempts", "max_total_cost_units", "max_total_duration_ms",
        "max_total_wire_bytes", "max_total_token_reservation", "backoff_contract_cid",
        "media_input_contracts", "default_publication", "self_cid",
      ],
      b,
    )
    if model_task_string(o, "version", root, b) !=
      "actql-model-execution-contract/0.1" ||
      model_task_string(o, "default_publication", root, b) != "outcomes" {
      model_task_fail(InvalidBody, root)
    }
    let cid = model_task_cid(o, "self_cid", root, b)
    if cid != expected_cid {
      model_task_fail(IdentityMismatch, root)
    }
    model_task_charge(b, bytes.length(), root)
    let hashed = try {
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
    if hashed != cid {
      model_task_fail(IdentityMismatch, root)
    }
    if model_task_cid(o, "model_task_contract_cid", root, b) != task.cid {
      model_task_fail(ReferenceMismatch, root)
    }
    let retry_classification_cid = model_task_cid(
      o, "retry_classification_contract_cid", root, b,
    )
    let backoff_cid = model_task_cid(o, "backoff_contract_cid", root, b)
    let ceilings = []
    for
      name in [
        "max_attempts_per_slot", "max_total_attempts", "max_total_cost_units", "max_total_duration_ms",
        "max_total_wire_bytes", "max_total_token_reservation",
      ] {
      let c = model_task_required(o, name, root)
      let n = model_task_integer(c, name != "max_total_cost_units", b)
      if n < 0L {
        model_task_fail(InvalidBody, c)
      }
      ceilings.push(n)
    }
    let media_source = model_task_required(o, "media_input_contracts", root)
    let count = match @decode.object_length(media_source) {
      Some(n) => n
      None => model_task_fail(InvalidBody, media_source)
    }
    model_task_charge(b, count, media_source)
    let media = []
    for i in 0..<count {
      let (name, value) = @decode.field_at(media_source, i).unwrap()
      model_task_charge(b, name.length(), value)
      let pin = model_task_text(value, b)
      if pin.length() != 71 || !pin.has_prefix("sha256:") {
        model_task_fail(InvalidBody, value)
      }
      for j in 7..<71 {
        let c = pin[j].to_int()
        if !((c >= 48 && c <= 57) || (c >= 97 && c <= 102)) {
          model_task_fail(InvalidBody, value)
        }
      }
      media.push((name, pin))
    }
    Ok({
      task,
      source: root,
      cid,
      retry_classification_cid,
      backoff_cid,
      ceilings,
      media,
      bytes: size,
      nodes,
      work: b.work,
    })
  } catch {
    ModelTaskStop(e) => Err(e)
  }
}

///|
pub fn model_execution_task(v : ModelExecutionContract) -> ModelTaskContract {
  v.task
}

///|
pub fn model_execution_source(v : ModelExecutionContract) -> @decode.Cursor {
  v.source
}

///|
pub fn model_execution_cid(v : ModelExecutionContract) -> String {
  v.cid
}

///|
pub fn model_execution_usage(v : ModelExecutionContract) -> (Int, Int, Int) {
  (v.bytes, v.nodes, v.work)
}

///|
pub fn model_execution_retry_cid(v : ModelExecutionContract) -> String {
  v.retry_classification_cid
}

///|
pub fn model_execution_backoff_cid(v : ModelExecutionContract) -> String {
  v.backoff_cid
}

///|
pub fn model_execution_ceiling(
  v : ModelExecutionContract,
  ceiling : ModelExecutionCeiling,
) -> Int64 {
  v.ceilings[match ceiling {
    AttemptsPerSlot => 0
    TotalAttempts => 1
    TotalCostUnits => 2
    TotalDurationMs => 3
    TotalWireBytes => 4
    TotalTokenReservation => 5
  }]
}

///|
pub fn model_execution_media_count(v : ModelExecutionContract) -> Int {
  v.media.length()
}

///|
pub fn model_execution_media_at(
  v : ModelExecutionContract,
  index : Int,
) -> (String, String)? {
  v.media.get(index)
}
