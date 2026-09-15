///|
/// Graph input measures, independent of downstream application aggregation.
pub(all) enum Measure {
  Nodes
  Edges
} derive(Eq, Debug)

///|
pub(all) struct Limits {
  max_work : Int
  max_name_bytes : Int
}

///|
pub(all) enum Issue {
  InvalidLimits
  BudgetExceeded
  MissingMixedClosure
  UnknownInput(String)
  WrongCarrier(String)
  UnsupportedEnforcedLaw(Int)
  MissingMeasure(Int, Measure)
  DuplicateMeasure(Int, Measure)
  SubjectMismatch(Int)
  UnsupportedCandidate(Int, Int)
  CandidateScopeMismatch(Int, Int)
  UnconsumedLimits(Int)
  ForeignDependency(Int)
} derive(Eq, Debug)

///|
struct GraphInputs {
  pipeline : @pipeline.CheckedPipeline
  sources : @host.HostSources
  policy : @policy.Policy
  bindings : Array[(@wire.LimitClaim?, @wire.LimitClaim?)]
  witnesses : Array[(@wire.WireWitness?, @wire.WireWitness?)]
  work : Int
  names : Int
  remaining : Int
  dependencies : Array[GraphInputs]
}

///|
/// Binds the fixed compiler's Host-backed Graph input preflight form.
/// Does not execute preflight or admit an observed input count.
pub fn check(
  pipeline : @pipeline.CheckedPipeline,
  sources : @host.HostSources,
  policy : @policy.Policy,
  limits : Limits,
  producers? : Array[GraphInputs] = [],
) -> Result[GraphInputs, Issue] {
  if limits.max_work < 0 || limits.max_name_bytes < 0 {
    return Err(InvalidLimits)
  }
  guard @wire.program_claim_mixed(@host.source_claims(sources)) is Some(mixed) else {
    return Err(MissingMixedClosure)
  }
  let claims = @wire.mixed_arithmetic(mixed)
  let n = @pipeline.input_count(pipeline)
  let count = @wire.claim_count(claims)
  if n > limits.max_work / 2 || count > limits.max_work - n * 2 {
    return Err(BudgetExceeded)
  }
  let mut work = n * 2 + count
  let mut names = 0
  let mut consumed = 0
  let dependencies : Array[GraphInputs] = []
  for i in 0..<@host.source_dependency_count(sources) {
    if limits.max_work - work < 2 {
      return Err(BudgetExceeded)
    }
    work += 2
    let origin = @host.source_dependency_at(sources, i).unwrap()
    let mut matched = None
    for producer in producers {
      if work == limits.max_work {
        return Err(BudgetExceeded)
      }
      work += 1
      if @host.same_source_origin(origin, producer.sources) &&
        @policy.cid(policy) == @policy.cid(producer.policy) {
        matched = Some(producer)
        break
      }
    }
    guard matched is Some(producer) else { return Err(ForeignDependency(i)) }
    dependencies.push(producer)
  }
  let inputs : Map[String, Int] = Map([])
  let bindings : Array[(@wire.LimitClaim?, @wire.LimitClaim?)] = Array::make(
    n,
    (None, None),
  )
  let witnesses : Array[(@wire.WireWitness?, @wire.WireWitness?)] = Array::make(
    n,
    (None, None),
  )
  for i in 0..<n {
    let (name, _) = @pipeline.input_at(pipeline, i).unwrap()
    let bytes = match
      @scalar.admit_utf8_length(name, limits.max_name_bytes - names) {
      Ok(v) => v
      Err(_) => return Err(BudgetExceeded)
    }
    names += bytes
    inputs[name] = i
  }
  for i in 0..<count {
    guard @wire.mixed_enforced_limit(mixed, i) is Some(limit) else { continue }
    if !@host.source_enforcement_is_local(sources, i) {
      continue
    }
    let witness = @wire.claim_at(claims, i).unwrap()
    let measure = match @law.name(@wire.law(witness)) {
      "actql.bound.graph-input-nodes" => Nodes
      "actql.bound.graph-input-edges" => Edges
      _ => return Err(UnsupportedEnforcedLaw(i))
    }
    // Mixed closure already checks the exact Program proof/limit association.
    guard @wire.source(witness) is @wire.Program(name, _) else {
      return Err(UnsupportedEnforcedLaw(i))
    }
    guard inputs.get(name) is Some(input) else {
      return Err(UnknownInput(name))
    }
    if @carrier.kind(@pipeline.input_at(pipeline, input).unwrap().1) !=
      @carrier.GraphKind {
      return Err(WrongCarrier(name))
    }
    let (suffix, field, unit) = match measure {
      Nodes => ("nodes", "max_graph_input_nodes", @arithmetic.Nodes)
      Edges => ("edges", "max_graph_input_edges", @arithmetic.Edges)
    }
    if @wire.limit_subject(limit) != "graph-input:" + name + ":" + suffix ||
      @wire.unit(witness) != unit {
      return Err(SubjectMismatch(i))
    }
    let pair = bindings[input]
    if (if measure == Nodes { pair.0 } else { pair.1 }) is Some(_) {
      return Err(DuplicateMeasure(input, measure))
    }
    let minimum = @wire.limit_minimum(limit)
    let candidates = @arithmetic.minimum_candidate_count(minimum)
    if candidates > limits.max_work - work {
      return Err(BudgetExceeded)
    }
    work += candidates
    for j in 0..<candidates {
      let candidate = @arithmetic.minimum_candidate_at(minimum, j).unwrap()
      guard @host.source_at(sources, candidate.node) is Some(source) else {
        return Err(UnsupportedCandidate(i, j))
      }
      let ceiling = @host.ceiling(source)
      if @policy.cid(@policy.ceiling_policy(ceiling)) != @policy.cid(policy) ||
        @policy.ceiling_field(ceiling) != field {
        return Err(CandidateScopeMismatch(i, j))
      }
    }
    bindings[input] = if measure == Nodes {
      (Some(limit), pair.1)
    } else {
      (pair.0, Some(limit))
    }
    let prior = witnesses[input]
    witnesses[input] = if measure == Nodes {
      (Some(witness), prior.1)
    } else {
      (prior.0, Some(witness))
    }
    consumed += 1
  }
  for i in 0..<n {
    if @carrier.kind(@pipeline.input_at(pipeline, i).unwrap().1) ==
      @carrier.GraphKind {
      if bindings[i].0 is None {
        return Err(MissingMeasure(i, Nodes))
      }
      if bindings[i].1 is None {
        return Err(MissingMeasure(i, Edges))
      }
    }
  }
  // Each accepted limit has one exact input/measure subject; duplicate measures
  // have already failed. Distinct bindings therefore consume distinct limits.
  Ok({
    pipeline,
    sources,
    policy,
    bindings,
    witnesses,
    work,
    names,
    remaining: @host.source_local_limit_count(sources) - consumed,
    dependencies,
  })
}

