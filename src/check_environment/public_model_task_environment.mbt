///|
priv enum PublicTaskEnvironmentMember {
  Original(Entry)
  ProjectedTask(NormalizedPublicModelTask)
}

///|
/// Bounded wire adapter for the same projection. Reserve outer admission's
/// parse/decode/hash traversals before UTF8 materialization; this work ceiling
/// is not physical workspace funding or installation/current admission.
pub fn read_project_public_model_task_environment(
  wire : String,
  evidence_cid : String,
  tasks : Array[NormalizedPublicModelTask],
  limits : ModelTaskLimits,
) -> Result[(String, String, Int), ModelTaskIssue] {
  if limits.max_work < 0 ||
    limits.bodies.max_bytes < 0 ||
    limits.bodies.max_nodes < 0 ||
    limits.bodies.max_depth < 0 ||
    limits.bodies.max_members < 0 ||
    limits.contracts.max_nodes < 0 ||
    limits.contracts.max_depth < 0 ||
    limits.contracts.max_text_bytes < 0 {
    return Err({ kind: InvalidLimits, source: None, })
  }
  let mut remaining = limits.max_work
  for _ in 0..<6 {
    for amount in [limits.bodies.max_bytes, limits.bodies.max_nodes] {
      if amount > remaining {
        return Err({ kind: WorkLimit, source: None, })
      }
      remaining -= amount
    }
  }
  match @scalar.admit_utf8_length(wire, limits.bodies.max_bytes) {
    Ok(_) => ()
    Err(_) => return Err({ kind: BodyLimit, source: None, })
  }
  let environment = match
    read(@utf8.encode(wire), evidence_cid, limits.bodies) {
    Ok(value) => value
    Err(_) => return Err({ kind: InvalidBody, source: None, })
  }
  project_public_model_task_environment(environment, tasks, {
    ..limits,
    max_work: remaining,
  }).map(value => (value.0, value.1, limits.max_work - remaining + value.2))
}

