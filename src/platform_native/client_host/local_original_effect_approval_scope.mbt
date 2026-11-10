///|
// Two existing original read owners, not an authority issued from CID DATA.
// Public Resident entry signatures remain unchanged; saved Native review is
// selected only after its full original computation/Preview admission.
priv enum NativeLocalOriginalEffectApprovalScope {
  ResidentApproval(@resident.ResidentOriginalEffectApprovalScope)
  SavedApproval(NativeLocalSavedEffectReview)
}

///|
priv enum NativeLocalOriginalEffectSigningSubjectRead {
  ResidentSigningSubject(@resident.ResidentOriginalEffectSigningSubjectRead)
  SavedSigningSubject(NativeLocalSavedEffectSigningSubjectRead)
}

///|
priv struct NativeLocalSavedEffectSigningSubjectRead {
  owner : NativeLocalSavedEffectReview
  original : NativeLocalSavedEffectApprovalOriginal
}

///|
fn NativeLocalOriginalEffectApprovalScope::current_for(
  self : NativeLocalOriginalEffectApprovalScope,
  request : @host.ClientRequestIdentity,
  run_definition_cid : String,
  checkpoint_cid : String,
) -> String? {
  match self {
    ResidentApproval(original) =>
      original.current_for(request, run_definition_cid, checkpoint_cid)
    SavedApproval(original) =>
      original.saved_approval_current_for(
        request,
        run_definition_cid,
        checkpoint_cid,
        @env.now().to_double(),
      )
  }
}

///|
fn NativeLocalOriginalEffectApprovalScope::read_original_signing_subject_for(
  self : NativeLocalOriginalEffectApprovalScope,
  request : @host.ClientRequestIdentity,
  run_definition_cid : String,
  checkpoint_cid : String,
) -> Result[
  NativeLocalOriginalEffectSigningSubjectRead,
  NativeLocalEffectReviewerBindingIssue,
] {
  match self {
    ResidentApproval(original) =>
      original
      .read_original_signing_subject_for(
        request, run_definition_cid, checkpoint_cid,
      )
      .map(value => ResidentSigningSubject(value))
      .map_err(_ => ReviewerUnavailable)
    SavedApproval(owner) => {
      guard owner.approval_original is Some(original) else {
        return Err(ReviewerUnavailable)
      }
      let current = self.current_for(
        request, run_definition_cid, checkpoint_cid,
      )
      if current != Some(original.authority) ||
        !owner.saved_approval_original_live(original) {
        return Err(ReviewerUnavailable)
      }
      Ok(SavedSigningSubject({ owner, original, }))
    }
  }
}

///|
// No callback follows this final same-original alias check. It does not
// restore, reread, recapture or renew any retired backing or physical owner.
fn NativeLocalOriginalEffectSigningSubjectRead::original_subject_after_current(
  self : NativeLocalOriginalEffectSigningSubjectRead,
) -> Result[(String, String), NativeLocalEffectReviewerBindingIssue] {
  match self {
    ResidentSigningSubject(original) =>
      original
      .original_subject_after_current()
      .map_err(_ => ReviewerUnavailable)
    SavedSigningSubject(read) => {
      if !read.owner.saved_approval_original_live(read.original) {
        return Err(ReviewerUnavailable)
      }
      Ok(
        (
          @publication.publication_contract_identity(read.original.invocation),
          read.original.unit_definition_cid,
        ),
      )
    }
  }
}

///|
/// Same adopted initial Reviewer and independent Client Run-read authority.
/// Saved review supplies an authenticated original subject, never a new
/// Resident owner, configured key, credential issue right or signing use.
pub fn NativeLocalSavedEffectReview::bind_initial_effect_reviewer(
  self : NativeLocalSavedEffectReview,
  initial_original : NativeLocalInitialSigningOriginal,
  host_configuration_file : String,
  now : () -> Double,
) -> Result[
  (NativeLocalEffectReviewerBinding, NativeLocalInstalledEffectReviewer),
  NativeLocalEffectReviewerBindingIssue,
] {
  guard self.capture.opening is JournalAcquired(host) &&
    self.approval_original is Some(_) &&
    self._retained_original is Some(metadata) &&
    self.saved_approval_current_for(
      self.selected.request,
      metadata.run_definition_cid,
      metadata.checkpoint_cid,
      now(),
    )
    is Some(_) else {
    return Err(ReviewerUnavailable)
  }
  let installed = match
    host.install_initial_effect_reviewer(
      initial_original,
      self.principal,
      self.connection,
      host_configuration_file,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  host
  .bind_selected_effect_reviewer(
    self.capture.crypto,
    self.principal,
    self.connection,
    self.selected.reference,
    self.selected.request,
    SavedApproval(self),
    now,
    installed,
  )
  .map(binding => (binding, installed))
}
