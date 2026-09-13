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
  StageDefinition(Int)
  StageParameterValues(Int)
  StageParameterDeclarations(Int)
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
  stages : Array[StageSourceIdentity]
  work : Int
  hash_bytes : Int
  hash_nodes : Int
}

///|
struct StageSourceIdentity {
  definition : @program_refs.StageDefinition
  definition_cid : String
  values : @references.BoundIndex
  values_cid : String
  declarations_cid : String
}

///|
/// Close Program/Stage Definitions and whole/local used Parameter identities,
/// including local annotation-free declaration maps for Unit extraction.
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
  let count = @program_refs.program_semantics_stage_count(semantics)
  let work = prefix + @program_refs.program_semantics_work(semantics) + 1
  if count > limits.max_work - work {
    return Err(BudgetExceeded)
  }
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
  let stages = []
  for i in 0..<count {
    let local_definition = @program_refs.stage_definition_at(semantics, i).unwrap()
    let local_values = @program_refs.stage_parameter_values(values, i).unwrap()
    let local_hash = try {
      let writer = @encode.hashing_writer(
        limits.max_hash_bytes - bytes,
        limits.max_hash_nodes - nodes,
        limits.max_depth,
      )
      @program_refs.emit_stage_definition(local_definition, writer)
      @encode.finish_hash_usage(writer)
    } catch {
      e => return Err(Hash(StageDefinition(i), e))
    }
    bytes += local_hash.1
    nodes += local_hash.2
    let local_parameter_hash = try {
      let writer = @encode.hashing_writer(
        limits.max_hash_bytes - bytes,
        limits.max_hash_nodes - nodes,
        limits.max_depth,
      )
      @references.emit_used_values(local_values, writer)
      @encode.finish_hash_usage(writer)
    } catch {
      e => return Err(Hash(StageParameterValues(i), e))
    }
    bytes += local_parameter_hash.1
    nodes += local_parameter_hash.2
    let declarations_hash = try {
      let writer = @encode.hashing_writer(
        limits.max_hash_bytes - bytes,
        limits.max_hash_nodes - nodes,
        limits.max_depth,
      )
      @program_refs.emit_stage_parameter_declarations(
        @program_refs.stage_definition_semantics(local_definition),
        writer,
      )
      @encode.finish_hash_usage(writer)
    } catch {
      e => return Err(Hash(StageParameterDeclarations(i), e))
    }
    bytes += declarations_hash.1
    nodes += declarations_hash.2
    stages.push({
      definition: local_definition,
      definition_cid: "sha256:" + local_hash.0,
      values: local_values,
      values_cid: "sha256:" + local_parameter_hash.0,
      declarations_cid: "sha256:" + declarations_hash.0,
    })
  }
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
    stages,
    work: work + count,
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
/// Inclusive source-check work and cumulative bytes/nodes of stage semantics,
/// Program semantics, all Definitions, local declarations and local/Program
/// Parameter Values.
pub fn program_identity_usage(v : ProgramSourceIdentity) -> (Int, Int, Int) {
  (v.work, v.hash_bytes, v.hash_nodes)
}

///|
/// Return the already checked requests owned by this Program and Stage.
/// Equal request contents from another preparation do not substitute for ownership.
pub fn program_identity_stage_requests(
  v : ProgramSourceIdentity,
  stage_index : Int,
) -> @sourceviews.PipelineRequests? {
  source_request_stage(
    v.sources.operations.preparation.sources.capacity.context.rows.requests,
    stage_index,
  )
}

///|
pub fn program_identity_stage_count(v : ProgramSourceIdentity) -> Int {
  v.stages.length()
}

///|
pub fn program_identity_stage_at(
  v : ProgramSourceIdentity,
  index : Int,
) -> StageSourceIdentity? {
  v.stages.get(index)
}

///|
/// All retained producer visits, not only sites with unresolved obligations or
/// selected Results. Reads do not copy pipelines or reset preparation budgets.
pub fn program_identity_producer_count(
  v : ProgramSourceIdentity,
  stage : Int,
) -> Int? {
  let stages = v.sources.operations.preparation.profiles.context.selected.context.wired.stages
  stages.contexts.get(stage).map(context => context.visits.length())
}

///|
/// Preserve the exact pipeline owner for operation and contract-root traversal.
/// Repeated visits remain distinct coordinates even when they share a pipeline.
pub fn program_identity_producer_at(
  v : ProgramSourceIdentity,
  stage : Int,
  visit : Int,
) -> @pipeline.CheckedPipeline? {
  let stages = v.sources.operations.preparation.profiles.context.selected.context.wired.stages
  stages.contexts
  .get(stage)
  .bind(context => {
    context.visits
    .get(visit)
    .map(entry => @parameter_slots.pipeline(entry.collected))
  })
}

///|
/// Distinguish the Stage's authored pipeline from predecessor visits retained
/// for validation. Imported execution prerequisites are not local Unit bodies.
pub fn program_identity_producer_is_local(
  v : ProgramSourceIdentity,
  stage : Int,
  visit : Int,
) -> Bool? {
  let stages = v.sources.operations.preparation.profiles.context.selected.context.wired.stages
  guard program_identity_producer_at(v, stage, visit) is Some(pipeline) else {
    return None
  }
  @stage_results.stage_at(stages.results, stage).map(result => {
    physical_equal(pipeline, @results.pipeline(result))
  })
}

///|
pub fn stage_identity_definition(
  v : StageSourceIdentity,
) -> @program_refs.StageDefinition {
  v.definition
}

///|
pub fn stage_identity_definition_cid(v : StageSourceIdentity) -> String {
  v.definition_cid
}

///|
pub fn stage_identity_parameter_values(
  v : StageSourceIdentity,
) -> @references.BoundIndex {
  v.values
}

///|
pub fn stage_identity_parameter_values_cid(v : StageSourceIdentity) -> String {
  v.values_cid
}

///|
pub fn stage_identity_parameter_declarations_cid(
  v : StageSourceIdentity,
) -> String {
  v.declarations_cid
}

///|
/// Unit body reference for an extracted stage: its full semantic envelope,
/// not the raw local_body member, Stage Definition or enclosing Program.
/// Reuses the owned hash without additional emission or allocation.
pub fn stage_identity_local_body_cid(v : StageSourceIdentity) -> String {
  @program_refs.stage_definition_semantics_cid(v.definition)
}

///|
/// Read the exact governing root emitted in this stage's semantic preimage.
/// No second declaration, replacement CID or independent checker result is used.
pub fn stage_identity_expression_contract_cid(
  v : StageSourceIdentity,
) -> String {
  @program_refs.stage_semantics_expression_contract(
    @program_refs.stage_definition_semantics(v.definition),
  )
}

///|
/// Resolve only the inherited text/time edge of the owned expression root.
/// None denotes unsupported contract interpretation, never an empty closure.
/// Other expression dependencies and whole-Unit selection remain separate.
pub fn stage_identity_inherited_text_time(
  v : StageSourceIdentity,
) -> @environment.InheritedTextTimeContract? {
  @environment.inherited_text_time_for_expression(
    stage_identity_expression_contract_cid(v),
  )
}

///|
/// Resolve declared expression body references from the owned semantic root.
/// This does not select other Unit roots or discharge runtime obligations.
pub fn stage_identity_expression_body(
  v : StageSourceIdentity,
) -> @environment.ExpressionContractBody? {
  @environment.expression_contract_body(
    stage_identity_expression_contract_cid(v),
  )
}
