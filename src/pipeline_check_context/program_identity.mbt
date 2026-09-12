///|
pub(all) struct ProgramIdentityLimits {
  max_work : Int
  max_stages : Int
  max_hash_bytes : Int
  max_hash_nodes : Int
  max_depth : Int
} derive(Eq, Debug)

///|
pub(all) enum ProgramIdentityPhase {
  ProgramSemantics
  Definition
  ParameterValues
} derive(Eq, Debug)

///|
pub enum ProgramIdentityIssue {
  InvalidLimits
  BudgetExceeded
  SourceSemantics(@program_refs.ProgramSemanticsIssue)
  Hash(ProgramIdentityPhase, @encode.EncodeFailure)
}

///|
struct ProgramSourceIdentity {
  sources : ProgramSourceChecks
  definition : @program_refs.ProgramDefinition
  definition_cid : String
  parameter_values_cid : String
  work : Int
  hash_bytes : Int
  hash_nodes : Int
}

///|
/// Close source Definition and whole-Program used Parameter identity ownership.
/// No identity or value set is independently supplied. This is not an Invocation
/// or the final static Program boundary; Host Bindings remain unresolved.
pub fn identify_program_sources(
  sources : ProgramSourceChecks,
  limits : ProgramIdentityLimits,
) -> Result[ProgramSourceIdentity, ProgramIdentityIssue] {
  if limits.max_work < 0 ||
    limits.max_stages < 0 ||
    limits.max_hash_bytes < 0 ||
    limits.max_hash_nodes < 0 ||
    limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  if sources.work >= limits.max_work {
    return Err(BudgetExceeded)
  }
  let values = sources.references.references
  let usage = @program_refs.parameter_usage(values)
  // Existing source-check work already includes declaration-use preparation.
  // Subtract that shared prefix before translating the remaining work cap.
  let prefix = sources.work - @program_refs.usage_work(usage)
  let semantics = match
    @program_refs.prepare_program_semantics(usage, {
      max_work: limits.max_work - prefix - 1,
      max_stages: limits.max_stages,
      max_hash_bytes: limits.max_hash_bytes,
      max_hash_nodes: limits.max_hash_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(v) => v
    Err(e) => return Err(SourceSemantics(e))
  }
  let (stage_bytes, stage_nodes) = @program_refs.program_semantics_hash_usage(
    semantics,
  )
  let definition = @program_refs.prepare_program_definition(
    semantics,
    limits.max_hash_bytes - stage_bytes,
    limits.max_hash_nodes - stage_nodes,
    limits.max_depth,
  ) catch {
    e => return Err(Hash(ProgramSemantics, e))
  }
  let (program_bytes, program_nodes) = @program_refs.program_definition_hash_usage(
    definition,
  )
  let mut bytes = stage_bytes + program_bytes
  let mut nodes = stage_nodes + program_nodes
  let definition_hash = try {
    let writer = @encode.hashing_writer(
      limits.max_hash_bytes - bytes,
      limits.max_hash_nodes - nodes,
      limits.max_depth,
    )
    @program_refs.emit_program_definition(definition, writer)
    @encode.finish_hash_usage(writer)
  } catch {
    e => return Err(Hash(Definition, e))
  }
  bytes += definition_hash.1
  nodes += definition_hash.2
  let parameter_hash = try {
    let writer = @encode.hashing_writer(
      limits.max_hash_bytes - bytes,
      limits.max_hash_nodes - nodes,
      limits.max_depth,
    )
    @references.emit_used_values(
      @program_refs.program_parameter_values(values),
      writer,
    )
    @encode.finish_hash_usage(writer)
  } catch {
    e => return Err(Hash(ParameterValues, e))
  }
  bytes += parameter_hash.1
  nodes += parameter_hash.2
  Ok({
    sources,
    definition,
    definition_cid: "sha256:" + definition_hash.0,
    parameter_values_cid: "sha256:" + parameter_hash.0,
    work: prefix + @program_refs.program_semantics_work(semantics) + 1,
    hash_bytes: bytes,
    hash_nodes: nodes,
  })
}

///|
pub fn program_identity_sources(
  v : ProgramSourceIdentity,
) -> ProgramSourceChecks {
  v.sources
}

///|
pub fn program_identity_definition(
  v : ProgramSourceIdentity,
) -> @program_refs.ProgramDefinition {
  v.definition
}

///|
pub fn program_identity_definition_cid(v : ProgramSourceIdentity) -> String {
  v.definition_cid
}

///|
pub fn program_identity_parameter_values_cid(
  v : ProgramSourceIdentity,
) -> String {
  v.parameter_values_cid
}

///|
/// Inclusive source-check work and cumulative bytes/nodes of all four hash
/// phases (stage envelopes, Program semantics, Definition, Parameter Values).
pub fn program_identity_usage(v : ProgramSourceIdentity) -> (Int, Int, Int) {
  (v.work, v.hash_bytes, v.hash_nodes)
}
