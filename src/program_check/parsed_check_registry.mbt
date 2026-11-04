///|
priv enum EnvironmentAdmissionStart {
  Registry(@environment.ContractRegistry, IdentityBudget, @environment.Limits?)
  Contents(@environment.CatalogContents, IdentityBudget)
  References(@environment.CatalogReferences, IdentityBudget)
  Policies(@environment.SourceDataPolicies, IdentityBudget)
  Values(@environment.ProtocolValueContracts, IdentityBudget)
  Modes(@environment.SourceReadModes, IdentityBudget)
  Carriers(@environment.CarrierSchemas, IdentityBudget)
  Requests(@environment.SourceRequestContracts, IdentityBudget)
  Registered(
    @environment.SourceRequestContracts,
    @environment.CatalogReferences,
    IdentityBudget,
    SourceLimits,
    @sourceviews.PipelineInputs,
    @local_inputs.ProgramEnvironmentInputs
  )
  ReusedModes(
    @environment.SourceRequestContracts,
    @environment.CatalogReferences,
    IdentityBudget
  )
  ReusedCarriers(
    @environment.SourceRequestContracts,
    @environment.CatalogReferences,
    IdentityBudget
  )
  ReusedRequests(
    @environment.SourceRequestContracts,
    @environment.CatalogReferences,
    IdentityBudget
  )
  ReusedValues(
    @environment.SourceRequestContracts,
    @environment.CatalogReferences,
    IdentityBudget
  )
  ReusedReferences(
    @environment.SourceRequestContracts,
    @environment.CatalogReferences,
    IdentityBudget
  )
  ReusedPolicies(
    @environment.SourceRequestContracts,
    @environment.CatalogReferences,
    IdentityBudget
  )
  ReusedContents(
    @environment.SourceRequestContracts,
    @environment.CatalogReferences,
    IdentityBudget
  )
  Reused(
    @environment.SourceRequestContracts,
    @environment.CatalogReferences,
    IdentityBudget
  )
}

///|
pub struct ParsedCatalogInput {
  priv prelude : ParsedCheckPrelude
  priv geometry : @environment.RegistryConstructionGeometry?
  priv initial_work : Int
  priv inspection_work : Int
}

///|
pub struct ParsedCheckRegistry {
  priv prelude : ParsedCheckPrelude
  priv mut start : EnvironmentAdmissionStart
  priv mut available : Bool
  priv collected_source_inputs : Ref[@source_inputs.Inputs?]
}

///|
pub suberror ParsedCatalogPreparationIssue {
  Prelude(ParsedCheckPreludeIssue)
  Check(LocalConstructionFailure)
}

///|
fn parsed_catalog_budget(prelude : ParsedCheckPrelude) -> IdentityBudget {
  let limits = prelude.original.limits.artifacts
  {
    work: prelude.budget.work - prelude.declaration_work,
    bytes: limits.bytes,
    nodes: limits.nodes,
    depth: limits.depth,
  }
}

///|
/// Original retained-Catalog selection, including required-reuse refusal and
/// tighter full-reader fallback. This is DATA selection, not an admission.
pub fn prepare_parsed_catalog_input(
  prelude : ParsedCheckPrelude,
) -> Result[ParsedCatalogInput, ParsedCheckPreludeIssue] {
  if !prelude.available {
    return Err(AlreadyConsumed)
  }
  let budget = parsed_catalog_budget(prelude)
  let original = prelude.original
  let registry_needed = match original.source_catalog {
    Some(catalog) =>
      !source_catalog_replay_fits(catalog.usage, catalog.depth_limit, budget) &&
      !catalog.require_reuse
    None => true
  }
  let geometry = if registry_needed {
    Some(
      @environment.observe_registry_construction_geometry(
        original.environment.wire,
      ),
    )
  } else {
    None
  }
  Ok({
    prelude,
    initial_work: budget.work,
    geometry,
    inspection_work: match geometry {
      Some(g) => g.members
      None => 0
    },
  })
}

///|
pub fn parsed_catalog_inspection_work(input : ParsedCatalogInput) -> Int {
  input.inspection_work
}

///|
pub fn parsed_check_prelude_registry_members(
  prelude : ParsedCheckPrelude,
) -> Int {
  @environment.member_count(
    prelude.original.environment.wire,
    @environment.ContractRegistry,
  )
}

///|
/// Existing restriction, never a memory demand or permission. Used by the
/// original phase receipt before allocation; the prelude is not consumed here.
pub fn parsed_catalog_semantic_work(input : ParsedCatalogInput) -> Int {
  input.initial_work
}

