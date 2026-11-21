///|
/// Retain the selected complete-input originals only after this SAME Request
/// backs their constructor and Native locator/transport overlap. This entry
/// never selects Query fallback, starts a physical read or issues a Run. The
/// caller must use these exact originals in the existing Whole Source Plan.
pub fn[I] reserve_request_whole_source_construction(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
) -> Result[
  (
    @publication_host.ClientDirectAcquisitionOccurrences,
    Array[@sourceviews.SourceAcquisition],
  ),
  ClientRequestProgramPlanIssue,
] {
  preparation_module_call(
    () => {
      let (direct, sources) = match
        reserve_request_whole_source_routes(owner, input, request) {
        Err(issue) => return Err(issue)
        Ok(value) => value
      }
      match
        reserve_request_selected_whole_source_inputs(owner, input, sources) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      Ok((direct, sources))
    },
    () => if owner.phase == Selecting { owner.phase = ProgramBodyFailed },
  )
}

///|
fn[I] reserve_request_selected_whole_source_inputs(
  owner : ClientRequestPreparation[I],
  input : I,
  sources : Array[@sourceviews.SourceAcquisition],
) -> Result[Unit, ClientRequestProgramPlanIssue] {
  guard owner.phase == Selecting && owner.compiled_program is Some(prepared) else {
    return Err(Preparation(ForeignOriginal))
  }
  let mut bytes = 0L
  for source in sources {
    guard request_whole_source_input_construction_bytes(source)
      is Some(input_bytes) &&
      @execution.checked_preparation_add_product(bytes, input_bytes, 1L)
      is Some(next) else {
      return Err(Preparation(Policy))
    }
    bytes = next
  }
  match
    reserve_request_domain_graph_construction(owner, input, prepared, bytes) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // Keep the successful extent after the checked grow. Earlier construction
  // backing and pending physical cleanup remain with the same parent.
  owner.program_domain_quote = None
  owner.phase = ProgramPlanReserved
  Ok(())
}

///|
/// The checked construction choice for this Native file Request. The same
/// original occurrence inventory reaches the selected constructor.
pub enum ClientRequestNativeFileSourceInputs {
  WholeSourceInputs(
    @publication_host.ClientDirectAcquisitionOccurrences,
    Array[@sourceviews.SourceAcquisition]
  )
  QuerySourceInputs(
    @planning.QueryEvidenceContracts,
    @publication_host.ClientDirectAcquisitionOccurrences
  )
  MissingQueryContracts
}

///|
pub enum ClientRequestNativeFileSourceIssue {
  NativeFileSourceSelection(ClientRequestProgramPlanIssue)
  NativeFileWholeConstruction(ClientRequestProgramPlanIssue)
  NativeFileQueryContracts(ClientRequestProgramPlanIssue)
}

///|
/// Fund and inspect the exact checked occurrence inventory before choosing
/// a Native file constructor. A failed Query is terminal. Whole requires
/// complete-input selection for each original, even when several share a task.
pub fn[I] prepare_request_native_file_source_inputs(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  bodies : (String, String)?,
) -> Result[
  ClientRequestNativeFileSourceInputs,
  ClientRequestNativeFileSourceIssue,
] {
  preparation_module_call(
    () => {
      let (direct, sources) = match
        reserve_request_whole_source_routes(
          owner,
          input,
          request,
          select_query=true,
        ) {
        Err(issue) => return Err(NativeFileSourceSelection(issue))
        Ok(value) => value
      }
      if !sources.is_empty() {
        return reserve_request_selected_whole_source_inputs(
            owner, input, sources,
          )
          .map(_ => WholeSourceInputs(direct, sources))
          .map_err(issue => NativeFileWholeConstruction(issue))
      }
      // The selector requires at least one original and refuses mixed routes.
      // No Whole Source original here therefore means every route was Query.
      guard owner.phase == Selecting && owner.compiled_program is Some(prepared) else {
        return Err(NativeFileSourceSelection(Preparation(ForeignOriginal)))
      }
      owner.program_domain_quote = None
      owner.phase = ProgramPlanReserved
      guard bodies is Some((query, evidence)) else {
        return Ok(MissingQueryContracts)
      }
      admit_request_query_acquisition_contracts_for_original(
        owner, input, prepared, direct, query, evidence,
      )
      .map(value => QuerySourceInputs(value.0, value.1))
      .map_err(issue => NativeFileQueryContracts(issue))
    },
    () => if owner.phase == Selecting { owner.phase = ProgramBodyFailed },
  )
}
