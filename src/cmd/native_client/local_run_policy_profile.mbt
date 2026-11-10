///|
// This finite product profile uses the actual explicit selection; no directory
// discovery, default profile fabrication or replacement of adopted originals.
fn local_run_policy_binding(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  business? : LocalCommandBusinessPreparation? = None,
) -> @local_host.NativeLocalRunPolicyBinding? raise ClientStop {
  if business is Some(original) {
    guard settings.run_policy_profile_file is Some(profile) &&
      settings.read_file is Some(read) &&
      settings.run_file is Some(run) else {
      stop("LocalRunPolicyOriginalUnavailable")
    }
    return Some(
      local_business_policy_result(
        original,
        original.capture.bind_run_policy_profile_in_original_read(
          settings.principal,
          settings.connection,
          profile,
          read,
          run,
        ),
      ).unwrap_or_else(() => stop("LocalRunPolicyOriginalUnavailable")),
    )
  }
  match settings.run_policy_profile_file {
    None =>
      match (settings.read_file, settings.run_file) {
        (Some(read), Some(run)) =>
          host
          .bind_upgraded_run_policy(
            crypto,
            settings.principal,
            settings.connection,
            read,
            run,
          )
          .unwrap_or_else(() => stop("LocalRunPolicyOriginalUnavailable"))
        _ => None
      }
    Some(profile) =>
      Some(
        host
        .bind_run_policy_profile_for_read(
          crypto,
          settings.principal,
          settings.connection,
          profile,
          settings.read_file.unwrap_or_else(() => {
            stop("LocalReadPolicyOriginalNotSelected")
          }),
          settings.run_file.unwrap_or_else(() => {
            stop("LocalRunOriginalNotSelected")
          }),
        )
        .unwrap_or_else(() => stop("LocalRunPolicyOriginalUnavailable")),
      )
  }
}

///|
// Preserve a combined actual Read/transaction failure on the same command
// carrier. A lost COMMIT reply cannot become a replacement Policy or Run.
fn[T] local_business_policy_result(
  original : LocalCommandBusinessPreparation,
  result : Result[T, @local_host.NativeLocalAdoptionIssue],
) -> Result[T, @local_host.NativeClientRunJournalIssue] raise ClientStop {
  match result {
    Ok(value) => Ok(value)
    Err(@local_host.Journal(issue)) => {
      local_report_submission_failure(@local_host.Journal(issue))
      Err(issue)
    }
    Err(issue) => {
      local_report_submission_failure(issue)
      original.original.retain_primary(CommandAdoption(issue))
      match issue {
        @local_host.InstallationReadTransactionFailure(_, TransactionUnknown) =>
          Err(@local_host.TransactionUnknown)
        _ => stop("LocalRunPolicyOriginalUnavailable")
      }
    }
  }
}
