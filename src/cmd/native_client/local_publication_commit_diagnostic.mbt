///|
// Closed commit causes only. Original identities, wire fields, Store paths and
// cleanup handles remain with the same failed publication owner.
fn local_publication_evidence_cause(
  issue : @publication.RunEvidenceChainIssue,
) -> Int64 {
  match issue {
    EvidenceEncoding => 101L
    EvidenceRoot(_) => 102L
    EvidenceWrongContract(_) => 103L
    EvidenceMissingField(_) => 104L
    EvidenceReferenceMismatch(_) => 105L
    EvidenceEmbeddedIdentity(field) =>
      match field {
        "prepared_invocation_cid" => 1061L
        "run_authorization_cid" => 1062L
        "observation_set_cid" => 1063L
        "authoring_context_cid" => 1064L
        _ => 1060L
      }
    EvidenceInventoryMismatch(_) => 107L
    EvidenceNotEffectFree => 108L
  }
}

///|
fn local_publication_commit_cause(
  issue : @publication.PublicationCommitIssue,
) -> Int64 {
  match issue {
    CommitEvidence(original) => local_publication_evidence_cause(original)
    CommitResultEvidence(_) => 2L
    CommitWrongContract(_) => 3L
    CommitReferenceMismatch(_) => 4L
    CommitInventoryMismatch => 5L
    CommitEncoding => 6L
  }
}

///|
fn local_publication_preparation_owner_cause(
  issue : @local_values.ClientClosedValuesPreparationIssue,
  emit : (Int, Int64) -> Unit,
) -> Int64 {
  match issue {
    ForeignOriginal => 1L
    WrongPhase => 2L
    Policy => 3L
    Syntax(_) => 4L
    Preparation(_) => 5L
    Installed(_) => 6L
    Compilation(_) => 7L
    Initial(_) => 8L
    Capacity(original) =>
      match original {
        ForeignOriginal => 201L
        WorkActive => 202L
        AlreadyCompleted => 203L
        AlreadyTransferred => 204L
        Retired => 205L
        BorrowReturned => 206L
        InvalidExtent => 207L
        Resource(resource) => {
          emit(13, local_submission_ledger_tag(resource))
          208L
        }
      }
    Work(_) => 9L
    CapacityExceeded(_) => 10L
    Intent(_) => 11L
    PublicationInvocation(_) => 12L
    PublicationCapture(_) => 13L
    PublicationSnapshot(_) => 14L
    PublicationRetention(_) => 15L
  }
}

///|
fn local_publication_validation_cause(
  issue : @local_values.ClientProgramValidationIssue,
  emit : (Int, Int64) -> Unit,
) -> Int64 {
  match issue {
    Owner(original) =>
      5000L + local_publication_preparation_owner_cause(original, emit)
    Chain(original) => 6000L + local_publication_evidence_cause(original)
    Commit(original) => 7000L + local_publication_commit_cause(original)
  }
}

///|
fn local_publication_delivery_cause(
  issue : @publication.DeliveryIssuanceIssue,
) -> Int64 {
  match issue {
    DeliveryIssuanceWrongContract(_) => 1L
    DeliveryIssuanceReferenceMismatch(field) =>
      match field {
        "binding.result_schema" => 201L
        "binding.physical_facts" => 202L
        "binding.store_authority_cid" => 203L
        "binding.material_generation_cid" => 204L
        "binding.logical_result_cid" => 205L
        "binding.result_schema_cid" => 206L
        "binding.ordering_evidence_cid" => 207L
        "binding.codec_contract_cid" => 208L
        "binding.physical_sha256" => 209L
        _ => 200L
      }
    DeliveryIssuanceUnknownResult(_) => 3L
    DeliveryIssuanceDuplicateResult(_) => 4L
    DeliveryIssuanceUnsupportedFormat(_) => 5L
    DeliveryIssuanceInvalidLimit => 6L
    DeliveryIssuanceInvalidOutcome => 7L
    DeliveryIssuanceExpiredGrant => 8L
    DeliveryIssuanceEncoding => 9L
    DeliveryIssuanceContract(_) => 10L
    DeliveryIssuanceTransition(_) => 11L
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
    PublicationPreparation(original) =>
      local_publication_validation_cause(original, emit)
    DeliveryIssuance(original) =>
      8000L + local_publication_delivery_cause(original)
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
    Preparation(_) => (9L, 0L)
  }
  emit(10, 11L)
  emit(11, 9000L + family)
  emit(12, cause)
}
