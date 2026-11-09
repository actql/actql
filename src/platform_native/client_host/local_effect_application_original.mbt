///|
/// Borrow only the same fully restored Saved computation/Preview after its
/// successful Resolution. This is immutable DATA, not dispatch permission,
/// a renewed approval, a new Run or a constructor/backing supplier. The actual
/// caller separately checks current Account and the original lease before IO.
/// No Store, signer, clock or current callback runs inside this projection.
pub fn NativeLocalEffectResumeOriginal::application_original_in_original_read(
  self : NativeLocalEffectResumeOriginal,
) -> Result[
  NativeLocalSavedEffectApprovalOriginal,
  NativeLocalInitialHostAttestationIssue,
] {
  guard self.prepared &&
    !self.retired &&
    self.subject is Some(SavedSigningSubject(read)) &&
    read.owner.saved_approval_original_live(read.original) &&
    read.original.unit_definition_cid == self.unit_definition_cid &&
    @publication.publication_contract_identity(read.original.invocation) ==
    self.invocation_cid &&
    @publication.publication_contract_identity(
      read.original.materials.run_definition,
    ) ==
    @publication.publication_contract_identity(self.record.definition) &&
    read.original.materials.request == Some(self.request) else {
    return Err(HostAttestationUnavailable)
  }
  Ok(read.original)
}

///|
/// The exact existing checked preparation/compilation/Run tuple. It does not
/// issue another Request or rerun Source/Model/normalization.
pub fn NativeLocalSavedEffectApprovalOriginal::run_materials(
  self : Self,
) -> @host.ClientEffectRunMaterials {
  self.materials
}

///|
pub fn NativeLocalSavedEffectApprovalOriginal::effect_preview(
  self : Self,
) -> @publication.EffectPreviewIdentity {
  self.preview
}

///|
/// Same admitted private bytes, retained for adapter request projection. The
/// consumer must fund that projection; this getter supplies no allocation.
pub fn NativeLocalSavedEffectApprovalOriginal::effect_preview_wire(
  self : Self,
) -> String {
  self.preview_wire
}

///|
/// Execution order and raw admission order are different inventories. Join
/// once through the original row CID; never index the raw key vector by an
/// execution ordinal or recompute an already checked key.
pub fn NativeLocalSavedEffectApprovalOriginal::ordered_row_key(
  self : Self,
  member_index : Int,
  row_ordinal : Int,
) -> @effect.EffectDispatchKey? {
  retained_effect_ordered_row_key(
    self.preview,
    self.row_keys,
    member_index,
    row_ordinal,
  )
}

///|
pub fn NativeLocalSavedEffectApprovalOriginal::request_scope(
  self : Self,
) -> @scope.LogicalRequestScope {
  self.scope
}

///|
fn retained_effect_ordered_row_key(
  preview : @publication.EffectPreviewIdentity,
  row_keys : Array[Array[@effect.EffectDispatchKey]],
  member_index : Int,
  row_ordinal : Int,
) -> @effect.EffectDispatchKey? {
  guard @publication.effect_preview_ordered_row_identity(
      preview, member_index, row_ordinal,
    )
    is Some(row) &&
    @publication.effect_preview_row_index(preview, member_index, row)
    is Some(raw_index) else {
    return None
  }
  row_keys.get(member_index).bind(keys => keys.get(raw_index))
}
