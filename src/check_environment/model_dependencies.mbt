///|
pub(all) enum ModelDependencyKind {
  ModelPrompt
  ModelRetryPolicy
  ModelBackoff
} derive(Eq, Debug)

///|
/// Integrity and structural admission, not provider compatibility or authority.
pub struct ModelDependency {
  kind : ModelDependencyKind
  source : @decode.Cursor
  cid : String
  payload : @decode.Cursor?
  count : Int
  bytes : Int
  nodes : Int
  work : Int
}

///|
pub(all) enum ModelDependencyIssue {
  Missing(ModelDependencyKind)
  Body(ModelDependencyKind, ModelTaskIssue)
  UnsupportedPolicy(ModelDependencyKind)
}

///|
/// Bound to the exact checked execution contract. No permission or provider
/// support is inferred from these bodies, including a canonical prompt value.
pub struct SingleAttemptModelDependencies {
  execution : ModelExecutionContract
  prompt : ModelDependency
  retry : ModelDependency
  backoff : ModelDependency
}

///|
pub fn read_model_dependency(
  kind : ModelDependencyKind,
  bytes : Bytes,
  expected_cid : String,
  limits : Limits,
  max_work : Int,
) -> Result[ModelDependency, ModelTaskIssue] {
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
  let budget : ModelTaskBudget = {
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
    model_task_charge(budget, bytes.length(), root)
    let (full, size, nodes) = hash(root, limits, false) catch {
      _ => model_task_fail(InvalidBody, root)
    }
    if full != "sha256:" + @sha.hex(bytes) {
      model_task_fail(InvalidBody, root)
    }
    let (version, field) = match kind {
      ModelPrompt => ("actql-model-prompt/0.1", "payload")
      ModelRetryPolicy => ("actql-model-retry-policy/0.1", "retryable_failures")
      ModelBackoff => ("actql-model-backoff/0.1", "delays_ms")
    }
    let object = model_task_object(root, ["version", field, "self_cid"], budget)
    if model_task_string(object, "version", root, budget) != version {
      model_task_fail(InvalidBody, root)
    }
    let cid = model_task_cid(object, "self_cid", root, budget)
    if cid != expected_cid {
      model_task_fail(IdentityMismatch, root)
    }
    model_task_charge(budget, bytes.length(), root)
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
    // Prompt payload may itself be NULL. The shared required reader rejects
    // NULL for ordinary contract fields, so preserve explicit presence here.
    let value = match @decode.lookup(object, field) {
      Some(value) => value
      None => model_task_fail(InvalidBody, root)
    }
    let count = match kind {
      ModelPrompt => 0
      ModelRetryPolicy | ModelBackoff => {
        let count = match @decode.array_length(value) {
          Some(value) => value
          None => model_task_fail(InvalidBody, value)
        }
        model_task_charge(budget, count, value)
        let mut previous = -1
        for index in 0..<count {
          let item = @decode.element_at(value, index).unwrap()
          match kind {
            ModelRetryPolicy => {
              // Normative rank, not alphabetic order or HTTP status priority.
              let rank = match model_task_text(item, budget) {
                "rate_limit" => 0
                "timeout" => 1
                "provider_error" => 2
                _ => model_task_fail(InvalidBody, item)
              }
              if rank <= previous {
                model_task_fail(InvalidBody, item)
              }
              previous = rank
            }
            ModelBackoff =>
              if model_task_integer(item, false, budget) < 0L {
                model_task_fail(InvalidBody, item)
              }
            ModelPrompt => ()
          }
        }
        count
      }
    }
    Ok({
      kind,
      source: root,
      cid,
      payload: if kind == ModelPrompt {
        Some(value)
      } else {
        None
      },
      count,
      bytes: size,
      nodes,
      work: budget.work,
    })
  } catch {
    ModelTaskStop(issue) => Err(issue)
  }
}

///|
/// Resolve references from the checked owners, never caller-selected expected
/// hashes. The installed envelope applies cumulatively to all three bodies.
pub fn read_single_attempt_model_dependencies(
  execution : ModelExecutionContract,
  prompt : Bytes?,
  retry : Bytes?,
  backoff : Bytes?,
  limits : Limits,
  max_work : Int,
) -> Result[SingleAttemptModelDependencies, ModelDependencyIssue] {
  let task = model_execution_task(execution)
  let mut remaining_bytes = limits.max_bytes
  let mut remaining_nodes = limits.max_nodes
  let mut remaining_work = max_work
  let admitted = []
  for
    (kind, bytes, expected) in [
      (ModelPrompt, prompt, model_task_prompt_cid(task)),
      (ModelRetryPolicy, retry, model_execution_retry_cid(execution)),
      (ModelBackoff, backoff, model_execution_backoff_cid(execution)),
    ] {
    guard bytes is Some(bytes) else { return Err(Missing(kind)) }
    let value = match
      read_model_dependency(
        kind,
        bytes,
        expected,
        { ..limits, max_bytes: remaining_bytes, max_nodes: remaining_nodes, },
        remaining_work,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Body(kind, issue))
    }
    remaining_bytes -= value.bytes
    remaining_nodes -= value.nodes
    remaining_work -= value.work
    admitted.push(value)
  }
  // Validate every body before reporting a supported-profile limitation.
  for value in admitted {
    if value.kind != ModelPrompt && value.count != 0 {
      return Err(UnsupportedPolicy(value.kind))
    }
  }
  Ok({
    execution,
    prompt: admitted[0],
    retry: admitted[1],
    backoff: admitted[2],
  })
}

///|
pub fn single_attempt_model_dependencies_match(
  value : SingleAttemptModelDependencies,
  execution : ModelExecutionContract,
) -> Bool {
  physical_equal(value.execution, execution)
}

///|
pub fn single_attempt_model_prompt(
  value : SingleAttemptModelDependencies,
) -> ModelDependency {
  value.prompt
}

///|
pub fn model_dependency_identity(value : ModelDependency) -> String {
  value.cid
}

///|
pub fn model_dependency_source(value : ModelDependency) -> @decode.Cursor {
  value.source
}

///|
pub fn model_dependency_payload(value : ModelDependency) -> @decode.Cursor? {
  value.payload
}

///|
pub fn emit_model_prompt_payload(
  value : ModelDependency,
  writer : @encode.Writer,
) -> Bool raise @encode.EncodeFailure {
  match value.payload {
    Some(payload) => {
      emit_cursor(payload, writer, false)
      true
    }
    None => false
  }
}

///|
pub fn model_dependency_usage(value : ModelDependency) -> (Int, Int, Int) {
  (value.bytes, value.nodes, value.work)
}