///|
/// Extend only the Task inventory of an already admitted outer Environment.
/// This is a bounded canonical DATA projection, not a checked Environment,
/// installation, Run, permission or capacity issuer. The ordinary checker
/// still admits the complete result, including duplicate Task selectors.
pub fn project_public_model_task_environment(
  environment : WireEnvironment,
  tasks : Array[NormalizedPublicModelTask],
  limits : ModelTaskLimits,
) -> Result[(String, String, Int), ModelTaskIssue] {
  let root = environment.root
  if limits.max_work < 0 ||
    limits.bodies.max_bytes < 0 ||
    limits.bodies.max_nodes < 0 ||
    limits.bodies.max_depth < 0 ||
    limits.bodies.max_members < 0 ||
    limits.contracts.max_nodes < 0 ||
    limits.contracts.max_depth < 0 ||
    limits.contracts.max_text_bytes < 0 {
    return Err({ kind: InvalidLimits, source: Some(root), })
  }
  if environment.members > limits.bodies.max_members ||
    tasks.length() > limits.bodies.max_members - environment.members {
    return Err({ kind: TaskLimit, source: Some(root), })
  }
  // The original writer already observed each final member's UTF8 bytes,
  // value nodes and depth. Fold only those scalar cells; do not emit, parse,
  // normalize or validate an earlier Task again to quote this final writer.
  // Keeping the original base includes its existing array and CID spelling.
  let mut output_bytes = environment.bytes.to_int64()
  let mut output_nodes = environment.nodes.to_int64()
  let mut output_depth = @decode.admission_usage(environment.root).depth
  for task in tasks {
    output_bytes += task.task_bytes.to_int64() + 1L
    output_nodes += task.task_nodes.to_int64()
    output_depth = Int::max(output_depth, task.task_depth + 2)
  }
  if output_bytes > limits.bodies.max_bytes.to_int64() ||
    output_nodes > limits.bodies.max_nodes.to_int64() ||
    output_depth > limits.bodies.max_depth {
    return Err({ kind: BodyLimit, source: Some(root), })
  }
  let selected = {
    ..limits,
    bodies: {
      ..limits.bodies,
      max_bytes: output_bytes.to_int(),
      max_nodes: output_nodes.to_int(),
      max_depth: output_depth,
    },
  }
  let budget : ModelTaskBudget = {
    limits: selected,
    work: 0,
    contract_nodes: 0,
    contract_text: 0,
  }
  try {
    model_task_charge(budget, tasks.length(), root)
    let entries : Array[(String, PublicTaskEnvironmentMember)] = []
    for entry in environment.sections[position(ModelTaskContracts)] {
      model_task_charge(budget, 1, root)
      entries.push((entry.cid, Original(entry)))
    }
    for task in tasks {
      // The complete member hash is distinct from its Task self-identity.
      // Reserve before UTF8 allocation/hash; the original material is not
      // decoded or reconstructed by a Host-side JSON implementation.
      model_task_charge(budget, task.task_bytes, root)
      match @scalar.admit_utf8_length(task.task_wire, limits.bodies.max_bytes) {
        Ok(_) => ()
        Err(_) => model_task_fail(BodyLimit, root)
      }
      let cid = "sha256:" + @sha.hex(@utf8.encode(task.task_wire))
      entries.push((cid, ProjectedTask(task)))
    }
    // Bounded insertion over the existing evidence-member identity order.
    // Count every comparison, including the complete fixed-size CID text.
    for index in 1..<entries.length() {
      let entry = entries[index]
      let mut next = index
      while next > 0 {
        model_task_charge(budget, 1, root)
        model_task_charge(budget, entry.0.length(), root)
        model_task_charge(budget, entries[next - 1].0.length(), root)
        if entries[next - 1].0 <= entry.0 {
          break
        }
        entries[next] = entries[next - 1]
        next -= 1
      }
      entries[next] = entry
    }
    let writer = public_task_emission_writer(budget, root)
    emit_public_task_environment(environment, entries, None, writer, budget)
    let (preimage, preimage_bytes, _, _) = @encode.finish_text_usage(writer)
    model_task_charge(budget, preimage_bytes, root)
    let identity = "sha256:" + @sha.hex(@utf8.encode(preimage))
    let writer = public_task_emission_writer(budget, root)
    emit_public_task_environment(
      environment,
      entries,
      Some(identity),
      writer,
      budget,
    )
    Ok((@encode.finish(writer), identity, budget.work))
  } catch {
    ModelTaskStop(issue) => Err(issue)
    _ => Err({ kind: BodyLimit, source: Some(root), })
  }
}

///|
fn emit_public_task_environment(
  environment : WireEnvironment,
  tasks : Array[(String, PublicTaskEnvironmentMember)],
  identity : String?,
  writer : @encode.Writer,
  budget : ModelTaskBudget,
) -> Unit raise {
  @encode.begin_object(writer)
  for index in 0..<@decode.object_length(environment.root).unwrap() {
    model_task_charge(budget, 1, environment.root)
    let (key, child) = @decode.field_at(environment.root, index).unwrap()
    if key == "evidence_bundle_cid" {
      if identity is Some(value) {
        @encode.key(writer, key)
        @encode.string_value(writer, value)
      }
    } else if key == "model_task_contracts" {
      @encode.key(writer, key)
      @encode.begin_array(writer)
      for (_, task) in tasks {
        model_task_charge(budget, 1, environment.root)
        match task {
          Original(entry) => emit_cursor(entry.cursor, writer, false)
          ProjectedTask(task) =>
            emit_normalized_public_task(
              task.declaration,
              task.provider,
              task.resolved,
              task.handling,
              task.prompt_cid,
              Some(task.task_cid),
              writer,
              budget,
            )
        }
      }
      @encode.end_array(writer)
    } else {
      @encode.key(writer, key)
      emit_cursor(child, writer, false)
    }
  }
  @encode.end_object(writer)
}
