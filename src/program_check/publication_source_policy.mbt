///|
pub struct PublicationSourcePolicy {
  // Acquisition provenance before predicate contributions, not the final policy.
  policy : DirectSourcePolicy?
  effective : EffectivePolicy
  cid : String
  prerequisite : SourceExecution?
  target : @pipeline.Target
  unknown_provenance : Bool
  imported_publication : PublicationExecution?
  priv predicates : Array[PublicationPolicyPredicate]
  priv slices : Array[PublicationPolicySlice]
  priv sources : Array[SourceExecution]
  priv imports : Array[PublicationPolicyImport]
  priv edges : Array[PublicationPolicyEdge]
  priv generators : Array[PublicationPolicyGenerator]
  priv locals : Array[@context.LocalInputExecutionCheck]
  priv copies : Array[PublicationPolicyCopies]
  priv derivations : Array[PublicationPolicyDerivation]
  priv groups : Array[PublicationPolicyGroup]
  priv pivots : Array[PublicationPolicyPivot]
  priv analytics : Array[PublicationPolicyAnalytic]
  priv lags : Array[PublicationPolicyLag]
  priv unpivots : Array[PublicationPolicyUnpivot]
  priv json_picks : Array[PublicationPolicyJsonPick]
  priv unnests : Array[PublicationPolicyUnnest]
  priv top_ks : Array[PublicationPolicyTopK]
  priv watermarks : Array[PublicationPolicyWatermark]
  priv nests : Array[PublicationPolicyNest]
  priv temporal_joins : Array[PublicationPolicyTemporalJoin]
  priv carrier_steps : Array[PublicationPolicyCarrierStep]
  priv model_steps : Array[PublicationPolicyModelStep]
}

///|
/// An external model observation is not a pure transfer of the source policy.
/// Keep its checked occurrence for capture admission while retaining all of
/// its input provenance. Static preparation alone cannot attest its output.
pub struct PublicationPolicyModelStep {
  step : Int
  infer : @evidence.CheckedInfer
}

///|
pub fn publication_policy_model_step_count(
  value : PublicationSourcePolicy,
) -> Int {
  value.model_steps.length()
}

///|
pub fn publication_policy_model_step_at(
  value : PublicationSourcePolicy,
  index : Int,
) -> PublicationPolicyModelStep? {
  value.model_steps.get(index)
}

///|
pub struct PublicationPolicyCarrierStep {
  step : Int
  operation : @pipeline.CheckedOperation
  unknown_provenance : Bool
}

///|
pub fn publication_policy_carrier_step_count(
  value : PublicationSourcePolicy,
) -> Int {
  value.carrier_steps.length()
}

///|
pub fn publication_policy_carrier_step_at(
  value : PublicationSourcePolicy,
  index : Int,
) -> PublicationPolicyCarrierStep? {
  value.carrier_steps.get(index)
}

///|
pub struct PublicationPolicyTemporalJoin {
  step : Int
  operation : @pipeline.CheckedOperation
  unknown_provenance : Bool
}

///|
pub fn publication_policy_temporal_join_count(
  value : PublicationSourcePolicy,
) -> Int {
  value.temporal_joins.length()
}

///|
pub fn publication_policy_temporal_join_at(
  value : PublicationSourcePolicy,
  index : Int,
) -> PublicationPolicyTemporalJoin? {
  value.temporal_joins.get(index)
}

///|
pub struct PublicationPolicyNest {
  step : Int
  operation : @nest.CheckedNest
  unknown_provenance : Bool
}

///|
pub fn publication_policy_nest_count(value : PublicationSourcePolicy) -> Int {
  value.nests.length()
}

///|
pub fn publication_policy_nest_at(
  value : PublicationSourcePolicy,
  index : Int,
) -> PublicationPolicyNest? {
  value.nests.get(index)
}

///|
pub struct PublicationPolicyWatermark {
  step : Int
  operation : @relation.CheckedOperation
  threshold : @relation.WatermarkSource
}

///|
pub fn publication_policy_watermark_count(
  value : PublicationSourcePolicy,
) -> Int {
  value.watermarks.length()
}

///|
pub fn publication_policy_watermark_at(
  value : PublicationSourcePolicy,
  index : Int,
) -> PublicationPolicyWatermark? {
  value.watermarks.get(index)
}

///|
pub struct PublicationPolicyTopK {
  step : Int
  operation : @relation.CheckedOperation
  count : @relation.CountValue
}

///|
pub fn publication_policy_top_k_count(value : PublicationSourcePolicy) -> Int {
  value.top_ks.length()
}

