///|
extern "C" fn flush_stdout_ffi() -> Bool = "actql_native_client_flush_stdout"

///|
/// Native sink installation only; the Local Host must supply an already
/// admitted, currently authorized original Result session. This helper does
/// not create a grant, negotiate a Host or replay a Run. Failed flush cannot
/// certify any prefix of the offered chunk; possible exposure stays bounded.
fn native_local_stdout_sink(
  session : @local_result.NativeResultAccessSession,
  max_output_bytes : Int,
) -> Result[@local_result.NativeResultSink, @local_result.NativeResultSinkIssue] {
  @local_result.install_native_result_sink(
    session,
    16384,
    max_output_bytes,
    bytes => {
      if write_stdout_ffi(bytes, bytes.length()) {
        @local_result.SinkChunkConfirmed
      } else {
        @local_result.SinkChunkFailed(0, bytes.length())
      }
    },
    () => flush_stdout_ffi(),
  )
}
