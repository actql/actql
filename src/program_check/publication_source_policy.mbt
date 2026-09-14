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
  if unit.source_execution.is_empty() {
    return None
  }
  let original = @publication.target(@publication.port_result(publication.port))
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
        let expected = match step.operation {
          @pipeline.Values(_) => {
            identity_charge(budget, 1)
            generators.push({ step: index, operation: step.operation, })
            unknown = true
            0
          }
          @pipeline.Unary(operation) => {
            match @relation.operation(operation) {
              Select | Rename | Drop | Sort | Distinct | DedupeRows => ()
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
              _ => return None
            }
            1
          }
          @pipeline.Append(..)
          | @pipeline.Set(..)
          | @pipeline.Join(..)
          | @pipeline.CrossJoin(..) => 2
          _ => return None
        }
        guard @pipeline.input_occurrence_count(step) == expected else {
          raise ForeignOwner
        }
        for index_in in 0..<expected {
          identity_charge(budget, 1)
          let occurrence = @pipeline.input_occurrence_at(step, index_in).unwrap()
          edges.push({ step: index, occurrence, })
          pending.push(occurrence.target)
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
          if subject.stage == publication.stage &&
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
            if subject.stage == publication.stage &&
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
  let occurrences : Array[DirectSourcePolicy] = []
  for source in sources {
    identity_charge(budget, 1)
    occurrences.push(source.subject.direct_policy.unwrap())
  }
  let effective = prepare_effective_policy(occurrences, unknown, budget)
  let writer = identity_writer(budget)
  emit_effective_policy(effective, writer) catch {
    e => raise Encoding(e)
  }
  let cid = identity_finish(budget, writer)
  {
    policy: if sources.length() == 1 {
      Some(occurrences[0])
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
    check.subject.input.to_string()
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