///|
pub fn publication_policy_top_k_at(
  value : PublicationSourcePolicy,
  index : Int,
) -> PublicationPolicyTopK? {
  value.top_ks.get(index)
}

///|
pub struct PublicationPolicyUnnest {
  step : Int
  operation : @relation.CheckedOperation
}

///|
pub fn publication_policy_unnest_count(value : PublicationSourcePolicy) -> Int {
  value.unnests.length()
}

///|
pub fn publication_policy_unnest_at(
  value : PublicationSourcePolicy,
  index : Int,
) -> PublicationPolicyUnnest? {
  value.unnests.get(index)
}

///|
pub struct PublicationPolicyJsonPick {
  step : Int
  operation : @relation.CheckedOperation
}

///|
pub fn publication_policy_json_pick_count(
  value : PublicationSourcePolicy,
) -> Int {
  value.json_picks.length()
}

///|
pub fn publication_policy_json_pick_at(
  value : PublicationSourcePolicy,
  index : Int,
) -> PublicationPolicyJsonPick? {
  value.json_picks.get(index)
}

///|
pub struct PublicationPolicyUnpivot {
  step : Int
  operation : @relation.CheckedOperation
}

///|
pub fn publication_policy_unpivot_count(value : PublicationSourcePolicy) -> Int {
  value.unpivots.length()
}

///|
pub fn publication_policy_unpivot_at(
  value : PublicationSourcePolicy,
  index : Int,
) -> PublicationPolicyUnpivot? {
  value.unpivots.get(index)
}

///|
pub struct PublicationPolicyLag {
  step : Int
  operation : @relation.CheckedOperation
  field : @relation.KeyField
  output : String
  offset : @relation.CountValue
}

///|
pub fn publication_policy_lag_count(value : PublicationSourcePolicy) -> Int {
  value.lags.length()
}

///|
pub fn publication_policy_lag_at(
  value : PublicationSourcePolicy,
  index : Int,
) -> PublicationPolicyLag? {
  value.lags.get(index)
}

///|
pub struct PublicationPolicyAnalytic {
  step : Int
  operation : @relation.CheckedOperation
  analytic : @relation.CheckedAnalytic
  unknown_provenance : Bool
}

///|
pub fn publication_policy_analytic_count(
  value : PublicationSourcePolicy,
) -> Int {
  value.analytics.length()
}

///|
pub fn publication_policy_analytic_at(
  value : PublicationSourcePolicy,
  index : Int,
) -> PublicationPolicyAnalytic? {
  value.analytics.get(index)
}

///|
pub struct PublicationPolicyPivot {
  step : Int
  operation : @relation.CheckedOperation
  pivot : @relation.CheckedPivot
  unknown_provenance : Bool
}

///|
pub fn publication_policy_pivot_count(value : PublicationSourcePolicy) -> Int {
  value.pivots.length()
}

///|
pub fn publication_policy_pivot_at(
  value : PublicationSourcePolicy,
  index : Int,
) -> PublicationPolicyPivot? {
  value.pivots.get(index)
}

///|
pub struct PublicationPolicyGroup {
  step : Int
  operation : @relation.CheckedOperation
  group : @relation.CheckedGroup
  unknown_provenance : Bool
}

///|
pub fn publication_policy_group_count(value : PublicationSourcePolicy) -> Int {
  value.groups.length()
}

///|
pub fn publication_policy_group_at(
  value : PublicationSourcePolicy,
  index : Int,
) -> PublicationPolicyGroup? {
  value.groups.get(index)
}

///|
pub struct PublicationPolicyDerivation {
  step : Int
  operation : @relation.CheckedOperation
  unknown_provenance : Bool
}

///|
pub fn publication_policy_derivation_count(
  value : PublicationSourcePolicy,
) -> Int {
  value.derivations.length()
}

///|
pub fn publication_policy_derivation_at(
  value : PublicationSourcePolicy,
  index : Int,
) -> PublicationPolicyDerivation? {
  value.derivations.get(index)
}

///|
pub struct PublicationPolicyCopies {
  step : Int
  operation : @relation.CheckedOperation
}

///|
pub fn publication_policy_copy_count(value : PublicationSourcePolicy) -> Int {
  value.copies.length()
}

///|
pub fn publication_policy_copy_at(
  value : PublicationSourcePolicy,
  index : Int,
) -> PublicationPolicyCopies? {
  value.copies.get(index)
}

///|
pub fn publication_policy_local_check_count(
  value : PublicationSourcePolicy,
) -> Int {
  value.locals.length()
}

