///|
// Closed commit causes only. Original identities, wire fields, Store paths and
// cleanup handles remain with the same failed publication owner.
fn local_publication_commit_cause(
  issue : @publication.PublicationCommitIssue,
) -> Int64 {
  match issue {
    CommitEvidence(EvidenceEncoding) => 101L
    CommitEvidence(EvidenceRoot(_)) => 102L
    CommitEvidence(EvidenceWrongContract(_)) => 103L
    CommitEvidence(EvidenceMissingField(_)) => 104L
    CommitEvidence(EvidenceReferenceMismatch(_)) => 105L
    CommitEvidence(EvidenceEmbeddedIdentity(_)) => 106L
    CommitEvidence(EvidenceInventoryMismatch(_)) => 107L
    CommitEvidence(EvidenceNotEffectFree) => 108L
    CommitResultEvidence(_) => 2L
    CommitWrongContract(_) => 3L
    CommitReferenceMismatch(_) => 4L
    CommitInventoryMismatch => 5L
    CommitEncoding => 6L
  }
}

///|
fn local_publication_commit_issuance_cause(
  issue : @publication.PublicationCommitIssuanceIssue,
) -> Int64 {
  match issue {
    CommitIssuanceWrongContract => 1L
    CommitIssuanceInventoryMismatch => 2L
    CommitIssuanceDuplicateResult(_) => 3L
    CommitIssuanceReferenceMismatch(_) => 4L
    CommitIssuanceEncoding => 5L
    CommitIssuanceContract(_) => 6L
  }
}

///|
fn local_publication_commit_store_cause(
  issue : @local_store.NativePublicationStoreIssue,
  emit : (Int, Int64) -> Unit,
) -> Int64 {
  match issue {
    PublicationCommit(original) =>
      1000L + local_publication_commit_cause(original)
    PublicationCommitIssuance(original) =>
      2000L + local_publication_commit_issuance_cause(original)
    OperationRouting(Some(original), sqlite) => {
      emit(15, local_submission_sql_tag(sqlite))
      3000L + local_publication_commit_store_cause(original, (_, _) => ())
    }
    OperationCleanup(Some(original), _) =>
      4000L + local_publication_commit_store_cause(original, emit)
    _ => local_publication_store_tag(issue, emit)
  }
}

///|
fn local_publication_commit_failure_tags(
  issue : @local_publication.NativeRunPublicationIssue,
  emit : (Int, Int64) -> Unit,
) -> Unit {
  let (family, cause) = match issue {
    InvalidConfiguration => (1L, 0L)
    AccessDenied => (2L, 0L)
    CommitConflict => (3L, 0L)
    CommitFenceUnavailable => (4L, 0L)
    Store(original) =>
      (5L, local_publication_commit_store_cause(original, emit))
    Issuance(original) =>
      (6L, local_publication_commit_issuance_cause(original))
    Commit(original) => (7L, local_publication_commit_cause(original))
    Projection(_) => (8L, 0L)
  }
  emit(10, 11L)
  emit(11, 9000L + family)
  emit(12, cause)
}
