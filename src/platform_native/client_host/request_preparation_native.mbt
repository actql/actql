///|
pub(all) enum NativeClientRequestPreparationIssue {
  Native(@bootstrap.NativeBackedRequestPreparationIssue)
  Request(@local.ClientRequestPreparationIssue)
}

///|
/// Connect the same installed input-bound child to Common Request preparation.
/// The Native issuer has retained the original frame before any fallible start;
/// Common alone creates its census and transfers that owner to the Run.
pub fn[I] begin_native_client_request_preparation(
  arena : @arena.InstalledArenaHost,
  live : @bootstrap.NativeBackedLiveChild[
    @arena.InstalledArenaHost,
    @arena.InstalledArenaDomain,
    I,
  ],
  input : I,
  policy : @local.ClientLocalResourcePolicy,
) -> Result[
  @local.ClientRequestPreparation[I],
  NativeClientRequestPreparationIssue,
] {
  let admission = match arena.prepare_request_admission(live, input) {
    Err(issue) => return Err(Native(issue))
    Ok(value) => value
  }
  @local.begin_backed_request_preparation(admission, input, policy).map_err(issue => {
    Request(issue)
  })
}

///|
pub(all) enum NativeClientRequestSourceReadIssue {
  Native(@bootstrap.NativeBackedRequestPreparationIssue)
  Source(@local.ClientInstalledSourceReadIssue)
}

///|
/// Typed observation before a physical reader constructor: the same entered
/// Native Request must back the existing Common managed Source read. No second
/// Request, RowRun, Ledger or read is admitted, and no physical ACK is issued.
/// Actual reader construction and its complete funding remain separate.
pub fn[I] check_native_client_request_source_read(
  arena : @arena.InstalledArenaHost,
  live : @bootstrap.NativeBackedLiveChild[
    @arena.InstalledArenaHost,
    @arena.InstalledArenaDomain,
    I,
  ],
  input : I,
  read : @local.ClientInstalledSourceRead,
) -> Result[Unit, NativeClientRequestSourceReadIssue] {
  let frame = match arena.borrow_request_read_frame(live, input) {
    Err(issue) => return Err(Native(issue))
    Ok(value) => value
  }
  let observation = match
    @local.check_installed_source_read_frame(read, frame) {
    Err(issue) => return Err(Source(issue))
    Ok(value) => value
  }
  // Common currentness may reenter the physical owner. Re-observe the same
  // current entered frame, without consulting the transferred admission.
  match arena.borrow_request_read_frame(live, input) {
    Err(issue) => Err(Native(issue))
    Ok(original) =>
      if physical_equal(original, frame) {
        @local.check_installed_source_read_frame_retained(
          observation, read, original,
        ).map_err(issue => Source(issue))
      } else {
        Err(Source(@local.ForeignOriginal))
      }
  }
}
