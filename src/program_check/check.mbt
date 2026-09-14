///|
struct CheckedProgram {
  traversal_limits : Array[Array[TraversalLimit]]
  components_limits : Array[Array[ComponentsLimit]]
  sequence_limits : Array[Array[SequenceLimit]]
  interval_search_limits : Array[Array[IntervalSearchLimit]]
  asof_search_limits : Array[Array[AsOfSearchLimit]]
  window_limits : Array[Array[WindowLimit]]
  input_completeness : Array[Array[InputCompletenessRequirement]]
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
              | "graph"
              | "normalize_graph"
              | "degree"
              | "components"
              | "graph_bounds"
              | "graphs_equal"
              | "graph_diff"
              | "apply_graph_delta"
              | "match_nodes"
              | "match_edges"
              | "subgraph"
              | "traverse"
              | "reach"
              | "shortest_path"
              | "graft_graph"
              | "union_graphs"
              | "subtract_graphs"
              | "mean_graphs"
              | "to_vectors"
              | "normalize_vectors"
              | "score_vectors"
              | "vectors"
              | "nearest"
              | "pool_vectors"
              | "merge_rankings"
              | "text_rank"
              | "node_rows"
              | "edge_rows"
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
/// Check the supported Local/direct-SourceView/Result-import domain from source and
/// admission material. Runtime checks are retained; success does not authorize
/// execution. Other static paths currently fail explicitly.
pub fn check(
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
  )
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
  let group_limits = prepare_program_group_limits(units, requirements, budget) catch {
    error => raise Units(error)
  }
  let window_limits = prepare_program_window_limits(units, requirements, budget) catch {
    error => raise Units(error)
  }
  let sequence_limits = prepare_program_sequence_limits(
    units, requirements, budget,
  ) catch {
    error => raise Units(error)
  }
  let components_limits = prepare_program_components_limits(
    units, requirements, budget,
  ) catch {
    error => raise Units(error)
  }
  let traversal_limits = prepare_program_traversal_limits(
    units, requirements, budget,
  ) catch {
    error => raise Units(error)
  }
  let interval_search_limits = prepare_program_interval_search_limits(
    units, requirements, budget,
  ) catch {
    error => raise Units(error)
  }
  let analytic_limits = prepare_program_analytic_limits(
    units, requirements, budget,
  ) catch {
    error => raise Units(error)
  }
  let asof_search_limits = prepare_program_asof_search_limits(
    units, requirements, budget,
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
  {
    traversal_limits,
    components_limits,
    sequence_limits,
    interval_search_limits,
    asof_search_limits,
    window_limits,
    input_completeness,
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
  }
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
  identity_charge(budget, stages)
  let mut offset = 0
  for stage in 0..<stages {
    let count = @context.source_contract_input_count(requirements, stage).unwrap()
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
      guard subject.request is @sourceviews.Direct(mode, request) &&
        subject.direct_policy is Some(policy) else {
        raise UnclosedSourceExecution(stage, input)
      }
      guard physical_equal(@sourceviews.mode_input(mode), subject.source) &&
        physical_equal(policy.request, request) &&
        physical_equal(policy.response, subject.response_policy) &&
        policy.response_cid == subject.response_policy_cid else {
        raise ForeignOwner
      }
      for field in 0..<@sourceviews.parameterized_request_field_count(request) {
        identity_charge(budget, 1)
        if @sourceviews.parameterized_request_field_at(request, field).unwrap().value
          is @sourceviews.UnboundHostBinding(_) {
          raise UnclosedSourceExecution(stage, input)
        }
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
pub fn requirements(
  program : CheckedProgram,
) -> @context.StageRequirementClosure {
  program.requirements
}