///|
pub fn dependency_count(v : GraphInputs) -> Int {
  v.dependencies.length()
}

///|
pub fn dependency_at(v : GraphInputs, index : Int) -> GraphInputs? {
  v.dependencies.get(index)
}

///|
/// Requires complete consumption of this collection by Graph input preflights.
/// Does not validate other operation consumers or authorize execution.
pub fn check_complete(
  pipeline : @pipeline.CheckedPipeline,
  sources : @host.HostSources,
  policy : @policy.Policy,
  limits : Limits,
) -> Result[GraphInputs, Issue] {
  match check(pipeline, sources, policy, limits) {
    Err(e) => Err(e)
    Ok(v) =>
      if v.remaining == 0 {
        Ok(v)
      } else {
        Err(UnconsumedLimits(v.remaining))
      }
  }
}

///|
pub fn unconsumed_limit_count(v : GraphInputs) -> Int {
  v.remaining
}

///|
pub fn checked_pipeline(v : GraphInputs) -> @pipeline.CheckedPipeline {
  v.pipeline
}

///|
pub fn checked_sources(v : GraphInputs) -> @host.HostSources {
  v.sources
}

///|
pub fn selected_policy(v : GraphInputs) -> @policy.Policy {
  v.policy
}

///|
pub fn input_limit(
  v : GraphInputs,
  input : Int,
  measure : Measure,
) -> @wire.LimitClaim? {
  match v.bindings.get(input) {
    Some(pair) => if measure == Nodes { pair.0 } else { pair.1 }
    None => None
  }
}

///|
pub fn usage(v : GraphInputs) -> (Int, Int) {
  (v.work, v.names)
}

///|
/// Conditional input bound retaining the complete validated preflight owner.
/// Construction does not execute its unit-preflight enforcement obligation.
struct InputBound {
  owner : GraphInputs
  input : Int
  witness : @wire.WireWitness
}

///|
pub fn input_bound(
  v : GraphInputs,
  input : Int,
  measure : Measure,
) -> InputBound? {
  v.witnesses
  .get(input)
  .bind(pair => {
    (if measure == Nodes { pair.0 } else { pair.1 }).map(witness => {
      owner: v,
      input,
      witness,
    })
  })
}

///|
pub fn bound_owner(v : InputBound) -> GraphInputs {
  v.owner
}

///|
pub fn bound_input(v : InputBound) -> Int {
  v.input
}

///|
pub fn bound_witness(v : InputBound) -> @wire.WireWitness {
  v.witness
}
