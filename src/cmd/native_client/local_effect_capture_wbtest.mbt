///|
test "Native Work capture exposes the original owner method without a supplied journal" {
  // This compiles the real Host method, not an uninstalled CLI adapter. It opens no Source, Store or Provider and
  // is not evidence that the Native physical component fixture executed.
  let caller = fn(
    work : @local_host.NativeClientEffectSourceWork,
    retention : @publication.PublicationContract,
    limits : @run_host.PublicationOutputExportLimits,
    max_bytes : Int,
    max_nodes : Int,
    max_depth : Int,
  ) {
    work.prepare_original_capture_context(
      retention, limits, max_bytes, max_nodes, max_depth,
    )
  }
  caller |> ignore
  assert_true(
    @local_host.NativeClientEffectCaptureIssue::Normalization(
      @run_host.MissingOriginalJournal,
    )
    is Normalization(@run_host.MissingOriginalJournal),
  )
}
