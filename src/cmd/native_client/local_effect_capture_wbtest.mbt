///|
test "CLI original Effect capture uses the actual Native Work caller without a supplied journal" {
  // This compiles the real caller. It opens no Source, Store or Provider and
  // is not evidence that the Native physical component fixture executed.
  let caller : (
    @local_host.NativeLocalHostConnection,
    LocalHostSettings,
    @local_crypto.Library,
    @local_host.NativeClientSubmissionReference,
    @run_host.ClientRequestIdentity,
    @local_host.NativeClientEffectSourceWork,
    LocalRunInstallation,
    @source_owner.ResidentSourceComputeConfiguration,
  ) -> Result[
    @source_owner.ResidentLocalEffectCaptureContext,
    LocalEffectOriginalCaptureIssue,
  ] = local_capture_effect_original
  caller |> ignore
  assert_true(
    @local_host.NativeClientEffectCaptureIssue::Normalization(
      @run_host.MissingOriginalJournal,
    )
    is Normalization(@run_host.MissingOriginalJournal),
  )
}
