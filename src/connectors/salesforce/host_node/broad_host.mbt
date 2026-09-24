///|
#export_name("salesforceBroadHostOpen")
pub fn salesforce_broad_host_open(
  configuration : @salesforce_host.SalesforceBroadHostConfiguration,
  nonce : String,
  verify : (@salesforce_host.SalesforceBroadAttempt) -> Bool,
) -> @salesforce_host.SalesforceBroadHostRun raise SalesforceCatalogBridgeIssue {
  match
    @salesforce_host.start_salesforce_broad_host(configuration, nonce, verify) {
    Ok(run) => run
    Err(issue) => raise BroadHost(issue)
  }
}

///|
#export_name("salesforceBroadHostAttempt")
pub fn salesforce_broad_host_attempt(
  run : @salesforce_host.SalesforceBroadHostRun,
) -> @salesforce_host.SalesforceBroadAttempt {
  @salesforce_host.salesforce_broad_host_attempt(run)
}

///|
#export_name("salesforceBroadHostComplete")
pub fn salesforce_broad_host_complete(
  run : @salesforce_host.SalesforceBroadHostRun,
) -> @salesforce_host.SalesforceBroadObservation raise SalesforceCatalogBridgeIssue {
  match @salesforce_host.complete_salesforce_broad_host(run) {
    Ok(value) => value
    Err(issue) => raise BroadHost(issue)
  }
}

///|
#export_name("salesforceBroadHostSource")
pub fn salesforce_broad_host_source(
  run : @salesforce_host.SalesforceBroadHostRun,
  observation : @salesforce_host.SalesforceBroadObservation,
) -> @query.CapturedInputSource raise SalesforceCatalogBridgeIssue {
  match @salesforce_host.salesforce_broad_host_source(run, observation) {
    Ok(value) => value
    Err(issue) => raise BroadHost(issue)
  }
}

///|
#export_name("salesforceBroadHostBind")
pub fn salesforce_broad_host_bind(
  run : @salesforce_host.SalesforceBroadHostRun,
  observation : @salesforce_host.SalesforceBroadObservation,
  receiver : @lower.BoundPrepared,
  input_index : Int,
) -> @execution.BoundProducerInput raise SalesforceCatalogBridgeIssue {
  match
    @salesforce_host.bind_salesforce_broad_host_input(
      run, observation, receiver, input_index,
    ) {
    Ok(value) => value
    Err(issue) => raise BroadHost(issue)
  }
}

///|
#export_name("salesforceBroadHostDocument")
pub fn salesforce_broad_host_document(
  observation : @salesforce_host.SalesforceBroadObservation,
) -> String {
  @encode.document_text(
    @salesforce_host.salesforce_broad_observation_document(observation),
  )
}

///|
#export_name("salesforceBroadHostAbort")
pub fn salesforce_broad_host_abort(
  run : @salesforce_host.SalesforceBroadHostRun,
) -> Unit {
  @salesforce_host.abort_salesforce_broad_host(run)
}

///|
#export_name("salesforceBroadHostClose")
pub fn salesforce_broad_host_close(
  run : @salesforce_host.SalesforceBroadHostRun,
) -> Unit {
  @salesforce_host.close_salesforce_broad_host(run)
}
