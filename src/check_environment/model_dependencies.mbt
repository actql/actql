///|
pub(all) enum ModelDependencyKind {
  ModelPrompt
  ModelRetryPolicy
  ModelBackoff
  ModelMediaInput(String)
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
  MediaRole(String, ModelMediaRoleIssue)
}

///|
pub(all) enum ModelMediaRoleIssue {
  UnknownRole
  UnsupportedShape
  MediaTypeMismatch
} derive(Eq, Debug)

///|
/// Bound to the exact checked execution contract. No permission or provider
/// support is inferred from these bodies, including a canonical prompt value.
pub struct SingleAttemptModelDependencies {
  execution : ModelExecutionContract
  prompt : ModelDependency
  retry : ModelDependency
  backoff : ModelDependency
  media : Array[ModelDependency]
  decision : DecisionContract?
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
      ModelMediaInput(_) => ("actql-model-media-input/0.1", "payload")
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
      ModelMediaInput(_) => {
        read_model_media_payload(value, budget)
        0
      }
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
            ModelPrompt | ModelMediaInput(_) => ()
          }
        }
        count
      }
    }
    Ok({
      kind,
      source: root,
      cid,
      payload: match kind {
        ModelPrompt | ModelMediaInput(_) => Some(value)
        ModelRetryPolicy | ModelBackoff => None
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
/// hashes. The installed envelope applies cumulatively to scalar and media
/// dependencies; a reference alone cannot stand in for an admitted body.
pub fn read_single_attempt_model_dependencies(
  execution : ModelExecutionContract,
  prompt : Bytes?,
  retry : Bytes?,
  backoff : Bytes?,
  limits : Limits,
  max_work : Int,
  media? : Array[(String, Bytes)] = [],
) -> Result[SingleAttemptModelDependencies, ModelDependencyIssue] {
  read_model_dependencies_selected(
    execution,
    prompt,
    retry,
    backoff,
    limits,
    max_work,
    media,
    None,
  )
}

///|
fn read_model_dependencies_selected(
  execution : ModelExecutionContract,
  prompt : Bytes?,
  retry : Bytes?,
  backoff : Bytes?,
  limits : Limits,
  max_work : Int,
  media : Array[(String, Bytes)],
  original_mock : (ModelMockProfile, NormalizedPublicModelTask)?,
) -> Result[SingleAttemptModelDependencies, ModelDependencyIssue] {
  if original_mock is Some((profile, normalized)) &&
    !model_mock_execution_matches(profile, normalized, execution) {
    return Err(Body(ModelPrompt, { kind: ReferenceMismatch, source: None, }))
  }
  let task = model_execution_task(execution)
  let mut remaining_bytes = limits.max_bytes
  let mut remaining_nodes = limits.max_nodes
  let mut remaining_work = max_work
  if media.length() > limits.max_members ||
    model_execution_media_count(execution) > limits.max_members {
    return Err(Body(ModelPrompt, { kind: BodyLimit, source: None, }))
  }
  let supplied : Map[String, Bytes] = Map([])
  for (role, bytes) in media {
    let kind = ModelMediaInput(role)
    if role.length() >= remaining_work {
      return Err(Body(kind, { kind: WorkLimit, source: None, }))
    }
    remaining_work -= role.length() + 1
    if supplied.contains(role) {
      return Err(Body(kind, { kind: InvalidBody, source: None, }))
    }
    supplied[role] = bytes
  }
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
  let media_dependencies = []
  for index in 0..<model_execution_media_count(execution) {
    let (role, expected) = model_execution_media_at(execution, index).unwrap()
    let kind = ModelMediaInput(role)
    guard supplied.get(role) is Some(bytes) else { return Err(Missing(kind)) }
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
    media_dependencies.push(value)
  }
  if media.length() != media_dependencies.length() {
    return Err(Body(ModelPrompt, { kind: InvalidBody, source: None, }))
  }
  if original_mock is None {
    match
      validate_model_media_roles(
        model_task_input(task),
        media_dependencies,
        limits,
        remaining_work,
      ) {
      Err(issue) => return Err(issue)
      Ok(remaining) => remaining_work = remaining
    }
  }
  // Validate every body before reporting a supported-profile limitation.
  for value in admitted {
    if value.kind != ModelPrompt && value.count != 0 {
      return Err(UnsupportedPolicy(value.kind))
    }
  }
  let decision = if task.kind == Decision {
    match
      read_decision_contract(task, admitted[0], {
        max_questions: limits.max_nodes,
        max_options: limits.max_nodes,
        max_levels: limits.max_nodes,
        max_name_bytes: limits.max_bytes,
        max_work: remaining_work,
      }) {
      Ok(value) => Some(value)
      Err(issue) =>
        return Err(
          Body(ModelPrompt, {
            kind: if issue.kind == DecisionIssueKind::WorkLimit {
              WorkLimit
            } else {
              InvalidDecision(issue.kind)
            },
            source: issue.source,
          }),
        )
    }
  } else {
    None
  }
  Ok({
    execution,
    prompt: admitted[0],
    retry: admitted[1],
    backoff: admitted[2],
    media: media_dependencies,
    decision,
  })
}

///|
// Match installed media to declarations, never sampled inputs. Nullable or
// empty input does not waive a Content role's dependency. Traversal is bounded
// by the same installed admission envelope; it does not inspect byte contents.
fn validate_model_media_roles(
  input : @value_contract.Contract,
  dependencies : Array[ModelDependency],
  limits : Limits,
  max_work : Int,
) -> Result[Int, ModelDependencyIssue] {
  guard input.shape is @value_contract.Object(fields) else {
    return Err(
      Body(ModelPrompt, { kind: InvalidObjectContract, source: None, }),
    )
  }
  let mut remaining = max_work
  let roles : Map[String, ModelDependency] = Map([])
  for dependency in dependencies {
    guard dependency.kind is ModelMediaInput(role) else {
      return Err(Body(dependency.kind, { kind: InvalidBody, source: None, }))
    }
    if role.length() >= remaining {
      return Err(Body(dependency.kind, { kind: WorkLimit, source: None, }))
    }
    remaining -= role.length() + 1
    roles[role] = dependency
  }
  let mut nodes = limits.max_nodes
  for index in 0..<@value_contract.field_count(fields) {
    let field = @value_contract.field_at(fields, index).unwrap()
    let kind = ModelMediaInput(field.name)
    if field.name.length() >= remaining {
      return Err(Body(kind, { kind: WorkLimit, source: None, }))
    }
    remaining -= field.name.length() + 1
    // Only direct Content or bounded homogeneous Content arrays are media
    // roles. Nested Content is not silently treated as an ordinary scalar.
    let media_type : String?? = match field.contract.shape {
      @value_contract.ContentRef(media_type~) => Some(media_type)
      @value_contract.Array(item, max_items=Some(_)) =>
        match item.shape {
          @value_contract.ContentRef(media_type~) => Some(media_type)
          _ => None
        }
      _ => None
    }
    let stack = [field.contract]
    let mut contains_content = false
    while !stack.is_empty() {
      if remaining <= 0 || nodes <= 0 {
        return Err(
          Body(kind, {
            kind: if remaining <= 0 {
              WorkLimit
            } else {
              BodyLimit
            },
            source: None,
          }),
        )
      }
      remaining -= 1
      nodes -= 1
      let current = stack.pop().unwrap()
      match current.shape {
        @value_contract.ContentRef(_) => contains_content = true
        @value_contract.Array(item, ..) => stack.push(item)
        @value_contract.Object(nested) => {
          let count = @value_contract.field_count(nested)
          let names = @value_contract.field_name_bytes(nested)
          if names > remaining || count > nodes - stack.length() {
            return Err(
              Body(kind, {
                kind: if names > remaining {
                  WorkLimit
                } else {
                  BodyLimit
                },
                source: None,
              }),
            )
          }
          remaining -= names
          for index in 0..<count {
            stack.push(
              @value_contract.field_at(nested, index).unwrap().contract,
            )
          }
        }
        _ => ()
      }
    }
    if contains_content && media_type is None {
      return Err(MediaRole(field.name, UnsupportedShape))
    }
    match media_type {
      Some(expected) => {
        guard roles.get(field.name) is Some(dependency) else {
          return Err(Missing(kind))
        }
        let payload = dependency.payload.unwrap()
        let actual = @decode.text(
          @decode.lookup(@decode.open_object(payload).unwrap(), "media_type").unwrap(),
        ).unwrap()
        let comparison_work = actual.length() +
          expected.map(value => value.length()).unwrap_or(0)
        if comparison_work > remaining {
          return Err(Body(kind, { kind: WorkLimit, source: None, }))
        }
        remaining -= comparison_work
        if expected is Some(expected) && actual != expected {
          return Err(MediaRole(field.name, MediaTypeMismatch))
        }
        roles.remove(field.name)
      }
      None =>
        if roles.contains(field.name) {
          return Err(MediaRole(field.name, UnsupportedShape))
        }
    }
  }
  for (role, _) in roles {
    return Err(MediaRole(role, UnknownRole))
  }
  Ok(remaining)
}

///|
// The media body is an explicit transport envelope, not Ref issuance, byte
// validation or current egress authorization. Those facts belong to the
// physical preflight and its attachment evidence. No absent ceiling/default
// expands this installed profile; page/frame bounds are explicitly nullable.
fn read_model_media_payload(
  source : @decode.Cursor,
  budget : ModelTaskBudget,
) -> Unit raise ModelTaskStop {
  let object = model_task_object(
    source,
    [
      "media_type", "max_bytes", "max_pages", "max_frames", "complete", "transfer_method",
      "classifications", "regions", "egress_scope_cid",
    ],
    budget,
  )
  let media = model_task_string(object, "media_type", source, budget)
  // Reuse ContentRef's nonempty checked media descriptor. Do not introduce a
  // second MIME spelling grammar in the Model dependency owner.
  if media.is_empty() {
    model_task_fail(InvalidBody, source)
  }
  ignore(
    model_task_integer(
      model_task_required(object, "max_bytes", source),
      true,
      budget,
    ),
  )
  for name in ["max_pages", "max_frames"] {
    let value = match @decode.lookup(object, name) {
      Some(value) => value
      None => model_task_fail(InvalidBody, source)
    }
    if !@decode.is_null(value) {
      ignore(model_task_integer(value, true, budget))
    }
  }
  let complete = model_task_required(object, "complete", source)
  if @decode.boolean(complete) != Ok(true) ||
    model_task_string(object, "transfer_method", source, budget) !=
    "inline_bytes" {
    // The first integrated profile transfers exact complete stored bytes.
    // Truncated input and URL/upload transports are not implicitly admitted.
    model_task_fail(InvalidBody, source)
  }
  ignore(model_task_cid(object, "egress_scope_cid", source, budget))
  for name in ["classifications", "regions"] {
    let values = model_task_required(object, name, source)
    let count = match @decode.array_length(values) {
      Some(count) => count
      None => model_task_fail(InvalidBody, values)
    }
    if count < 1 {
      model_task_fail(InvalidBody, values)
    }
    model_task_charge(budget, count, values)
    let seen : Map[String, Bool] = Map([])
    for index in 0..<count {
      let value = @decode.element_at(values, index).unwrap()
      let text = model_task_text(value, budget)
      if text.is_empty() || seen.contains(text) {
        model_task_fail(InvalidBody, value)
      }
      seen[text] = true
    }
  }
}

///|
pub fn single_attempt_model_media(
  value : SingleAttemptModelDependencies,
  role : String,
) -> ModelDependency? {
  for dependency in value.media {
    if dependency.kind is ModelMediaInput(name) && name == role {
      return Some(dependency)
    }
  }
  None
}

///|
pub fn single_attempt_model_decision(
  value : SingleAttemptModelDependencies,
) -> DecisionContract? {
  value.decision
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
