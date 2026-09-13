///|
pub struct PublicationSourcePolicy {
  // Acquisition provenance before predicate contributions, not the final policy.
  policy : DirectSourcePolicy
  cid : String
  prerequisite : SourceExecution
  target : @pipeline.Target
  unknown_provenance : Bool
  priv predicates : Array[PublicationPolicyPredicate]
  priv slices : Array[PublicationPolicySlice]
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
  if value.unknown_provenance {
    @environment.Unknown
  } else {
    value.policy.classification
  }
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
  emit_source_policy(value.policy, value.unknown_provenance, writer)
}

///|
// Follow checked edges, never the Program's entire input set. This initial
// transfer preserves a single source and retains predicate contributions.
fn prepare_publication_source_policy(
  unit : BuiltUnit,
  publication : @context.PublicationResolution,
  budget : IdentityBudget,
) -> PublicationSourcePolicy? raise UnitBuildFailure {
  if unit.source_execution.is_empty() {
    return None
  }
  let original = @publication.target(@publication.port_result(publication.port))
  let mut target = original
  let predicates : Array[PublicationPolicyPredicate] = []
  let slices : Array[PublicationPolicySlice] = []
  let mut unknown = false
  while true {
    identity_charge(budget, 1)
    match target {
      @pipeline.Step(index) => {
        let step = @pipeline.step_at(unit.pipeline, index).unwrap()
        guard step.operation is @pipeline.Unary(operation) else { return None }
        match @relation.operation(operation) {
          Select | Rename | Drop | Sort | Distinct | DedupeRows => ()
          Take => {
            identity_charge(budget, 2)
            guard @relation.row_operation(operation)
              is Some(@relation.Take(count~, offset~)) else {
              raise ForeignOwner
            }
            // Count admission proves its numeric domain, not a classification.
            // Keep the exact checked operation and both selection controls;
            // order and bound resolution remain owned by the existing closure.
            unknown = true
            slices.push({ step: index, operation, count, offset, })
          }
          Filter =>
            for binding in 0..<@relation.binding_count(operation) {
              identity_charge(budget, 1)
              let expression = @relation.binding_expression_at(
                operation, binding,
              ).unwrap()
              let mut predicate_unknown = false
              for node in 0..<@typing.node_count(expression) {
                identity_charge(budget, 1)
                // Field leaves are owned by this single input. Other value
                // leaves carry no authoritative policy attestation; retain
                // every occurrence through the exact checked expression.
                if @typing.child_count(expression, node) == Some(0) {
                  match @typing.node_form(expression, node).unwrap() {
                    Expression("field" | "join_field", _) => ()
                    _ => predicate_unknown = true
                  }
                }
              }
              unknown = unknown || predicate_unknown
              predicates.push({
                step: index,
                expression,
                unknown_provenance: predicate_unknown,
              })
            }
          _ => return None
        }
        guard @pipeline.input_occurrence_count(step) == 1 else {
          raise ForeignOwner
        }
        target = @pipeline.input_occurrence_at(step, 0).unwrap().target
      }
      @pipeline.Input(index) => {
        let (name, _) = @pipeline.input_at(unit.pipeline, index).unwrap()
        for check in unit.source_execution {
          identity_charge(budget, 1)
          let subject = check.subject
          if subject.stage != publication.stage ||
            @sourceviews.declaration(subject.source).input_name != name {
            continue
          }
          if check.kind is CarrierResponse {
            guard subject.direct_policy is Some(policy) else { return None }
            let writer = identity_writer(budget)
            let unknown_provenance = unknown || policy.unknown_provenance
            emit_source_policy(policy, unknown_provenance, writer) catch {
              e => raise Encoding(e)
            }
            let cid = identity_finish(budget, writer)
            return Some({
              policy,
              cid,
              prerequisite: check,
              target: original,
              unknown_provenance,
              predicates,
              slices,
            })
          }
        }
        // Local/imported provenance in a SourceView-containing Program still
        // needs explicit composition; do not substitute another source's policy.
        return None
      }
    }
  } nobreak {
    raise ForeignOwner
  }
}

///|
pub fn publication_source_policy(
  value : PublicationExecution,
) -> PublicationSourcePolicy? {
  value.source_policy
}
