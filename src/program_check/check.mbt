///|
struct CheckedProgram {
  has_effects : Bool
  keyed_input_proofs : Array[KeyedInputProof]
  nest_limits : Array[Array[NestLimits]]
  traversal_limits : Array[Array[TraversalLimit]]
  sequence_limits : Array[Array[SequenceLimit]]
  interval_search_limits : Array[Array[IntervalSearchLimit]]
  asof_search_limits : Array[Array[AsOfSearchLimit]]
  window_limits : Array[Array[WindowLimit]]
  input_completeness : Array[Array[InputCompletenessRequirement]]
  expression_profiles : @context.ExpressionProfiles
  catalog_references : @environment.CatalogReferences
  identity : @context.ProgramSourceIdentity
  requirements : @context.StageRequirementClosure
  gates : @context.ProgramIncomingGates
  contracts : @context.CoreContractInventory
  units : Array[BuiltUnit]
  group_limits : Array[Array[GroupLimit]]
  analytic_limits : Array[Array[AnalyticLimit]]
  group_string_limits : Array[Array[GroupStringLimit]]
  analytic_string_limits : Array[Array[AnalyticStringLimit]]
  numeric_slots : NumericSlotIdentities
  analytic_numeric_slots : AnalyticNumericSlotIdentities
  pivot_numeric_slots : PivotNumericSlotIdentities
  model_tasks : @environment.ModelTasks?
}

///|
// Initial source-driven integration domain. This is an implementation boundary,
// not a restriction on the language's operation grammar. Broader paths continue
// to require their full semantic and execution closure before entry here.
fn check_supported_source(
  program : @syntax.Program,
  budget : IdentityBudget,
) -> Unit raise LocalConstructionFailure {
  try {
    identity_charge(budget, @syntax.stage_count(program))
    let stages = @syntax.stages(program)
    for stage in 0..<@syntax.stage_count(program) {
      identity_charge(budget, 1)
      let body = @syntax.stage_body(stages[stage])
      for field in 0..<@decode.object_length(body).unwrap() {
        identity_charge(budget, 1)
        let (name, value) = @decode.field_at(body, field).unwrap()
        if name != "steps" {
          continue
        }
        for index in 0..<@decode.array_length(value).unwrap() {
          identity_charge(budget, 1)
          let step = @decode.element_at(value, index).unwrap()
          guard @decode.object_length(step) is Some(members) else {
            raise UnitBuildFailure::UnsupportedStaticPath(step)
          }
          for member_index in 0..<members {
            identity_charge(budget, 1)
            let (key, _) = @decode.field_at(step, member_index).unwrap()
            match key {
              "from"
              | "as"
              | "meta"
              | "derive"
              | "filter"
              | "assert_rows"
              | "group"
              | "select"
              | "rename"
              | "drop"
              | "sort"
              | "take"
              | "distinct"
              | "dedupe_rows"
              | "top_k"
              | "top_k_by"
              | "lag"
              | "json_pick"
              | "unnest"
              | "unpivot"
              | "nest"
              | "pivot"
              | "analytic"
              | "row_window"
              | "window_events"
              | "time_series"
              | "calendar_series"
              | "calendar_bucket"
              | "window_group"
              | "watermark_rows"
              | "append"
              | "except"
              | "intersect"
              | "join"
              | "cross_join"
              | "interval_join"
              | "asof_join"
              | "to_events"
              | "watermark_events"
              | "dedupe_events"
              | "session"
              | "sequence"
              | "events"
              | "property_graph"
              | "node_rows"
              | "edge_rows"
              | "match_nodes"
              | "match_edges"
              | "traverse"
              | "to_vectors"
              | "normalize_vectors"
              | "score_vectors"
              | "vectors"
              | "nearest"
              | "pool_vectors"
              | "merge_rankings"
              | "text_rank"
              | "infer"
              | "values" => ()
              _ => raise UnitBuildFailure::UnsupportedStaticPath(step)
            }
          }
        }
      }
    }
  } catch {
    error => raise Units(error)
  }
}

