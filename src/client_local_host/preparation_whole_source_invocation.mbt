///|
/// Closed publication selection from the same adopted Run. Its original
/// Request is already retained by that owner; no new request or clock is read.
pub fn installed_managed_publication_source_kind(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
) -> Result[String, ClientInstalledManagedRunIssue] {
  installed_managed_source_input_kind(owner, prepared, owner.request)
}

///|
fn whole_source_publication_capture_matches(
  owner : ClientInstalledManagedRun,
  plan : ClientInstalledManagedCapturePlan,
  capture : @row_source_host.RowSourceCapture,
  index? : Int = 0,
) -> Bool {
  guard owner.captured_preparation is Some(original) &&
    physical_equal(original, plan) &&
    owner.reads.length() == plan.whole_sources.length() &&
    plan.whole_sources.get(index) is Some(capacity) &&
    owner.reads.get(index) is Some(Some(read)) &&
    read.ledger is Some(ledger) &&
    owner.ledger is Some(original_ledger) &&
    physical_equal(ledger, original_ledger) &&
    read.whole_input is Some(selected) &&
    physical_equal(selected, capacity) &&
    read.run is Some(run) else {
    return false
  }
  @row_source_host.check_row_input_capture_run(capture, run) is Ok(_)
}

///|
/// Bind the actual RowRun capture and typed Source observations to the same
/// adopted publication owner. Equal wires cannot replace its Run occurrence.
pub fn issue_program_whole_source_publication_invocation(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  capture : @row_source_host.RowSourceCapture,
  identity : @query.CapturedSourceRelationIdentity,
  source : @publication.RunEvidenceValue,
  input : @publication.RunEvidenceValue,
  authority_scope_cid : String,
  data_policy_cid : String,
  capture_started_at : String,
  capture_completed_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  ClientClosedValuesPreparationIssue,
] {
  issue_program_whole_sources_publication_invocation(
    owner,
    prepared,
    compiled,
    definition,
    [capture],
    [identity],
    [source],
    [input],
    authority_scope_cid,
    data_policy_cid,
    capture_started_at,
    capture_completed_at,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
pub fn issue_program_whole_sources_publication_invocation(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  captures : Array[@row_source_host.RowSourceCapture],
  identities : Array[@query.CapturedSourceRelationIdentity],
  sources : Array[@publication.RunEvidenceValue],
  inputs : Array[@publication.RunEvidenceValue],
  authority_scope_cid : String,
  data_policy_cid : String,
  capture_started_at : String,
  capture_completed_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  ClientClosedValuesPreparationIssue,
] {
  guard owner.captured_preparation is Some(plan) &&
    physical_equal(plan.prepared, prepared) &&
    physical_equal(plan.request, owner.request) &&
    !plan.whole_sources.is_empty() &&
    captures.length() == plan.whole_sources.length() &&
    identities.length() == captures.length() &&
    sources.length() == captures.length() &&
    inputs.length() == captures.length() &&
    captures
    .mapi((index, capture) => {
      whole_source_publication_capture_matches(owner, plan, capture, index~)
    })
    .all(value => value) else {
    return Err(ForeignOriginal)
  }
  match
    begin_program_publication_invocation(owner, prepared, compiled, definition) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let captured = []
  for index, capture in captures {
    let source = match @row_source_host.row_capture_source(capture) {
      Err(_) => return Err(ForeignOriginal)
      Ok(value) => value
    }
    if !whole_source_publication_capture_matches(owner, plan, capture, index~) {
      return Err(ForeignOriginal)
    }
    captured.push(source)
  }
  let (evidence, invocation) = match
    @publication_host.issue_client_compiled_whole_sources_invocation(
      compiled,
      definition,
      captured,
      identities,
      plan.whole_sources.map(value => value.original),
      sources,
      inputs,
      authority_scope_cid,
      data_policy_cid,
      capture_started_at,
      capture_completed_at,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Err(issue) => return Err(PublicationInvocation(issue))
    Ok(value) => value
  }
  guard managed_run_publication_body(owner, prepared) is Ok(_) &&
    captures
    .mapi((index, capture) => {
      whole_source_publication_capture_matches(owner, plan, capture, index~)
    })
    .all(value => value) &&
    captured.all(@query.captured_source_available) else {
    return Err(ForeignOriginal)
  }
  owner.publication_definition = Some(definition)
  owner.publication_invocation = Some(invocation)
  Ok((evidence, invocation))
}
