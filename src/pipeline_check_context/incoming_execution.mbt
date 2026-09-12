///|
pub(all) enum IncomingExecutionKind {
  StageSuccess(IncomingMilestone)
  ResultAvailable
} derive(Eq, Debug)

///|
pub(all) enum IncomingExecutionPhase {
  BeforeStageActivation
} derive(Eq, Debug)

///|
/// The barrier does not turn failure or uncertainty into a partial success.
pub(all) enum IncomingExecutionOutcome {
  AwaitPredecessor
  AwaitReconciliation
  PreventDownstreamActivation
} derive(Eq, Debug)

///|
/// An obligation on the exact consumer and producer, not an observed milestone,
/// admitted Result value, incoming-interface CID or permission to activate.
pub struct IncomingExecutionCheck {
  site : IncomingSite
  kind : IncomingExecutionKind
}

///|
pub enum IncomingExecutionState {
  Connected(IncomingExecutionCheck)
  ReceiptUnresolved(IncomingSite)
  SuccessContractsUnresolved(IncomingSite)
}

///|
fn incoming_effects_present(body : @decode.Cursor) -> Bool {
  // Stage grammar bounds this field scan independently of Effect count. Never
  // copy an Effect-name array or inspect unadmitted Effect contracts here.
  for i in 0..<@decode.object_length(body).unwrap() {
    let (name, value) = @decode.field_at(body, i).unwrap()
    if name == "effects" {
      return @decode.object_length(value) != Some(0)
    }
  }
  false
}

///|
/// Receipt requirements remain statically unresolved until their Effect and
/// completion contracts are admitted. None denotes only an absent index.
pub fn incoming_execution_at(
  v : ProgramIncomingLinks,
  index : Int,
) -> IncomingExecutionState? {
  guard v.incoming.entries.get(index) is Some(site) else { return None }
  match site.requirement {
    Success(milestone, producer) => {
      let at = @program_refs.stage_semantics_index(
        @program_refs.stage_definition_semantics(producer.definition),
      )
      let stage = @stages.stage_at(
        @stage_results.wiring_source(v.incoming.wiring),
        at,
      ).unwrap()
      if incoming_effects_present(@syntax.stage_body(stage)) {
        Some(SuccessContractsUnresolved(site))
      } else {
        Some(Connected({ site, kind: StageSuccess(milestone), }))
      }
    }
    Result(_, _, _) => Some(Connected({ site, kind: ResultAvailable, }))
    Receipt(_, _, _) => Some(ReceiptUnresolved(site))
  }
}

///|
pub fn incoming_execution_phase(
  v : IncomingExecutionCheck,
) -> IncomingExecutionPhase {
  match v.kind {
    StageSuccess(_) | ResultAvailable => BeforeStageActivation
  }
}

///|
/// A missing observation waits; it is not a missing caller Parameter binding.
pub fn incoming_execution_missing(
  v : IncomingExecutionCheck,
) -> IncomingExecutionOutcome {
  match v.kind {
    StageSuccess(_) | ResultAvailable => AwaitPredecessor
  }
}

///|
pub fn incoming_execution_unknown(
  v : IncomingExecutionCheck,
) -> IncomingExecutionOutcome {
  match v.kind {
    StageSuccess(_) | ResultAvailable => AwaitReconciliation
  }
}

///|
/// Failure, partial application and cancellation cannot activate the consumer.
pub fn incoming_execution_failure(
  v : IncomingExecutionCheck,
) -> IncomingExecutionOutcome {
  match v.kind {
    StageSuccess(_) | ResultAvailable => PreventDownstreamActivation
  }
}
