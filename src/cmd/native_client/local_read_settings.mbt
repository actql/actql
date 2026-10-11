///|
// CLI preflight uses the same finite Host settings admission as actual reads.
// It cannot create an adopted Policy binding or issue a grant.
fn local_read_installation_or_stop(
  text : String,
) -> @local_host.NativeLocalReadSelection raise ClientStop {
  match @local_host.admit_native_local_read_selection(text) {
    Ok(value) => value
    Err(issue) =>
      stop(
        match issue {
          @local_host.InvalidOriginal => "InvalidLocalReadPolicyOriginal"
          @local_host.InvalidLimits => "InvalidLocalReadPolicyLimits"
          @local_host.UnsupportedSink => "UnsupportedLocalReadSink"
          @local_host.UnsupportedFormat => "UnsupportedLocalReadFormat"
          @local_host.InvalidPolicyReference =>
            "InvalidLocalReadPolicyReference"
        },
      )
  }
}
