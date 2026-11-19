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
      // The grow rechecks the SAME owner/input/compiled body after callback.
      // Keep its successful extent; no refund/regrant of earlier constructor
      // peaks and no replacement of pending physical cleanup duties occurs.
      owner.program_domain_quote = None
      owner.phase = ProgramPlanReserved
      Ok((direct, sources))
    },
    () => if owner.phase == Selecting { owner.phase = ProgramBodyFailed },
  )
}
