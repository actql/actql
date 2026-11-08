///|
priv enum LocalNativeMockSourceIdentityIssue {
  Read(@run_host.ClientModelReadPreparationIssue)
}

///|
fn[T] Result::native_source_identity(
  self : Result[T, LocalNativeMockSourceIdentityIssue],
  original : LocalCommandPreparationOriginal,
) -> T raise ClientStop {
  match self {
    Ok(value) => value
    Err(issue) => {
      original.retain_primary(CommandBusinessSourceIdentity(issue))
      stop("LocalOriginalModelSourceIdentityUnavailable")
    }
  }
}