///|
pub fn parsed_catalog_construction_extent(
  input : ParsedCatalogInput,
) -> @environment.RegistryConstructionExtent {
  let domain = match input.geometry {
    Some(g) => @environment.registry_construction_extent(g).unwrap()
    None =>
      {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      }
  }
  // Budget, actual start variant, original caps and usage tuple, original
  // continuation, typed Local/Environment errors and Result/observation tuple.
  // These are fixed constructor roles, not borrowed Catalog/body backing.
  {
    ..domain,
    // One fixed Ref and its existing-registry field retain original Inputs.
    record_headers: domain.record_headers + 10L,
    reference_slots: domain.reference_slots + 11L,
    scalar_words: domain.scalar_words + 15L,
  }
}

///|
/// SAME original reader and exact charged compiler budget. On failure this
/// reports charges performed by that existing meter (e.g. environment_begin),
/// NOT a hash-invocation count or total CPU work. Reader limits stay unchanged.
pub fn observe_parsed_check_registry(
  input : ParsedCatalogInput,
) -> (Result[ParsedCheckRegistry, ParsedCatalogPreparationIssue], Int) {
  let prelude = input.prelude
  if !prelude.available {
    return (Err(Prelude(AlreadyConsumed)), 0)
  }
  prelude.available = false
  let b = parsed_catalog_budget(prelude)
  let before = b.work
  let original = prelude.original
  let result = try {
    let wire = original.environment.wire
    let reuse = match original.source_catalog {
      Some(catalog) => try_reuse_source_catalog_accounting(catalog, wire, b)
      None => false
    }
    let start = if reuse {
      let catalog = original.source_catalog.unwrap()
      Reused(catalog.catalog, catalog.references, b)
    } else {
      Registry(prepare_environment_registry(wire, b, None), b, None)
    }
    Ok({ prelude, start, available: true, collected_source_inputs: Ref(None), })
  } catch {
    issue => Err(Check(Environment(issue)))
  }
  (result, before - b.work)
}

///|
fn finish_environment_admission(
  start : EnvironmentAdmissionStart,
  budget : IdentityBudget,
) -> (@environment.SourceRequestContracts, @environment.CatalogReferences) raise EnvironmentFailure {
  match start {
    Registry(registry, b, limits) =>
      finish_environment_registry(registry, b, budget, limits)
    Contents(contents, b) => finish_environment_contents(contents, b, budget)
    References(references, b) =>
      finish_environment_references(references, b, budget)
    Policies(policies, b) => finish_environment_policies(policies, b, budget)
    Values(values, b) => finish_environment_values(values, b, budget)
    Modes(modes, b) => finish_environment_modes(modes, b, budget)
    Carriers(carriers, b) => finish_environment_carriers(carriers, b, budget)
    Requests(requests, b) => finish_environment_requests(requests, b, budget)
    Registered(catalog, references, b, _, _, _)
    | Reused(catalog, references, b)
    | ReusedContents(catalog, references, b)
    | ReusedReferences(catalog, references, b)
    | ReusedPolicies(catalog, references, b)
    | ReusedValues(catalog, references, b)
    | ReusedModes(catalog, references, b)
    | ReusedCarriers(catalog, references, b)
    | ReusedRequests(catalog, references, b) => {
      budget.work = b.work
      budget.bytes = b.bytes
      budget.nodes = b.nodes
      (catalog, references)
    }
  }
}

///|
pub fn parsed_check_registry_remaining_work(
  prepared : ParsedCheckRegistry,
) -> Result[Int, ParsedCheckPreludeIssue] {
  if !prepared.available {
    return Err(AlreadyConsumed)
  }
  Ok(environment_start_budget(prepared.start).work)
}

///|
/// Full remaining Catalog/Context/Unit overlap MUST be funded before entry.
/// The first registry or retained Catalog accounting is not repeated.
pub fn finish_parsed_check_registry(
  prepared : ParsedCheckRegistry,
) -> Result[CheckOutcome, ParsedCheckPreludeIssue] {
  if !prepared.available {
    return Err(AlreadyConsumed)
  }
  prepared.available = false
  Ok(finish_parsed_check_registry_owned(prepared))
}

///|
fn finish_parsed_check_registry_owned(
  prepared : ParsedCheckRegistry,
  source_context? : @context.SourceViewContextInput? = None,
) -> CheckOutcome {
  let original = prepared.prelude.original
  // This SAME full remaining-check frame has already been backed. Observe
  // caller-owned supplied values before private Program Source resolution.
  // Keep the result beside the original primary outcome, never in its place.
  let (prepared_source, independent_supplied) = if parsed_check_independent_supplied_original(
      prepared,
    )
    is Some((source, supplied)) {
    let limits = source_limits_after_catalog(
      compile_source_limits(original.limits),
      environment_start_budget(prepared.start),
    )
    let (source, result) = @stages.prepare_bindings(source, Some(supplied), {
      max_nodes: limits.topology.max_nodes,
      max_depth: limits.topology.max_depth,
      max_text_bytes: Int::min(
        limits.topology.max_text_bytes,
        limits.context.stages.max_text_bytes,
      ),
    })
    (
      Some(source),
      Some(IndependentSuppliedBinding::{
        program: original.program,
        source,
        supplied,
        result,
      }),
    )
  } else {
    (None, None)
  }
  checking_outcome(
    original.program,
    original.environment,
    () => {
      construct_after_parsed_check_registry(
        prepared,
        source_context~,
        prepared_source~,
      )
    },
    independent_supplied~,
  )
}

