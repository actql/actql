///|
/// The original Source dispatch is retained by its admitted acquisition Owner.
/// This custody token grants neither execution nor current authorization.
struct ClientEffectProducerArtifact {
  dispatch : @remote.DispatchRequest
  artifact : ClientEffectLocalResultArtifact
}

///|
/// Preserve the producer attempt from the dispatch bound before Source I/O.
/// Equal Run identities or Result bytes cannot substitute another capture.
pub fn bind_client_effect_producer_artifact(
  bound : PreparedClientEffectRun,
  captured : @strategy.CapturedEffectRunDAG,
  artifact : ClientEffectLocalResultArtifact,
) -> Result[ClientEffectProducerArtifact, ClientEffectTransferredArtifactIssue] {
  guard bound.source_dispatch is Some(dispatch) else {
    return Err(ForeignInput)
  }
  if !@strategy.captured_effect_run_matches_checked(captured, bound.checked) {
    return Err(ForeignInput)
  }
  guard artifact.custody is AcquiredUnit(inputs) else {
    return Err(ForeignArtifact)
  }
  if !@strategy.captured_effect_local_unit_inputs_match_run(inputs, captured) ||
    !client_effect_local_artifact_matches_computation(
      artifact,
      bound.computation,
    ) {
    return Err(Unavailable)
  }
  if client_effect_local_artifact_run_definition_cid(artifact) !=
    Some(@remote.dispatch_request_task_scope(dispatch).0) {
    return Err(ForeignRun)
  }
  Ok({ dispatch, artifact, })
}
