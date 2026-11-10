///|
pub(all) enum NativeClientRequestModelReadIssue {
  Native(@bootstrap.NativeBackedRequestPreparationIssue)
  Model(@host.ClientModelReadFrameIssue)
}

///|
/// The physical supplier must retain this exact entered Request frame and
/// checked Model scope. This observation creates no replacement Ledger, grant,
/// descriptor or execution. Complete constructor funding remains prerequisite.
pub fn[I] check_native_client_request_model_read(
  arena : @arena.InstalledArenaHost,
  live : @bootstrap.NativeBackedLiveChild[
    @arena.InstalledArenaHost,
    @arena.InstalledArenaDomain,
    I,
  ],
  input : I,
  scope : @host.ClientModelReadScope,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @host.ClientInferPlanGraph,
) -> Result[Unit, NativeClientRequestModelReadIssue] {
  let frame = match arena.borrow_request_read_frame(live, input) {
    Err(issue) => return Err(Native(issue))
    Ok(value) => value
  }
  match
    @host.check_client_model_read_frame(
      scope, compiled, definition, plan, frame,
    ) {
    Err(issue) => return Err(Model(issue))
    Ok(_) => ()
  }
  // The final physical-current callback may synchronously finish this scope.
  // Retain the same frame and use only the callback-free Common fence after it.
  match arena.borrow_request_read_frame(live, input) {
    Err(issue) => Err(Native(issue))
    Ok(original) =>
      if physical_equal(original, frame) {
        @host.check_client_model_read_frame_retained(
          scope, compiled, definition, plan, frame,
        ).map_err(issue => Model(issue))
      } else {
        Err(Model(@host.ForeignRun))
      }
  }
}
