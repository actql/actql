///|
// Immutable catalogue DATA from the existing installed contract holder. Some
// with ordered=None is an explicit absence, never a request to parse a fallback.
// This carries no Run, Account, current callback or physical Resource grant.
priv struct ClientCompilerContracts {
  ordered : @execution.RegisteredOrderedContract?
}

///|
/// Bind the original installed compiler contract before Task emission starts.
/// Repeated forwarding accepts only that same original. A fresh standalone
/// compiler remains responsible for its own finite contract admission.
pub fn bind_prepared_client_compiler_contracts(
  value : PreparedClientProgram,
  ordered : @execution.RegisteredOrderedContract?,
) -> Result[Unit, ClientTaskPipelineIssue] {
  if value.compiler_contracts is Some(original) {
    match (original.ordered, ordered) {
      (None, None) => Ok(())
      (Some(first), Some(next)) if physical_equal(first, next) => Ok(())
      _ => Err(Encoding)
    }
  } else if !value.task_pipeline_inputs.is_empty() {
    // An earlier emission may already retain its own contract/params. Do not
    // relabel or upgrade that unbound material after its construction.
    Err(Encoding)
  } else {
    value.compiler_contracts = Some({ ordered, })
    Ok(())
  }
}
