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