///|
// Borrow original DATA only, before any Program Source selection. The caller
// separately owns currentness, entry backing and the actual binding read.
fn parsed_check_independent_supplied_original(
  prepared : ParsedCheckRegistry,
) -> (@stages.Source, @decode.Cursor)? {
  match prepared.start {
    Requests(_, _) | ReusedRequests(_, _, _) => {
      let original = prepared.prelude.original
      let limits = source_limits_after_catalog(
        compile_source_limits(original.limits),
        environment_start_budget(prepared.start),
      )
      if original.source_preparation is Some(source) &&
        original.supplied is Some(supplied) &&
        @stages.reuse_prepared(source, original.program, {
          max_parameters: limits.max_parameters,
          max_nodes: limits.topology.max_nodes,
          max_depth: limits.topology.max_depth,
          max_text_bytes: limits.topology.max_text_bytes,
        })
        is Some(source) {
        Some((source, supplied))
      } else {
        None
      }
    }
    _ => None
  }
}

///|
fn construct_after_parsed_check_registry(
  prepared : ParsedCheckRegistry,
  source_context? : @context.SourceViewContextInput? = None,
  prepared_source? : @stages.Source? = None,
) -> CheckedProgram raise LocalConstructionFailure {
  let prelude = prepared.prelude
  let {
    program,
    environment,
    supplied,
    effect_headers,
    inputs,
    limits,
    source_catalog,
    source_preparation,
  } = prelude.original
  let source_preparation = match prepared_source {
    Some(source) => Some(source)
    None => source_preparation
  }
  let source_limits = match prepared.start {
    Registered(_, _, _, selected, _, _) => selected
    _ => compile_source_limits(limits)
  }
  check_after_prelude(
    program,
    environment.wire,
    supplied,
    [],
    environment.expressions,
    environment.operations,
    source_limits,
    prelude.budget,
    prelude.declaration_work,
    has_effects=effect_headers is Some(_),
    numeric_profile=environment.numeric,
    calendar=environment.calendar,
    text_rank=environment.text_rank,
    capacity_inputs=Some(inputs),
    graph=environment.graph,
    model_tasks=environment.model_tasks,
    request_value_policies=environment.request_value_policies,
    source_catalog~,
    source_preparation~,
    environment_start=Some(prepared.start),
    source_context~,
    collected_inputs_out=Some(prepared.collected_source_inputs),
  )
}

///|
/// Immutable declaration DATA retained by this same consumed checker. No
/// collection, binding, resolution, authority or completed check is issued.
pub fn parsed_check_collected_source_inputs(
  prepared : ParsedCheckRegistry,
) -> @source_inputs.Inputs? {
  if prepared.available {
    None
  } else {
    prepared.collected_source_inputs.val
  }
}

///|
pub fn parsed_catalog_retained_extent(
  input : ParsedCatalogInput,
) -> @environment.RegistryConstructionExtent {
  let domain = match input.geometry {
    Some(g) =>
      @environment.registry_retained_construction_extent(g.members).unwrap()
    None =>
      {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      }
  }
  // Keep the original continuation/budget/control envelope conservatively.
  {
    ..domain,
    // One fixed Ref and its existing-registry field retain original Inputs.
    record_headers: domain.record_headers + 10L,
    reference_slots: domain.reference_slots + 11L,
    scalar_words: domain.scalar_words + 15L,
  }
}

///|
fn environment_start_budget(
  start : EnvironmentAdmissionStart,
) -> IdentityBudget {
  match start {
    Registry(_, b, _)
    | Contents(_, b)
    | References(_, b)
    | Policies(_, b)
    | Values(_, b)
    | Modes(_, b)
    | Carriers(_, b)
    | Requests(_, b)
    | Reused(_, _, b)
    | ReusedContents(_, _, b)
    | ReusedReferences(_, _, b)
    | ReusedPolicies(_, _, b)
    | ReusedValues(_, _, b)
    | ReusedModes(_, _, b)
    | ReusedCarriers(_, _, b)
    | ReusedRequests(_, _, b)
    | Registered(_, _, b, _, _, _) => b
  }
}