///|
pub fn publication_policy_local_check_at(
  value : PublicationSourcePolicy,
  index : Int,
) -> @context.LocalInputExecutionCheck? {
  value.locals.get(index)
}

///|
pub struct PublicationPolicyGenerator {
  step : Int
  operation : @pipeline.CheckedOperation
}

///|
pub fn publication_policy_generator_count(
  value : PublicationSourcePolicy,
) -> Int {
  value.generators.length()
}

///|
pub fn publication_policy_generator_at(
  value : PublicationSourcePolicy,
  index : Int,
) -> PublicationPolicyGenerator? {
  value.generators.get(index)
}

///|
pub struct PublicationPolicyEdge {
  step : Int
  occurrence : @pipeline.InputOccurrence
}

///|
pub struct PublicationPolicyImport {
  input : Int
  publication : PublicationExecution
}

///|
pub fn publication_policy_source_count(value : PublicationSourcePolicy) -> Int {
  value.sources.length()
}

///|
pub fn publication_policy_source_at(
  value : PublicationSourcePolicy,
  index : Int,
) -> SourceExecution? {
  value.sources.get(index)
}

///|
pub fn publication_policy_import_count(value : PublicationSourcePolicy) -> Int {
  value.imports.length()
}

///|
pub fn publication_policy_import_at(
  value : PublicationSourcePolicy,
  index : Int,
) -> PublicationPolicyImport? {
  value.imports.get(index)
}

///|
pub fn publication_policy_edge_count(value : PublicationSourcePolicy) -> Int {
  value.edges.length()
}

///|
pub fn publication_policy_edge_at(
  value : PublicationSourcePolicy,
  index : Int,
) -> PublicationPolicyEdge? {
  value.edges.get(index)
}

///|
pub struct PublicationPolicySlice {
  step : Int
  operation : @relation.CheckedOperation
  count : @relation.CountValue
  offset : @relation.CountValue
}

///|
pub fn publication_policy_slice_count(value : PublicationSourcePolicy) -> Int {
  value.slices.length()
}

///|
pub fn publication_policy_slice_at(
  value : PublicationSourcePolicy,
  index : Int,
) -> PublicationPolicySlice? {
  value.slices.get(index)
}

///|
pub fn publication_policy_classification(
  value : PublicationSourcePolicy,
) -> @environment.DataClassification {
  effective_policy_classification(value.effective)
}

///|
pub struct PublicationPolicyPredicate {
  step : Int
  expression : @typing.TypedExpression
  unknown_provenance : Bool
}

///|
pub fn publication_policy_predicate_count(
  value : PublicationSourcePolicy,
) -> Int {
  value.predicates.length()
}

///|
pub fn publication_policy_predicate_at(
  value : PublicationSourcePolicy,
  index : Int,
) -> PublicationPolicyPredicate? {
  value.predicates.get(index)
}

///|
pub fn emit_publication_source_policy(
  value : PublicationSourcePolicy,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_effective_policy(value.effective, writer)
}

///|
// Field leaves inherit the retained input provenance. Other leaves lack an
// admitted value-policy attestation. Scan every node even after finding one so
// preparation work does not depend on the position of the first unknown leaf.
fn publication_expression_unknown(
  expression : @typing.TypedExpression,
  budget : IdentityBudget,
) -> Bool raise UnitBuildFailure {
  let mut missing = false
  for node in 0..<@typing.node_count(expression) {
    identity_charge(budget, 1)
    if @typing.child_count(expression, node) == Some(0) {
      match @typing.node_form(expression, node).unwrap() {
        Expression("field" | "join_field", _) => ()
        _ => missing = true
      }
    }
  }
  missing
}

///|
// Visit checked vertices once; retain all input edges without expanding paths.
fn prepare_publication_source_policy(
  unit : BuiltUnit,
  publication : @context.PublicationResolution,
  budget : IdentityBudget,
  producers? : Array[BuiltUnit]? = None,
) -> PublicationSourcePolicy? raise UnitBuildFailure {
  prepare_target_source_policy(
    unit,
    publication.stage,
    @publication.target(@publication.port_result(publication.port)),
    budget,
    producers~,
  )
}

