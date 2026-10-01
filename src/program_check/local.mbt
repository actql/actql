///|
pub suberror LocalConstructionFailure {
  InvalidLimits
  Program(@syntax.SyntaxError)
  CapacityInputs(@context.CapacityInputsIssue)
  Environment(EnvironmentFailure)
  Source(SourceFailure)
  Closure(ConstructionFailure)
  Units(UnitBuildFailure)
}

///|
// Internal construction result only. Complete semantic-role selection and
// execution-binding coverage must precede the future CheckedProgram seal.
fn construct_local(
  program : @syntax.Program,
  supplied : @decode.Cursor?,
  environment : SourceEnvironment,
  material : Array[Array[@context.CapacityMaterial]],
  expression_profiles : @context.ExpressionProfiles,
  operation_profiles : @context.PureOperationProfiles,
  limits : SourceLimits,
  budget : IdentityBudget,
  numeric_profile? : @numeric.Profile? = None,
  calendar? : @environment.SelectedCalendarProfile? = None,
  text_rank? : @environment.SelectedTextRankProfile? = None,
  conversion_out? : Array[ProofConversion]? = None,
  references_out? : Array[@environment.CatalogReferences]? = None,
  capacity_inputs? : @context.ProgramCapacityInputs? = None,
  effect_headers? : @syntax.EffectHeaders? = None,
  model_tasks? : @environment.ModelTasks? = None,
) -> (
  @context.ProgramSourceIdentity,
  @context.StageRequirementClosure,
  @context.ProgramIncomingGates,
  @context.CoreContractInventory,
  Array[BuiltUnit],
) raise LocalConstructionFailure {
  if budget.work < 0 || budget.bytes < 0 || budget.nodes < 0 || budget.depth < 0 {
    raise InvalidLimits
  }
  let declaration_work = audit_declarations(
    program,
    budget.work,
    effect_headers~,
  ) catch {
    e => raise Source(e)
  }
  let work_limit = budget.work - declaration_work
  let admission = IdentityBudget::{
    work: work_limit,
    bytes: budget.bytes,
    nodes: budget.nodes,
    depth: budget.depth,
  }
  let wire = environment.wire
  let (catalog, references) = prepare_environment(wire, admission) catch {
    e => raise Environment(e)
  }
  let locations = environment.locations
  let work_limit = admission.work
  // Cap every preparatory pass before it allocates, not after a large source
  // preparation has already consumed more than the enclosing work allowance.
  let limits : SourceLimits = {
    ..limits,
    topology: {
      ..limits.topology,
      max_work: Int::min(limits.topology.max_work, work_limit),
    },
    context: {
      ..limits.context,
      stages: {
        ..limits.context.stages,
        max_work: Int::min(limits.context.stages.max_work, work_limit),
      },
    },
    requests: {
      ..limits.requests,
      max_work: Int::min(limits.requests.max_work, work_limit),
    },
    checks: { ..limits.checks, work: Int::min(limits.checks.work, work_limit), },
    identity: {
      ..limits.identity,
      body: {
        ..limits.identity.body,
        max_work: Int::min(limits.identity.body.max_work, work_limit),
      },
      uses: {
        ..limits.identity.uses,
        max_work: Int::min(limits.identity.uses.max_work, work_limit),
      },
      references: {
        ..limits.identity.references,
        max_work: Int::min(limits.identity.references.max_work, work_limit),
      },
      identity: {
        ..limits.identity.identity,
        max_work: Int::min(limits.identity.identity.max_work, work_limit),
        max_hash_bytes: Int::min(
          limits.identity.identity.max_hash_bytes,
          admission.bytes,
        ),
        max_hash_nodes: Int::min(
          limits.identity.identity.max_hash_nodes,
          admission.nodes,
        ),
        max_depth: Int::min(limits.identity.identity.max_depth, budget.depth),
      },
    },
  }
  let identity = prepare_catalog_source(
    program,
    supplied,
    catalog,
    material,
    locations,
    expression_profiles,
    operation_profiles,
    limits,
    calendar~,
    capacity_inputs~,
    model_tasks~,
    derived_capacity_limits=if capacity_inputs is Some(_) {
      Some({
        max_bytes: limits.identity.identity.max_hash_bytes,
        max_nodes: limits.identity.identity.max_hash_nodes,
        max_depth: limits.identity.identity.max_depth,
      })
    } else {
      None
    },
  ) catch {
    e => raise Source(e)
  }
  let (_, bytes, nodes) = @context.program_identity_usage(identity)
  let (generated_bytes, generated_nodes) = @context.program_identity_capacity_metadata_usage(
    identity,
  )
  let remaining = IdentityBudget::{
    work: work_limit,
    bytes: admission.bytes - bytes - generated_bytes,
    nodes: admission.nodes - nodes - generated_nodes,
    depth: budget.depth,
  }
  // Closure accounts for the source work prefix once; hashes are incremental
  // here and must instead receive only the remaining bytes/nodes.
  let (requirements, gates, contracts) = prepare_owned_closure(
    identity,
    remaining,
    numeric_profile~,
    calendar~,
    text_rank~,
  ) catch {
    e => raise Closure(e)
  }
  let units = build_units(contracts, requirements, gates, remaining) catch {
    e => raise Units(e)
  }
  let conversion = proof_conversion(units, remaining) catch {
    e => raise Units(e)
  }
  let units = prepare_unit_publications(
    units,
    remaining,
    conversion=Some(conversion),
  ) catch {
    e => raise Units(e)
  }
  // No partial result or externally visible budget mutation on late failure.
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  if conversion_out is Some(output) {
    output.push(conversion)
  }
  if references_out is Some(output) {
    output.push(references)
  }
  (identity, requirements, gates, contracts, units)
}

///|
priv struct SourceEnvironment {
  wire : @environment.WireEnvironment
  locations : Array[Array[(Int, Int)]]?
}
