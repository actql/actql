///|
/// Borrow the exact finalized input through the existing bounded Relation
/// exporter. This does not consume the call-scope receipt, authorize a send,
/// or establish durable custody. The Host must retain and verify Store bytes
/// before it registers an approval inventory or releases this execution.
pub fn prepare_model_approval_input_export(
  active : Execution,
  max_batch_bytes : Int,
) -> Result[@relation.CompletedOutputExport, Issue] {
  guard !active.cancelled &&
    !active.reclaimed &&
    prepared_model_call_set(active) is Some(_) &&
    active.prepared is Some(prepared) &&
    active.call_scope is Some(scope) &&
    @input.client_infer_completed_input(active.input) is Some(output) &&
    @publication_host.client_infer_call_scope_matches(scope, prepared, output) else {
    return Err(InvalidAdvance)
  }
  let limits = active.limits.identity
  @relation.prepare_completed_relation_export(
    output,
    limits.rows,
    active.limits.input.rows.output_values,
    limits.wire,
    limits.logical_wire,
    limits.schema,
    max_batch_bytes,
  ).map_err(issue => IdentityExport(issue))
}