///|
/// Check the supported Local/SourceView/Result-import domain from source and
/// admission material. Runtime checks are retained; success does not authorize
/// execution. Other static paths currently fail explicitly.
fn check(
  program : @syntax.Program,
  environment : @environment.WireEnvironment,
  supplied : @decode.Cursor?,
  material : Array[Array[@context.CapacityMaterial]],
  expression_profiles : @context.ExpressionProfiles,
  operation_profiles : @context.PureOperationProfiles,
  limits : SourceLimits,
  max_work~ : Int,
  max_bytes~ : Int,
  max_nodes~ : Int,
  max_depth~ : Int,
  numeric_profile? : @numeric.Profile? = None,
  calendar? : @environment.SelectedCalendarProfile? = None,
  text_rank? : @environment.SelectedTextRankProfile? = None,
  capacity_inputs? : @context.ProgramCapacityInputs? = None,
  effect_headers? : @syntax.EffectHeaders? = None,
  property_graph? : Bool = false,
  model_tasks? : @environment.ModelTasks? = None,
) -> CheckedProgram raise LocalConstructionFailure {
  if max_work < 0 || max_bytes < 0 || max_nodes < 0 || max_depth < 0 {
    raise InvalidLimits
  }
  let budget = IdentityBudget::{
    work: max_work,
    bytes: max_bytes,
    nodes: max_nodes,
    depth: max_depth,
  }
  check_supported_source(program, budget)
  let conversions : Array[ProofConversion] = []
  let references : Array[@environment.CatalogReferences] = []
  let (identity, requirements, gates, contracts, units) = construct_local(
    program,
    supplied,
    { wire: environment, locations: None, },
    material,
    expression_profiles,
    operation_profiles,
    limits,
    budget,
    numeric_profile~,
    calendar~,
    text_rank~,
    conversion_out=Some(conversions),
    references_out=Some(references),
    capacity_inputs~,
    effect_headers~,
    property_graph~,
    model_tasks~,
  )
  let conversion = Some(conversions[0])
  audit_source_execution(contracts, units[0].source_execution, budget) catch {
    error => raise Units(error)
  }
  if !units[0].source_execution.is_empty() {
    for stage, unit in units {
      for index, publication in unit.publications {
        identity_charge(budget, 1) catch {
          error => raise Units(error)
        }
        if publication.source_policy is None {
          raise Units(UnclosedPublicationPolicy(stage, index))
        }
      }
    }
  }
  let input_completeness = prepare_input_completeness(units, budget) catch {
    error => raise Units(error)
  }
  let nest_limits = prepare_program_nest_limits(
    units,
    requirements,
    budget,
    conversion~,
  ) catch {
    error => raise Units(error)
  }
  let group_limits = prepare_program_group_limits(
    units,
    requirements,
    budget,
    conversion~,
  ) catch {
    error => raise Units(error)
  }
  let window_limits = prepare_program_window_limits(
    units,
    requirements,
    budget,
    conversion~,
  ) catch {
    error => raise Units(error)
  }
  let sequence_limits = prepare_program_sequence_limits(
    units, requirements, budget,
  ) catch {
    error => raise Units(error)
  }
  let traversal_limits = prepare_program_traversal_limits(
    units,
    requirements,
    budget,
    conversion~,
  ) catch {
    error => raise Units(error)
  }
  let interval_search_limits = prepare_program_interval_search_limits(
    units,
    requirements,
    budget,
    conversion~,
  ) catch {
    error => raise Units(error)
  }
  let analytic_limits = prepare_program_analytic_limits(
    units,
    requirements,
    budget,
    conversion~,
  ) catch {
    error => raise Units(error)
  }
  let asof_search_limits = prepare_program_asof_search_limits(
    units,
    requirements,
    budget,
    conversion~,
  ) catch {
    error => raise Units(error)
  }
  let group_string_limits = prepare_program_group_string_limits(
    units, requirements, budget,
  ) catch {
    error => raise Units(error)
  }
  let analytic_string_limits = prepare_program_analytic_string_limits(
    units, requirements, budget,
  ) catch {
    error => raise Units(error)
  }
  let numeric_slots = prepare_program_numeric_slot_identities(
    units, requirements, budget,
  ) catch {
    error => raise Units(error)
  }
  let analytic_numeric_slots = prepare_program_analytic_numeric_slot_identities(
    units, requirements, budget,
  ) catch {
    error => raise Units(error)
  }
  let pivot_numeric_slots = prepare_program_pivot_numeric_slot_identities(
    units, requirements, budget,
  ) catch {
    error => raise Units(error)
  }
  let keyed_input_proofs = prepare_keyed_input_proofs(
    units,
    units[0].source_execution,
    budget,
    conversion~,
  ) catch {
    error => raise Units(error)
  }
  {
    has_effects: effect_headers is Some(_),
    keyed_input_proofs,
    nest_limits,
    traversal_limits,
    sequence_limits,
    interval_search_limits,
    asof_search_limits,
    window_limits,
    input_completeness,
    expression_profiles,
    catalog_references: references[0],
    identity,
    requirements,
    gates,
    contracts,
    units,
    group_limits,
    analytic_limits,
    group_string_limits,
    analytic_string_limits,
    numeric_slots,
    analytic_numeric_slots,
    pivot_numeric_slots,
    model_tasks,
  }
}

