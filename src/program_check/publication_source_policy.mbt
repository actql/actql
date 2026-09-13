///|
pub struct PublicationSourcePolicy {
  policy : DirectSourcePolicy
  cid : String
  prerequisite : SourceExecution
  target : @pipeline.Target
}

///|
// Follow checked edges, never the Program's entire input set. This initial
// transfer handles operations that neither introduce values nor mix sources.
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
  while true {
    identity_charge(budget, 1)
    match target {
      @pipeline.Step(index) => {
        let step = @pipeline.step_at(unit.pipeline, index).unwrap()
        guard step.operation is @pipeline.Unary(operation) else { return None }
        match @relation.operation(operation) {
          Select | Rename | Drop | Sort | Distinct | DedupeRows => ()
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
            emit_direct_source_policy(policy, writer) catch {
              e => raise Encoding(e)
            }
            let cid = identity_finish(budget, writer)
            return Some({ policy, cid, prerequisite: check, target: original, })
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
