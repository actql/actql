///|
// Private routing only. The existing capture owns actual entry/current/SQL
// exchange and the first return failure. Retain the body issue independently;
// a failed scope return cannot turn a checked read into permission or success.
fn[T] read_binding_in_original_read(
  capture : NativeLocalJournalCapture,
  call : (NativeLocalHostConnection, NativeClientJournalOperationAccess) -> Result[
    T,
    NativeLocalReadBindingIssue,
  ],
) -> Result[T, NativeLocalReadBindingIssue] {
  let output : Ref[Result[T, NativeLocalReadBindingIssue]?] = Ref(None)
  let captured = capture.with_current_adoption_material_in_original_read((
    host,
    _material,
    operations,
  ) => {
    let result = call(host, operations)
    output.val = Some(result)
    match result {
      Err(Journal(TransactionUnknown | Epoch(TransactionUnknown))) =>
        Err(Journal(TransactionUnknown))
      _ => Ok(())
    }
  })
  match (captured, output.val) {
    (Err(issue), result) =>
      Err(
        OriginalRead(
          match result {
            Some(Err(primary)) => Some(primary)
            _ => None
          },
          issue,
        ),
      )
    (Ok(_), Some(result)) => result
    (Ok(_), None) => Err(Adoption(OriginalResourceScopePending))
  }
}

///|
/// Bind only the selected finite read original and its exact saved Run policy
/// through this capture. This does not issue disclosure evidence or a grant.
/// Legacy/upgraded originals retain their separate existing admission route.
pub fn NativeLocalJournalCapture::bind_result_read_policy_for_run_in_original_read(
  self : NativeLocalJournalCapture,
  policy : NativeLocalRunPolicyBinding,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  now : Double,
) -> Result[NativeLocalReadPolicyBinding, NativeLocalReadBindingIssue] {
  read_binding_in_original_read(self, (host, _operations) => {
    host.bind_result_read_policy_for_run_with_capture(
      policy,
      reference,
      request,
      now,
      capture=Some(self),
    )
  })
}
