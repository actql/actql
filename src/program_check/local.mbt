///|
pub suberror LocalConstructionFailure {
  InvalidLimits
  Program(@syntax.SyntaxError)
  CapacityInputs(@context.CapacityInputsIssue)
  Environment(EnvironmentFailure)
  Source(SourceFailure)
  Closure(ConstructionFailure)
  Units(UnitBuildFailure)
  Template(TemplateDeclarationPreparation, TemplateConstructionIssue)
}

///|
fn construct_local_after_declarations(
  program : @syntax.Program,
  supplied : @decode.Cursor?,
  environment : SourceEnvironment,
  material : Array[Array[@context.CapacityMaterial]],
  expression_profiles : @context.ExpressionProfiles,
  operation_profiles : @context.PureOperationProfiles,
  limits : SourceLimits,
  budget : IdentityBudget,
  declaration_work : Int,
  numeric_profile? : @numeric.Profile? = None,
  calendar? : @environment.SelectedCalendarProfile? = None,
  text_rank? : @environment.SelectedTextRankProfile? = None,
  conversion_out? : Array[ProofConversion]? = None,
  references_out? : Array[@environment.CatalogReferences]? = None,
  capacity_inputs? : @context.ProgramCapacityInputs? = None,
  graph? : Bool = false,
  model_tasks? : @environment.ModelTasks? = None,
  request_value_policies? : Array[HostRequestValuePolicyEvidence] = [],
  source_catalog? : PreparedSourceCatalog? = None,
  source_preparation? : @stages.Source? = None,
  environment_start? : EnvironmentAdmissionStart? = None,
  source_context? : @context.SourceViewContextInput? = None,
  collected_inputs_out? : Ref[@source_inputs.Inputs?]? = None,
) -> (
  @context.ProgramSourceIdentity,
  @context.StageRequirementClosure,
  @context.ProgramIncomingGates,
  @context.CoreContractInventory,
  Array[BuiltUnit],
) raise LocalConstructionFailure {
  let work_limit = budget.work - declaration_work
  let admission = IdentityBudget::{
    work: work_limit,
    bytes: budget.bytes,
    nodes: budget.nodes,
    depth: budget.depth,
  }
  let wire = environment.wire
  let (catalog, references) = try {
    match environment_start {
      Some(start) => finish_environment_admission(start, admission)
      None =>
        match source_catalog {
          Some(prepared) => reuse_source_catalog(prepared, wire, admission)
          None => prepare_environment(wire, admission)
        }
    }
  } catch {
    e => raise Environment(e)
  }
  let locations = environment.locations
  let work_limit = admission.work
  // Cap every preparatory pass before it allocates, not after a large source
  // preparation has already consumed more than the enclosing work allowance.
  let limits = match environment_start {
    Some(Registered(_, _, _, selected, _, _)) => selected
    _ => source_limits_after_catalog(limits, admission)
  }
  let derived_capacity_limits : @wire.Limits? = if capacity_inputs is Some(_) {
    Some({
      max_bytes: limits.identity.identity.max_hash_bytes,
      max_nodes: limits.identity.identity.max_hash_nodes,
      max_depth: limits.identity.identity.max_depth,
    })
  } else {
    None
  }
  let identity = match environment_start {
    Some(Registered(_, _, _, _, views, locals)) =>
      prepare_registered_catalog_source(
        views,
        locals,
        supplied,
        material,
        locations,
        expression_profiles,
        operation_profiles,
        limits,
        calendar~,
        graph~,
        capacity_inputs~,
        model_tasks~,
        derived_capacity_limits~,
        source_context~,
      ) catch {
        e => raise Source(e)
      }
    _ =>
      prepare_catalog_source(
        program,
        supplied,
        catalog,
        material,
        locations,
        expression_profiles,
        operation_profiles,
        limits,
        calendar~,
        graph~,
        source_preparation~,
        capacity_inputs~,
        model_tasks~,
        derived_capacity_limits~,
        collected_inputs_out~,
      ) catch {
        e => raise Source(e)
      }
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
  let units = build_units(
    contracts,
    requirements,
    gates,
    remaining,
    request_value_policies~,
  ) catch {
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

///|
// The SAME remaining Catalog meter bounds every later preparatory pass.
// Retained registration and the uninterrupted checker use this one projection.
fn source_limits_after_catalog(
  limits : SourceLimits,
  admission : IdentityBudget,
) -> SourceLimits {
  let work_limit = admission.work
  {
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
        max_depth: Int::min(limits.identity.identity.max_depth, admission.depth),
      },
    },
  }
}
