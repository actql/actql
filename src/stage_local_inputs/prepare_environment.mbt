///|
pub enum PrepareEnvironmentIssue {
  InvalidLimits
  BudgetExceeded
  Index(@refs.Issue)
  Snapshot(Int, @snapshot.MembershipIssue)
  UnknownStage(Int, String)
  Stage(Int, Issue)
  Environment(Int, EnvironmentIssue)
  Collection(ProgramEnvironmentIssue)
}

///|
/// Prepare Local registrations before pipeline construction. Every supplied
/// schema snapshot is read and assigned to its source Stage, including unused
/// inputs. This is not whole-Environment admission or capacity authorization.
pub fn prepare_environment(
  source : @stages.Source,
  environment : @environment.WireEnvironment,
  limits : Limits,
) -> Result[ProgramEnvironmentInputs, PrepareEnvironmentIssue] {
  if limits.max_work < 0 ||
    limits.max_nodes < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let count = @stages.stage_count(source)
  let members = @environment.member_count(
    environment,
    @environment.SchemaSnapshots,
  )
  if count >= limits.max_work || members > limits.max_work - count - 1 {
    return Err(BudgetExceeded)
  }
  let mut work = limits.max_work - count - members - 1
  let mut nodes = limits.max_nodes
  let mut text = limits.max_text_bytes
  let index = match
    @refs.prepare(source, { max_work: work, max_text_bytes: text, }) {
    Ok(v) => v
    Err(e) => return Err(Index(e))
  }
  // Reconciliation reports the exact retained index prefix per Stage, as does
  // assemble_environment. Do not add an extra index prefix here.
  let names : Map[String, Int] = Map([])
  let by_stage : Array[Array[@snapshot.EnvironmentSnapshot]] = Array::makei(
    count,
    _ => [],
  )
  for i in 0..<count {
    let name = @stages.stage_at(source, i).unwrap().id
    if name.length() > work {
      return Err(BudgetExceeded)
    }
    work -= name.length()
    names[name] = i
  }
  for i in 0..<members {
    let entry = @environment.member_at(
      environment,
      @environment.SchemaSnapshots,
      i,
    ).unwrap()
    let admitted = match
      @snapshot.read_member(entry, {
        max_bytes: text,
        max_nodes: if nodes < work {
          nodes
        } else {
          work
        },
        max_depth: limits.max_depth,
      }) {
      Ok(v) => v
      Err(e) => return Err(Snapshot(i, e))
    }
    let snapshot = @snapshot.environment_snapshot(admitted)
    let (bytes, n) = @snapshot.usage(snapshot)
    text -= bytes
    nodes -= n
    work -= n
    let name = @source_ref.stage_name(@snapshot.source_reference(snapshot))
    if name.length() > work {
      return Err(BudgetExceeded)
    }
    work -= name.length()
    let at = match names.get(name) {
      Some(at) => at
      None => return Err(UnknownStage(i, name))
    }
    by_stage[at].push(admitted)
  }
  let mut stage_work = 0
  let mut stage_nodes = 0
  let mut stage_text = 0
  let stages = []
  for i in 0..<count {
    let remaining : Limits = {
      max_work: work,
      max_nodes: nodes,
      max_text_bytes: text,
      max_depth: limits.max_depth,
    }
    let prepared = match prepare(source, i, remaining) {
      Ok(v) => v
      Err(e) => return Err(Stage(i, e))
    }
    // Reconciliation already includes declaration preparation in its usage.
    let checked = match
      reconcile_environment(
        prepared,
        index,
        environment,
        by_stage[i],
        remaining,
      ) {
      Ok(v) => v
      Err(e) => return Err(Environment(i, e))
    }
    let used = environment_usage(checked)
    work -= used.work
    nodes -= used.nodes
    text -= used.text_bytes
    stage_work += used.work
    stage_nodes += used.nodes
    stage_text += used.text_bytes
    stages.push(checked)
  }
  let result = match
    assemble_environment(source, environment, stages, {
      max_work: work + stage_work,
      max_nodes: nodes + stage_nodes,
      max_text_bytes: text + stage_text,
      max_depth: limits.max_depth,
    }) {
    Ok(v) => v
    Err(e) => return Err(Collection(e))
  }
  let used = program_environment_usage(result)
  Ok({
    ..result,
    usage: {
      work: limits.max_work - work + (used.work - stage_work),
      nodes: limits.max_nodes - nodes + (used.nodes - stage_nodes),
      text_bytes: limits.max_text_bytes - text + (used.text_bytes - stage_text),
    },
  })
}