///|
/// Structural Effect declarations remain attached to a computation-only
/// check. Their presence never turns its output into an Effect-free Run.
pub fn checked_program_has_effects(program : CheckedProgram) -> Bool {
  program.has_effects
}

///|
// Close every selected source, not merely the list of successful bindings.
// Mode closure and all operation/publication closures have already succeeded.
fn audit_source_execution(
  inventory : @context.CoreContractInventory,
  checks : Array[SourceExecution],
  budget : IdentityBudget,
) -> Unit raise UnitBuildFailure {
  let requirements = @context.program_source_contract_requirements(
    @context.core_contract_sources(inventory),
  )
  let stages = @context.source_contract_stage_count(requirements)
  let identity = @context.core_contract_identity(inventory)
  let producer = @context.preparation_sources(
    @context.operation_profiles_preparation(
      @context.program_sources_operations(
        @context.program_identity_sources(identity),
      ),
    ),
  )
  let requests = @context.source_rows_requests(
    @context.source_policy_rows(
      @context.source_capacity_context(
        @context.source_producer_capacity(producer),
      ),
    ),
  )
  identity_charge(budget, stages)
  let mut offset = 0
  for stage in 0..<stages {
    let stage_offset = offset
    guard @context.program_identity_stage_requests(identity, stage)
      is Some(selected) else {
      raise ForeignOwner
    }
    let count = @context.source_contract_input_count(requirements, stage).unwrap()
    if @sourceviews.pipeline_requests_count(selected) != count {
      raise ForeignOwner
    }
    for input in 0..<count {
      identity_charge(budget, 1)
      guard checks.get(offset) is Some(first) else {
        raise UnclosedSourceExecution(stage, input)
      }
      let subject = first.subject
      guard physical_equal(
          subject.owner,
          @context.core_contract_identity(inventory),
        ) &&
        subject.stage == stage &&
        subject.input == input &&
        physical_equal(
          subject.source,
          @context.source_contract_input_at(requirements, stage, input).unwrap(),
        ) else {
        raise ForeignOwner
      }
      let expected_request = @sourceviews.pipeline_request_at(selected, input).unwrap()
      match (subject.request, expected_request) {
        (
          @sourceviews.Direct(mode, request),
          @sourceviews.Direct(expected_mode, expected),
        ) => {
          guard subject.direct_policy is Some(policy) else {
            raise UnclosedSourceExecution(stage, input)
          }
          guard physical_equal(mode, expected_mode) &&
            physical_equal(request, expected) &&
            physical_equal(@sourceviews.mode_input(mode), subject.source) &&
            physical_equal(policy.request, request) &&
            physical_equal(policy.response, subject.response_policy) &&
            policy.response_cid == subject.response_policy_cid else {
            raise ForeignOwner
          }
          for
            field in 0..<@sourceviews.parameterized_request_field_count(request) {
            identity_charge(budget, 1)
            if @sourceviews.parameterized_request_field_at(request, field).unwrap().value
              is @sourceviews.UnboundHostBinding(_) {
              raise UnclosedSourceExecution(stage, input)
            }
          }
        }
        (
          @sourceviews.Keyed(mode, request),
          @sourceviews.Keyed(expected_mode, expected),
        ) => {
          guard physical_equal(mode, expected_mode) &&
            physical_equal(request, expected) &&
            physical_equal(@sourceviews.keyed_mode_input(mode), subject.source) &&
            subject.direct_policy is None else {
            raise ForeignOwner
          }
          for
            field in 0..<@sourceviews.parameterized_keyed_request_field_count(
              request,
            ) {
            identity_charge(budget, 1)
            if @sourceviews.parameterized_keyed_request_field_at(request, field).unwrap().value
              is @sourceviews.UnboundHostBinding(_) {
              raise UnclosedSourceExecution(stage, input)
            }
          }
        }
        _ => raise ForeignOwner
      }
      for index in 0..<5 {
        identity_charge(budget, 1)
        guard checks.get(offset + index) is Some(check) else {
          raise UnclosedSourceExecution(stage, input)
        }
        guard physical_equal(check.subject, subject) else { raise ForeignOwner }
        let valid = match (index, check.kind, check.phase, check.failure) {
          (0, HostCombination, BeforeProviderAccess, PreventProviderAccess)
          | (1, ReadAuthorization, BeforeProviderAccess, PreventProviderAccess)
          | (2, RequestEgress, BeforeProviderAccess, PreventProviderAccess)
          | (
            3,
            AcquisitionResources,
            BeforeAndDuringAcquisition,
            FailAcquisitionAtomically,
          )
          | (4, CarrierResponse, BeforeSourceOutputUse, RejectSourceOutput) =>
            true
          _ => false
        }
        if !valid {
          raise UnclosedSourceExecution(stage, input)
        }
        let expected = match index {
          0 => []
          1 => [0]
          2 => [1]
          3 => [0, 1, 2]
          _ => [0, 3]
        }
        if check.prerequisites.length() != expected.length() {
          raise UnclosedSourceExecution(stage, input)
        }
        for dependency, prior in expected {
          identity_charge(budget, 1)
          guard physical_equal(
            check.prerequisites[dependency],
            checks[offset + prior],
          ) else {
            raise ForeignOwner
          }
        }
      }
      offset += 5
    }
    guard @context.source_request_joins(requests, stage) is Some(joins) &&
      @context.source_capacity_stage(
        @context.source_producer_capacity(producer),
        stage,
      )
      is Some(bounds) else {
      raise ForeignOwner
    }
    let join_count = @sourceviews.keyed_join_count(joins)
    if @sourceviews.lookup_bounds_count(bounds) != join_count {
      raise ForeignOwner
    }
    for index in 0..<join_count {
      identity_charge(budget, 1)
      let join = @sourceviews.keyed_join_at(joins, index).unwrap()
      let input = @sourceviews.keyed_join_input(join)
      guard input >= 0 && input < count else { raise ForeignOwner }
      let base = stage_offset + input * 5
      let subject = checks[base].subject
      guard checks.get(offset) is Some(first) &&
        first.kind is KeyedRequest(binding) else {
        raise UnclosedSourceExecution(stage, input)
      }
      guard physical_equal(binding.owner, producer) &&
        binding.stage == stage &&
        binding.index == index &&
        physical_equal(binding.join, join) &&
        physical_equal(binding.bounds, bounds) &&
        physical_equal(
          binding.counts,
          @sourceviews.lookup_bounds_at(bounds, index).unwrap(),
        ) &&
        @context.source_producer_at(producer, stage, index) is Some(membership) &&
        physical_equal(binding.producer, membership) &&
        subject.request is @sourceviews.Keyed(_, request) &&
        physical_equal(request, @sourceviews.keyed_join_request(join)) else {
        raise ForeignOwner
      }
      for part in 0..<4 {
        identity_charge(budget, 1)
        guard checks.get(offset + part) is Some(check) else {
          raise UnclosedSourceExecution(stage, input)
        }
        let actual = match (part, check.kind, check.phase, check.failure) {
          (0, KeyedRequest(value), BeforeProviderAccess, PreventProviderAccess)
          | (1, KeyedEgress(value), BeforeProviderAccess, PreventProviderAccess)
          | (
            2,
            KeyedResources(value),
            BeforeAndDuringAcquisition,
            FailAcquisitionAtomically,
          )
          | (
            3,
            KeyedResponse(value),
            BeforeSourceOutputUse,
            FailAcquisitionAtomically,
          ) => value
          _ => raise UnclosedSourceExecution(stage, input)
        }
        guard physical_equal(actual, binding) &&
          physical_equal(check.subject, subject) else {
          raise ForeignOwner
        }
        let expected = match part {
          0 => [base, base + 3]
          1 => [offset]
          2 => [offset, offset + 1]
          _ => [offset + 2, base + 4]
        }
        if check.prerequisites.length() != expected.length() {
          raise UnclosedSourceExecution(stage, input)
        }
        for dependency, prior in expected {
          identity_charge(budget, 1)
          guard physical_equal(check.prerequisites[dependency], checks[prior]) else {
            raise ForeignOwner
          }
        }
      }
      offset += 4
    }
  }
  if offset != checks.length() {
    raise ForeignOwner
  }
}