///|
/// Reuse the publication provenance walk at the model's checked input edge.
/// This describes input policy, not a model response or dispatch permission.
pub fn prepare_infer_input_source_policy(
  program : CheckedProgram,
  unit : Int,
  index : Int,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> PublicationSourcePolicy? raise UnitBuildFailure {
  if max_work < 0 || max_bytes < 0 || max_nodes < 0 || max_depth < 0 {
    raise BudgetExceeded
  }
  guard program.units.get(unit) is Some(selected) &&
    @pipeline.step_at(selected.pipeline, index) is Some(step) &&
    step.operation is @pipeline.Infer(_) &&
    @pipeline.input_occurrence_count(step) == 1 &&
    @pipeline.input_occurrence_at(step, 0) is Some(input) else {
    raise ForeignOwner
  }
  prepare_target_source_policy(
    selected,
    unit,
    input.target,
    { work: max_work, bytes: max_bytes, nodes: max_nodes, depth: max_depth, },
    producers=Some(program.units),
  )
}

///|
fn prepare_target_source_policy(
  unit : BuiltUnit,
  stage : Int,
  original : @pipeline.Target,
  budget : IdentityBudget,
  producers? : Array[BuiltUnit]? = None,
) -> PublicationSourcePolicy? raise UnitBuildFailure {
  if unit.source_execution.is_empty() {
    return None
  }
  let pending = [original]
  let visited_steps : Map[Int, Bool] = Map([])
  let visited_inputs : Map[Int, Bool] = Map([])
  let source_ids : Map[String, Bool] = Map([])
  let sources : Array[SourceExecution] = []
  let imports : Array[PublicationPolicyImport] = []
  let edges : Array[PublicationPolicyEdge] = []
  let predicates : Array[PublicationPolicyPredicate] = []
  let slices : Array[PublicationPolicySlice] = []
  let generators : Array[PublicationPolicyGenerator] = []
  let locals : Array[@context.LocalInputExecutionCheck] = []
  let copies : Array[PublicationPolicyCopies] = []
  let derivations : Array[PublicationPolicyDerivation] = []
  let groups : Array[PublicationPolicyGroup] = []
  let pivots : Array[PublicationPolicyPivot] = []
  let analytics : Array[PublicationPolicyAnalytic] = []
  let lags : Array[PublicationPolicyLag] = []
  let unpivots : Array[PublicationPolicyUnpivot] = []
  let json_picks : Array[PublicationPolicyJsonPick] = []
  let unnests : Array[PublicationPolicyUnnest] = []
  let top_ks : Array[PublicationPolicyTopK] = []
  let watermarks : Array[PublicationPolicyWatermark] = []
  let nests : Array[PublicationPolicyNest] = []
  let temporal_joins : Array[PublicationPolicyTemporalJoin] = []
  let carrier_steps : Array[PublicationPolicyCarrierStep] = []
  let model_steps : Array[PublicationPolicyModelStep] = []
  // A single named keyed input can have several correlation producers. Index
  // the owned gates by join occurrence, never by response CID or input name.
  let keyed_responses : Map[Int, SourceExecution] = Map([])
  for check in unit.source_execution {
    identity_charge(budget, 1)
    if check.subject.stage == stage && check.kind is KeyedResponse(binding) {
      let step = @sourceviews.keyed_join_step(binding.join)
      if keyed_responses.contains(step) {
        raise ForeignOwner
      }
      keyed_responses[step] = check
    }
  }
  let mut unknown = false
  while pending.pop() is Some(target) {
    identity_charge(budget, 1)
    match target {
      @pipeline.Step(index) => {
        if visited_steps.contains(index) {
          continue
        }
        visited_steps[index] = true
        let step = @pipeline.step_at(unit.pipeline, index).unwrap()
        let mut keyed_right = false
        let expected = match step.operation {
          @pipeline.Infer(infer) => {
            // Follow the exact input edge without claiming that its policy
            // attests the external response. The execution/publication owner
            // must separately bind the model's adopted slot captures.
            model_steps.push({ step: index, infer, })
            unknown = true
            1
          }
          @pipeline.Values(_) | @pipeline.TimeSeries(_) => {
            identity_charge(budget, 1)
            generators.push({ step: index, operation: step.operation, })
            unknown = true
            0
          }
          @pipeline.Calendar(operation) => {
            identity_charge(budget, 1)
            if @calendar.input(operation) is Some(_) {
              carrier_steps.push({
                step: index,
                operation: step.operation,
                unknown_provenance: false,
              })
              1
            } else {
              generators.push({ step: index, operation: step.operation, })
              unknown = true
              0
            }
          }
          @pipeline.Unary(operation) | @pipeline.WindowGroup(operation) => {
            match @relation.operation(operation) {
              Select | Rename | Drop | Sort | Distinct | DedupeRows => ()
              WatermarkRows => {
                identity_charge(budget, 1)
                guard @relation.row_operation(operation)
                  is Some(Watermark(threshold~, ..)) else {
                  raise ForeignOwner
                }
                watermarks.push({ step: index, operation, threshold, })
                unknown = true
              }
              TopK | TopKBy => {
                identity_charge(budget, 1)
                guard @relation.top_k_count(operation) is Some(count) else {
                  raise ForeignOwner
                }
                // Selection counts lack an admitted value classification.
                // Keep the exact operation to distinguish global/partitioned k.
                top_ks.push({ step: index, operation, count, })
                unknown = true
              }
              Unnest => {
                identity_charge(budget, 1)
                guard @relation.reshape(operation) is Some(Unnest(..)) else {
                  raise ForeignOwner
                }
                // Elements, positions and outer placeholders derive from the
                // input array. Retain its policy without inventing provenance.
                unnests.push({ step: index, operation, })
              }
              JsonPick => {
                identity_charge(budget, 1)
                guard @relation.json_pick_source(operation) is Some(_) &&
                  @relation.json_pick_path_count(operation) > 0 else {
                  raise ForeignOwner
                }
                // Paths denote structural object keys, not emitted values.
                json_picks.push({ step: index, operation, })
              }
              Unpivot => {
                identity_charge(budget, 1)
                guard @relation.unpivot_outputs(operation) is Some(_) &&
                  @relation.unpivot_columns_count(operation) > 0 else {
                  raise ForeignOwner
                }
                unpivots.push({ step: index, operation, })
                // The authored field-reference labels become output values.
                // Their spelling alone supplies no classification attestation.
                unknown = true
              }
              Lag => {
                identity_charge(budget, 1)
                guard @relation.lag_navigation(operation)
                  is Some((field, output, offset)) else {
                  raise ForeignOwner
                }
                lags.push({ step: index, operation, field, output, offset, })
                // An explicit or defaulted navigation distance is a value, not
                // an admitted classification. Preserve all input provenance too.
                unknown = true
              }
              Analytic => {
                guard @relation.analytic(operation) is Some(analytic) else {
                  raise ForeignOwner
                }
                let mut missing = false
                for binding in 0..<@relation.binding_count(operation) {
                  identity_charge(budget, 1)
                  if publication_expression_unknown(
                      @relation.binding_expression_at(operation, binding).unwrap(),
                      budget,
                    ) {
                    missing = true
                  }
                }
                if @relation.analytic_frame(analytic) is Some(frame) {
                  for boundary in [frame.start, frame.end] {
                    identity_charge(budget, 1)
                    match boundary {
                      Preceding(_) | Following(_) => missing = true
                      UnboundedPreceding | CurrentRow | UnboundedFollowing => ()
                    }
                  }
                }
                for call in 0..<@relation.analytic_call_count(analytic) {
                  identity_charge(budget, 1)
                  match
                    @relation.analytic_call_at(analytic, call).unwrap().function {
                    Lag(..) | Lead(..) => missing = true
                    Aggregate(aggregate) =>
                      if @relation.aggregate_delimiter(aggregate) is Some(_) ||
                        @relation.aggregate_fraction(aggregate) is Some(_) ||
                        @relation.aggregate_item_limit(aggregate) is Some(_) ||
                        @relation.aggregate_byte_limit(aggregate) is Some(_) {
                        missing = true
                      }
                    RowNumber
                    | Rank
                    | DenseRank
                    | FirstValue(_)
                    | LastValue(_) => ()
                  }
                }
                identity_charge(budget, 1)
                analytics.push({
                  step: index,
                  operation,
                  analytic,
                  unknown_provenance: missing,
                })
                unknown = unknown || missing
              }
              Pivot => {
                guard @relation.pivot(operation) is Some(pivot) else {
                  raise ForeignOwner
                }
                // Declared bucket values are data comparisons as well as output
                // names. Authorship and typed fill admission are not policy
                // attestations. Retain their exact owner without copying axes.
                let missing = @relation.pivot_value_count(pivot) > 0 ||
                  @relation.pivot_fill(pivot) is Some(_)
                identity_charge(budget, 1)
                pivots.push({
                  step: index,
                  operation,
                  pivot,
                  unknown_provenance: missing,
                })
                unknown = unknown || missing
              }
              Group => {
                guard @relation.group(operation) is Some(group) else {
                  raise ForeignOwner
                }
                let mut missing = false
                for binding in 0..<@relation.binding_count(operation) {
                  identity_charge(budget, 1)
                  let expression = @relation.binding_expression_at(
                    operation, binding,
                  ).unwrap()
                  if publication_expression_unknown(expression, budget) {
                    missing = true
                  }
                }
                for call in 0..<@relation.aggregate_count(group) {
                  identity_charge(budget, 1)
                  let aggregate = @relation.aggregate_at(group, call).unwrap()
                  if @relation.aggregate_delimiter(aggregate) is Some(_) ||
                    @relation.aggregate_fraction(aggregate) is Some(_) ||
                    @relation.aggregate_item_limit(aggregate) is Some(_) ||
                    @relation.aggregate_byte_limit(aggregate) is Some(_) {
                    missing = true
                  }
                }
                identity_charge(budget, 1)
                groups.push({
                  step: index,
                  operation,
                  group,
                  unknown_provenance: missing,
                })
                unknown = unknown || missing
              }
              Derive => {
                let mut all_copies = true
                let mut missing = false
                for binding in 0..<@relation.binding_count(operation) {
                  identity_charge(budget, 1)
                  if @relation.binding_copy_at(operation, binding).unwrap().input
                    is None {
                    all_copies = false
                  }
                  let expression = @relation.binding_expression_at(
                    operation, binding,
                  ).unwrap()
                  if publication_expression_unknown(expression, budget) {
                    missing = true
                  }
                }
                if all_copies {
                  copies.push({ step: index, operation, })
                }
                unknown = unknown || missing
                derivations.push({
                  step: index,
                  operation,
                  unknown_provenance: missing,
                })
              }
              Take => {
                identity_charge(budget, 2)
                guard @relation.row_operation(operation)
                  is Some(@relation.Take(count~, offset~)) else {
                  raise ForeignOwner
                }
                unknown = true
                slices.push({ step: index, operation, count, offset, })
              }
              Filter | AssertRows =>
                for binding in 0..<@relation.binding_count(operation) {
                  identity_charge(budget, 1)
                  let expression = @relation.binding_expression_at(
                    operation, binding,
                  ).unwrap()
                  let missing = publication_expression_unknown(
                    expression, budget,
                  )
                  unknown = unknown || missing
                  predicates.push({
                    step: index,
                    expression,
                    unknown_provenance: missing,
                  })
                }
            }
            1
          }
          @pipeline.Nest(checked=operation, ..) => {
            identity_charge(budget, 1)
            let missing = @nest.item_guard(operation) is Some(_)
            nests.push({ step: index, operation, unknown_provenance: missing, })
            unknown = unknown || missing
            2
          }
          @pipeline.Traverse(selector~, checked=operation) => {
            identity_charge(budget, 1)
            let start = @graph.traverse_start(operation)
            let mut missing = !@graph.traverse_patterned(operation) ||
              @graph.selector_id_count(start) > 0 ||
              @graph.traverse_output_guard(operation) is Some(_)
            for hop in 0..<@graph.traverse_hop_count(operation) {
              identity_charge(budget, 1)
              let hop = @graph.traverse_hop_at(operation, hop).unwrap()
              if @graph.hop_type_count(hop).unwrap_or(0) > 0 {
                missing = true
              }
            }
            carrier_steps.push({
              step: index,
              operation: step.operation,
              unknown_provenance: missing,
            })
            unknown = unknown || missing
            if selector is Some(_) {
              2
            } else {
              1
            }
          }
          @pipeline.GraphMatch(operation) => {
            identity_charge(budget, 1)
            let mut missing = @graph.match_id_count(operation) > 0 ||
              @graph.match_type_count(operation).unwrap_or(0) > 0
            if @graph.match_predicate(operation) is Some(predicate) {
              if publication_expression_unknown(
                  @graph.predicate_expression(predicate),
                  budget,
                ) {
                missing = true
              }
            }
            carrier_steps.push({
              step: index,
              operation: step.operation,
              unknown_provenance: missing,
            })
            unknown = unknown || missing
            1
          }
          @pipeline.GraphBounds(_)
          | @pipeline.GraphDegree(_)
          | @pipeline.GraphComponents(_) => {
            identity_charge(budget, 1)
            carrier_steps.push({
              step: index,
              operation: step.operation,
              unknown_provenance: true,
            })
            unknown = true
            1
          }
          @pipeline.GraphEquality(..) => {
            identity_charge(budget, 1)
            carrier_steps.push({
              step: index,
              operation: step.operation,
              unknown_provenance: true,
            })
            unknown = true
            2
          }
          @pipeline.GraphNormalize(_) => {
            identity_charge(budget, 1)
            carrier_steps.push({
              step: index,
              operation: step.operation,
              unknown_provenance: false,
            })
            1
          }
          @pipeline.PropertyGraphConstruction(inputs~, ..) => {
            identity_charge(budget, 1)
            carrier_steps.push({
              step: index,
              operation: step.operation,
              unknown_provenance: false,
            })
            inputs.length()
          }
          @pipeline.Vector(operation) => {
            identity_charge(budget, 1)
            let missing = match @vector.operation(operation) {
              ToVectors | NormalizeVectors => false
              ScoreVectors => true
            }
            carrier_steps.push({
              step: index,
              operation: step.operation,
              unknown_provenance: missing,
            })
            unknown = unknown || missing
            1
          }
          @pipeline.Event(operation) => {
            identity_charge(budget, 1)
            let missing = match @event.options(operation) {
              ToEvents | Dedupe(_) => false
              Watermark(_, _) | Session(_) => true
            }
            carrier_steps.push({
              step: index,
              operation: step.operation,
              unknown_provenance: missing,
            })
            unknown = unknown || missing
            1
          }
          @pipeline.Sequence(operation) => {
            for pattern in 0..<@relation.sequence_pattern_count(operation) {
              identity_charge(budget, 1)
              ignore(
                publication_expression_unknown(
                  @relation.sequence_pattern_at(operation, pattern).unwrap().predicate,
                  budget,
                ),
              )
            }
            identity_charge(budget, 1)
            // The required within value already lacks a policy attestation.
            // Still account for every predicate, including nonmatching events'
            // selection contributions, instead of stopping at that first fact.
            carrier_steps.push({
              step: index,
              operation: step.operation,
              unknown_provenance: true,
            })
            unknown = true
            1
          }
          @pipeline.Window(_) => {
            identity_charge(budget, 1)
            carrier_steps.push({
              step: index,
              operation: step.operation,
              unknown_provenance: true,
            })
            unknown = true
            1
          }
          @pipeline.Pool(_) | @pipeline.Projection(_) => {
            identity_charge(budget, 1)
            carrier_steps.push({
              step: index,
              operation: step.operation,
              unknown_provenance: false,
            })
            1
          }
          @pipeline.IntervalJoin(checked=operation, ..) => {
            identity_charge(budget, 1)
            let missing = @join.interval_output_guard(operation) is Some(_)
            temporal_joins.push({
              step: index,
              operation: step.operation,
              unknown_provenance: missing,
            })
            unknown = unknown || missing
            2
          }
          @pipeline.Ranking(operation) => {
            identity_charge(budget, 1)
            carrier_steps.push({
              step: index,
              operation: step.operation,
              unknown_provenance: true,
            })
            // k and fusion controls have no implicit policy attestation.
            // Retain every weighted occurrence, including zero-weight inputs.
            unknown = true
            @vector.merged_ranking_input_count(operation)
          }
          @pipeline.TextRank(..) | @pipeline.Nearest(..) => {
            identity_charge(budget, 1)
            carrier_steps.push({
              step: index,
              operation: step.operation,
              unknown_provenance: true,
            })
            // k and authored scoring controls are not policy attestations.
            // Both corpus/candidate and query edges remain contributors.
            unknown = true
            2
          }
          @pipeline.AsOfJoin(..) => {
            identity_charge(budget, 1)
            temporal_joins.push({
              step: index,
              operation: step.operation,
              unknown_provenance: true,
            })
            // Tolerance is a literal or bound value, not a policy attestation.
            unknown = true
            2
          }
          @pipeline.Join(right~, checked~) => {
            if keyed_responses.get(index) is Some(response) {
              guard response.kind is KeyedResponse(binding) &&
                physical_equal(
                  @sourceviews.keyed_join_operation(binding.join),
                  checked,
                ) &&
                step.input == Some(@sourceviews.keyed_join_left(binding.join)) &&
                right is @pipeline.Input(input) else {
                raise ForeignOwner
              }
              let (name, _) = @pipeline.input_at(unit.pipeline, input).unwrap()
              if identity_compare(
                  name,
                  @sourceviews.declaration(response.subject.source).input_name,
                  budget,
                ) !=
                0 {
                raise ForeignOwner
              }
              retain_policy_source(response, source_ids, sources, budget)
              keyed_right = true
            }
            2
          }
          @pipeline.Append(..) | @pipeline.Set(..) | @pipeline.CrossJoin(..) =>
            2
        }
        guard @pipeline.input_occurrence_count(step) == expected else {
          raise ForeignOwner
        }
        for index_in in 0..<expected {
          identity_charge(budget, 1)
          let occurrence = @pipeline.input_occurrence_at(step, index_in).unwrap()
          edges.push({ step: index, occurrence, })
          // The right keyed response belongs to this join, not to every use of
          // its input declaration. The left edge remains a policy contributor
          // even when no left column survives the output projection.
          if !keyed_right || index_in != 1 {
            pending.push(occurrence.target)
          }
        }
      }
      @pipeline.Input(index) => {
        if visited_inputs.contains(index) {
          continue
        }
        visited_inputs[index] = true
        let (name, _) = @pipeline.input_at(unit.pipeline, index).unwrap()
        let mut found = false
        for check in unit.source_execution {
          identity_charge(budget, 1)
          let subject = check.subject
          if subject.stage == stage &&
            check.kind is CarrierResponse &&
            identity_compare(
              @sourceviews.declaration(subject.source).input_name,
              name,
              budget,
            ) ==
            0 {
            guard subject.direct_policy is Some(_) else { return None }
            retain_policy_source(check, source_ids, sources, budget)
            found = true
            break
          }
        }
        if found {
          continue
        }
        for interface in unit.interfaces {
          identity_charge(budget, 1)
          if identity_compare(interface.input_name, name, budget) != 0 {
            continue
          }
          guard @context.result_import_type_site(interface.row).requirement
            is @context.Result(_, producer, port) else {
            raise ForeignOwner
          }
          guard producers is Some(completed) else { return None }
          for prior in completed {
            identity_charge(budget, 1)
            if !physical_equal(prior.source, producer) {
              continue
            }
            guard physical_equal(
                @context.core_contract_identity(prior.contract_inventory),
                @context.core_contract_identity(unit.contract_inventory),
              ) &&
              prior.definition_cid == interface.producer_unit_definition_cid else {
              raise ForeignOwner
            }
            for output in prior.publications {
              identity_charge(budget, 1)
              let result = @context.publication_row_limit_result(
                output.selection,
              )
              if !physical_equal(
                  @publication.port_result(result.port),
                  @publication.port_result(@results.input_port(port)),
                ) {
                continue
              }
              guard output.source_policy is Some(parent) else { return None }
              imports.push({ input: index, publication: output, })
              unknown = unknown || parent.unknown_provenance
              for check in parent.sources {
                retain_policy_source(check, source_ids, sources, budget)
              }
              found = true
              break
            }
            if !found {
              return None
            }
            break
          }
          if !found {
            raise ForeignOwner
          }
          break
        }
        if !found {
          for i in 0..<@context.local_input_closure_count(unit.local_inputs) {
            identity_charge(budget, 1)
            let check = @context.local_input_closure_at(unit.local_inputs, i).unwrap()
            let subject = check.subject
            if subject.stage == stage &&
              subject.target == target &&
              physical_equal(subject.pipeline, unit.pipeline) {
              locals.push(check)
              found = true
              unknown = true
            }
          }
        }
        if !found {
          return None
        }
      }
    }
  }
  let occurrences : Array[SourcePolicyOccurrence] = []
  for source in sources {
    identity_charge(budget, 1)
    occurrences.push(
      match source.kind {
        KeyedResponse(_) => KeyedResponsePolicy(source)
        _ => DirectPolicy(source.subject.direct_policy.unwrap())
      },
    )
  }
  let effective = prepare_effective_policy(occurrences, unknown, budget)
  let writer = identity_writer(budget)
  emit_effective_policy(effective, writer) catch {
    e => raise Encoding(e)
  }
  let cid = identity_finish(budget, writer)
  {
    policy: if sources.length() == 1 {
      sources[0].subject.direct_policy
    } else {
      None
    },
    prerequisite: if sources.length() == 1 {
      Some(sources[0])
    } else {
      None
    },
    imported_publication: if imports.length() == 1 {
      Some(imports[0].publication)
    } else {
      None
    },
    effective,
    cid,
    target: original,
    unknown_provenance: effective.unknown_provenance,
    predicates,
    slices,
    sources,
    imports,
    edges,
    generators,
    locals,
    copies,
    derivations,
    groups,
    pivots,
    analytics,
    lags,
    unpivots,
    json_picks,
    unnests,
    top_ks,
    watermarks,
    nests,
    temporal_joins,
    carrier_steps,
    model_steps,
  }
  |> Some
}

///|
fn retain_policy_source(
  check : SourceExecution,
  seen : Map[String, Bool],
  sources : Array[SourceExecution],
  budget : IdentityBudget,
) -> Unit raise UnitBuildFailure {
  identity_charge(budget, 1)
  let key = check.subject.stage.to_string() +
    ":" +
    check.subject.input.to_string() +
    (match check.kind {
      KeyedResponse(binding) => ":join:" + binding.index.to_string()
      _ => ""
    })
  identity_charge(budget, key.length())
  if !seen.contains(key) {
    seen[key] = true
    sources.push(check)
  }
}

///|
pub fn publication_source_policy(
  value : PublicationExecution,
) -> PublicationSourcePolicy? {
  value.source_policy
}
