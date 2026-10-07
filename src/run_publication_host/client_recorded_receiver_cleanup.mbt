///|
/// Cleanup-only projection of the matched original recorded graph. This does
/// not expose an executable checked edge or refresh the recorded Run's Plan.
pub fn prepare_recorded_client_retained_receiver_cleanup_from_plan(
  recorded : ClientRecordedSourceCleanup,
  producer_record : @remote.DispatchRecord,
  producer_evidence : @remote.RemoteExecutionEvidence,
  producer_subject : @remote.RemoteManagedOutputSubject,
  producer_measurement : @remote.RemoteManagedOutputMeasurement,
  intent : @remote.RemoteRetainedInputIntent,
  result : @remote.RemoteRetainedInputResult,
  original_consumer : @remote.DispatchRequest,
  consumer_record : @remote.DispatchRecord,
  max_binding_bytes : Int,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Result[ClientRetainedInputCleanup, ClientRetainedTaskInputIssue] {
  let edge = match
    resolve_client_retained_input_edge(
      recorded.prepared,
      recorded.run_definition_cid,
      1,
      0,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidBinding)
  }
  prepare_client_retained_receiver_cleanup_from_plan(
    edge, producer_record, producer_evidence, producer_subject, producer_measurement,
    intent, result, original_consumer, consumer_record, max_binding_bytes, max_chunks,
    max_manifest_bytes, max_referenced_bytes,
  )
}