///|
pub fn unit_count(program : CheckedProgram) -> Int {
  program.units.length()
}

///|
pub fn unit_definition_cid(program : CheckedProgram, index : Int) -> String? {
  program.units.get(index).map(unit => unit.definition_cid)
}

///|
pub fn unit_pipeline(
  program : CheckedProgram,
  index : Int,
) -> @pipeline.CheckedPipeline? {
  program.units.get(index).map(unit => unit.pipeline)
}

///|
fn checked_selected_policy(
  program : CheckedProgram,
) -> @context.SelectedPolicyContext {
  let sources = @context.program_identity_sources(program.identity)
  let operation_checks = @context.program_sources_operations(sources)
  let preparation = @context.operation_profiles_preparation(operation_checks)
  let producers = @context.preparation_sources(preparation)
  let capacity = @context.source_producer_capacity(producers)
  let policy = @context.source_capacity_context(capacity)
  @context.source_policy_selected(policy)
}

///|
/// Return the exact Environment retained by this checked Program. A matching
/// CID from an independently admitted Environment is not the same owner.
/// This accessor does not itself authorize an Effect or captured Result use.
pub fn checked_environment(
  program : CheckedProgram,
) -> @environment.WireEnvironment {
  @environment.capacity_environment(
    @context.selected_capacity(checked_selected_policy(program)),
  )
}

///|
/// Return the exact Catalog role-reference closure admitted during this
/// Program check. This is static evidence, not current authority or an Effect
/// execution permit; consumers must retain its owner and bind exact members.
pub fn checked_catalog_references(
  program : CheckedProgram,
) -> @environment.CatalogReferences {
  program.catalog_references
}

///|
/// Return the exact typed ModelTask set retained by this checked Program.
/// Runtime dispatch must still perform its own authority and resource
/// admission before invoking a provider.
pub fn checked_model_tasks(
  program : CheckedProgram,
) -> @environment.ModelTasks? {
  program.model_tasks
}

///|
/// Return the exact checked Stage Results retained by this Program. This is
/// an ownership bridge for downstream Run admission, not an Effect permit or
/// authority to use a captured Result. The ordinary checker still rejects
/// Effects until their full static and execution closure is connected.
pub fn checked_stage_results(program : CheckedProgram) -> @results.Checked {
  let selected = checked_selected_policy(program)
  let reconciled = @context.policy_context(selected)
  let wired = @context.reconciled_wiring(reconciled)
  @context.stage_results(@context.wired_stage_contexts(wired))
}

///|
pub fn requirements(
  program : CheckedProgram,
) -> @context.StageRequirementClosure {
  program.requirements
}
