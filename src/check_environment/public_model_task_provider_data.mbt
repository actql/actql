///|
/// Borrow the two original checked schema identities. No contract re-emission,
/// parsing, hashing or Provider registration is performed by this projection.
pub fn normalized_public_model_task_schema_cids(
  value : NormalizedPublicModelTask,
) -> (String, String) {
  (value.declaration.input.cid, value.declaration.output.cid)
}

///|
/// Bounded DATA from the same normalized declaration. This neither registers a
/// Provider nor admits a new Task, Environment, permission or execution owner.
/// The existing prompt emitter preserves instruction text exactly.
pub fn normalized_public_model_task_provider_data(
  value : NormalizedPublicModelTask,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_work : Int,
) -> Result[(String, String, String), ModelTaskIssue] {
  let source = Some(value.declaration.original)
  if max_bytes < 0 || max_nodes < 0 || max_depth < 0 || max_work < 0 {
    return Err({ kind: InvalidLimits, source, })
  }
  // Pre-admit the complete declared encoder traversal before construction,
  // using the same conservative work law as public Task material emission.
  if max_bytes.to_int64() + max_nodes.to_int64() > max_work.to_int64() {
    return Err({ kind: WorkLimit, source, })
  }
  try {
    let writer = @encode.writer(max_bytes, max_nodes, max_depth)
    emit_public_task_prompt_payload(value.declaration, writer)
    Ok(
      (
        value.declaration.output.cid,
        value.resolved.model,
        @encode.finish(writer),
      ),
    )
  } catch {
    _ => Err({ kind: BodyLimit, source, })
  }
}
