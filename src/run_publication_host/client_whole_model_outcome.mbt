///|
/// A recording right issued only by the successful original Model Read
/// handoff. It belongs to the original execution and seals its outcome once.
struct ClientWholeModelOutcomeRecorder {
  scope : ClientInferCallScope
  consumer : ClientModelReadConsumer
  binding : @execution.InferOutcomeBinding
}

///|
pub fn complete_original_whole_model_outcome(
  value : ClientWholeModelOutcomeRecorder,
  port : @execution.InferOutcomePort,
  task_workspace? : @strategy.TaskOutputWorkspace? = None,
) -> @execution.CompletedOutput? {
  let scope = value.scope
  let selected = scope.plan.occurrence
  guard scope.custody is ArmedWholeOutcome else { return None }
  scope.custody = CompletingWholeOutcome
  defer (if scope.custody is CompletingWholeOutcome {
    scope.custody = ArmedWholeOutcome
  })
  let output_workspace = match
    (@execution.infer_outcome_workspace_original(port), task_workspace) {
    (None, None) => None
    (Some(original), Some(workspace)) => {
      guard @strategy.task_output_workspace_resource(workspace, original)
        is Some(resource) else {
        return None
      }
      Some(resource)
    }
    _ => return None
  }
  guard @execution.complete_bound_infer_outcome_port(port, value.binding)
    is Ok(output) &&
    @execution.completed_output_matches_port(
      output,
      selected.preparation,
      @pipeline.Step(selected.step),
    ) &&
    client_infer_call_scope_matches(scope, scope.owner, scope.input) &&
    @resources.funded_read_consumer_handed_off_origin(
      value.consumer.consumer,
      output_workspace~,
    )
    is Some(origin) &&
    physical_equal(origin.plan, scope.plan) &&
    client_infer_result_input_inventory_current(scope) &&
    scope.custody is CompletingWholeOutcome else {
    return None
  }
  scope.custody = WholeOutcome(
    @execution.completed_output_original_occurrence(output),
  )
  Some(output)
}

///|
fn client_whole_model_outcome_matches(
  scope : ClientInferCallScope,
  receipt : @execution.CompletedRelationExportReceipt,
) -> Bool {
  guard scope.custody is WholeOutcome(occurrence) &&
    @execution.completed_relation_export_is_unprojected(receipt) &&
    @execution.completed_relation_export_original_source(receipt)
    is Some(original) else {
    return false
  }
  @execution.completed_output_occurrence_matches_original(occurrence, original)
}

///|
fn client_whole_model_observation_matches(
  call : ClientInferCallScope,
  model : @publication.CapturedEffectDependencyBody,
  outcome : @execution.CompletedRelationExportReceipt,
) -> Bool {
  client_whole_model_outcome_matches(call, outcome) &&
  @publication.local_model_observation_matches_input(
    model,
    call.unit_definition_cid,
    call.source_ordinal,
    call.artifact,
  ) &&
  @publication.local_model_observation_matches_outcome(
    model,
    @execution.logical_relation_cid(
      @execution.completed_relation_export_identity(outcome),
    ),
    @execution.relation_schema_cid(
      @execution.completed_relation_export_schema_identity(outcome),
    ),
  )
}

///|
priv enum ClientWholeModelTerminal {
  Unclaimed
  Pending
  Recording
  Recorded(@execution.CompletedOutputOccurrence)
  Retired
}

///|
/// The live Model host claims this once, before entering Model execution.
/// The Model outcome receiver owns a different capability.
struct ClientWholeModelTerminalRecorder {
  scope : ClientInferCallScope
  step : Int
}

///|
pub fn claim_original_whole_model_terminal(
  scope : ClientInferCallScope,
) -> Result[ClientWholeModelTerminalRecorder?, ClientInferCallScopeIssue] {
  match scope.custody {
    LiveInput | SavedInput(_) => return Ok(None)
    PendingWholeOutcome => ()
    _ => return Err(ForeignInput)
  }
  guard scope.whole_terminal is Unclaimed &&
    client_infer_occurrence_output_step(scope.plan.occurrence) is Some(step) &&
    step >= scope.source_ordinal else {
    return Err(ForeignInput)
  }
  scope.whole_terminal = Pending
  Ok(Some({ scope, step, }))
}

///|
/// Commit only the result selected by the original host's terminal handoff.
/// The host retains the actual suffix through the same execution. A direct
/// Model terminal is the same completion as the registered unfiltered outcome.
pub fn record_original_whole_model_terminal(
  recorder : ClientWholeModelTerminalRecorder,
  outcome : @execution.CompletedOutput,
  completed : @execution.CompletedOutput,
  current : () -> Bool,
) -> Bool {
  let scope = recorder.scope
  guard scope.whole_terminal is Pending &&
    scope.custody is WholeOutcome(original) else {
    return false
  }
  scope.whole_terminal = Recording
  defer (if scope.whole_terminal is Recording {
    scope.whole_terminal = Pending
  })
  guard @execution.completed_output_occurrence_matches_original(
      original, outcome,
    ) &&
    @execution.completed_output_matches_port(
      completed,
      scope.plan.occurrence.preparation,
      @pipeline.Step(recorder.step),
    ) &&
    (
      recorder.step != scope.source_ordinal ||
      @execution.completed_output_occurrence_matches_original(
        original, completed,
      )
    ) &&
    client_infer_call_scope_matches(scope, scope.owner, scope.input) &&
    @execution.completed_output_available(outcome) &&
    @execution.completed_output_available(completed) &&
    current() &&
    client_infer_result_input_inventory_current(scope) &&
    scope.whole_terminal is Recording else {
    return false
  }
  scope.whole_terminal = Recorded(
    @execution.completed_output_original_occurrence(completed),
  )
  true
}

///|
pub fn retire_original_whole_model_terminal(
  recorder : ClientWholeModelTerminalRecorder,
) -> Unit {
  recorder.scope.whole_terminal = Retired
}

///|
fn client_whole_model_terminal_matches(
  scope : ClientInferCallScope,
  receipt : @execution.CompletedRelationExportReceipt,
) -> Bool {
  guard scope.whole_terminal is Recorded(_) &&
    @execution.completed_relation_export_original_source(receipt)
    is Some(output) else {
    return false
  }
  client_whole_model_terminal_output_matches(scope, output)
}

///|
/// Match an already sealed Whole Model terminal to the exact completed output.
/// This consumes no Work and issues no new output, Read or provider authority.
pub fn client_whole_model_terminal_output_matches(
  scope : ClientInferCallScope,
  output : @execution.CompletedOutput,
) -> Bool {
  guard scope.whole_terminal is Recorded(terminal) &&
    @execution.completed_output_occurrence_matches_original(terminal, output) &&
    scope.whole_terminal is Recorded(current) else {
    return false
  }
  physical_equal(terminal, current)
}
