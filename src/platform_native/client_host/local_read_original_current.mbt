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
  read_binding_with_material_in_original_read(capture, (
    host,
    _material,
    operations,
  ) => call(host, operations))
}

///|
// The closed read-policy operation consumes this already-admitted material.
// Keep the original body/return error join identical to the other read routes.
fn[T] read_binding_with_material_in_original_read(
  capture : NativeLocalJournalCapture,
  call : (
    NativeLocalHostConnection,
    @host.ClientLocalAdoptedHostMaterial[
      @sqlite.Database,
      NativeLocalAdoptionIssue,
    ],
    NativeClientJournalOperationAccess,
  ) -> Result[T, NativeLocalReadBindingIssue],
) -> Result[T, NativeLocalReadBindingIssue] {
  let output : Ref[Result[T, NativeLocalReadBindingIssue]?] = Ref(None)
  let captured = capture.with_current_adoption_material_in_original_read((
    host,
    material,
    operations,
  ) => {
    let result = call(host, material, operations)
    output.val = Some(result)
    match result {
      Err(
        Journal(TransactionUnknown | Epoch(TransactionUnknown))
        | SubmittedResult(
          Journal(TransactionUnknown | Epoch(TransactionUnknown))
        )
        | OriginalRead(_, TransactionUnknown)
      ) => Err(Journal(TransactionUnknown))
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

///|
/// The original selected Material file and actual receiver are both required.
/// A copied identity or the independent stdout selection cannot substitute.
pub fn NativeLocalJournalCapture::bind_result_material_read_policy_for_run_in_original_read(
  self : NativeLocalJournalCapture,
  policy : NativeLocalRunPolicyBinding,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  now : Double,
  material_file : String,
) -> Result[NativeLocalReadPolicyBinding, NativeLocalReadBindingIssue] {
  read_binding_in_original_read(self, (host, _operations) => {
    host.bind_result_read_policy_for_run_with_capture(
      policy,
      reference,
      request,
      now,
      capture=Some(self),
      material_file=Some(material_file),
    )
  })
}

///|
/// The independent adopted File selection is never a relabelled stdout
/// selection. The returned binding must be retained before opening its actual
/// destination, including a partially acquired Root or Writer.
pub fn NativeLocalJournalCapture::bind_result_file_read_policy_for_run_in_original_read(
  self : NativeLocalJournalCapture,
  policy : NativeLocalRunPolicyBinding,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  now : Double,
  file : String,
) -> Result[NativeLocalReadPolicyBinding, NativeLocalReadBindingIssue] {
  read_binding_in_original_read(self, (host, _operations) => {
    host.bind_result_read_policy_for_run_with_capture(
      policy,
      reference,
      request,
      now,
      capture=Some(self),
      file_configuration=Some(file),
    )
  })
}

///|
/// Bind one requested original Result after the SAME committed Run/Store/current
/// lookup. The optional independent sink file remains an exact adopted original.
/// The returned binding contains a finite one-name selection; templates cannot
/// reach read/egress code, and old finite selections are never widened.
pub fn NativeLocalJournalCapture::bind_requested_original_result_read_in_original_read(
  self : NativeLocalJournalCapture,
  policy : NativeLocalRunPolicyBinding,
  original : NativeClientOriginalRunSelection,
  store : @publication_store.Store,
  namespace_id : String,
  result_name : String,
  now : Double,
  prepare : (Int64, Int64) -> Bool,
  material_file? : String? = None,
  file_configuration? : String? = None,
) -> Result[NativeLocalReadPolicyBinding, NativeLocalReadBindingIssue] {
  // Synchronous wrapper closure1H9R1W; six optional input/result contexts
  // 6H9R5W; original predicate1H9R and primary cell1H1R; caught issue Some
  // 1H1R1W; final checked return/match2H2R2W. These controls coexist with the
  // separately admitted finite selection and original Store read (12H31R9W).
  // Retain conservatively until this SAME command Read actually retires.
  guard @execution.preparation_representation_cost({
      record_headers: 12L,
      reference_slots: 31L,
      scalar_words: 9L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(cost) &&
    prepare(cost, cost) else {
    return Err(Adoption(OriginalResourceScopePending))
  }
  read_binding_in_original_read(self, (host, operations) => {
    host.bind_result_read_policy_for_run_with_capture(
      policy,
      original.reference,
      original.request,
      now,
      capture=Some(self),
      material_file~,
      file_configuration~,
      requested_result=Some((original, store, namespace_id, result_name)),
      construction=Some(prepare),
      requested_operations=Some(operations),
    )
  })
}
