///|
// Closed existing publication error kinds. Messages, result identities, Store
// paths and cleanup capabilities remain solely with the original failed owner.
fn local_publication_export_tag(
  issue : @run_host.PublicationOutputExportIssue,
) -> Int64 {
  match issue {
    InvalidState => 1L
    UnknownResult => 2L
    Retain(_) => 3L
    Output(_) => 4L
    Evidence(_) => 5L
    Artifact(_) => 6L
    DurableBinding(_) => 7L
    Capture(_) => 8L
    Source(_) => 9L
  }
}

///|
fn local_publication_store_tag(
  issue : @local_store.NativePublicationStoreIssue,
  emit : (Int, Int64) -> Unit,
) -> Int64 {
  match issue {
    Database(original) | OperationRouting(_, original) => {
      emit(15, local_submission_sql_tag(original))
      1L
    }
    InvalidConfiguration => 2L
    Protocol(_) => 3L
    Filesystem(_) => 4L
    StateCollision => 5L
    RecoveryRequired => 6L
    DigestMismatch => 7L
    DeliveryLimit => 8L
    DeliveryIncomplete => 9L
    CleanupPending | OperationCleanup(_, _) => 10L
    Closed => 11L
    _ => 99L
  }
}

///|
fn local_publication_primary_tags(
  issue : @local_publication.NativeCapturedRunPublicationPrimaryIssue,
  emit : (Int, Int64) -> Unit,
) -> Int64 {
  match issue {
    InvalidCapturedRun => 1L
    Export(original) => {
      emit(13, local_publication_export_tag(original))
      2L
    }
    Publication(_) => 3L
    Output(_, original) => {
      emit(
        13,
        match original {
          InvalidOutputConfiguration => 1L
          Output(cause) | OutputCleanup(cause, _) =>
            100L + local_persisted_export_issue_tag(cause)
          Payload(_) => 2L
          Store(cause) | StoreCleanup(cause, _) =>
            200L + local_publication_store_tag(cause, emit)
          Binding(_) | BindingCleanup(_, _) => 3L
        },
      )
      4L
    }
    Assembly(original) => {
      emit(
        13,
        match original {
          InvalidAssembly => 1L
          Manifest(_) => 2L
          Receipt(_) => 3L
          Capture(_) => 4L
        },
      )
      5L
    }
  }
}

///|
fn local_publication_failure_tags(
  issue : @local_host.NativeClientValuesPublicationIssue,
  emit : (Int, Int64) -> Unit,
) -> Unit {
  let family = match issue {
    Work(original) => {
      // The existing C recorder accumulates amounts. Emit the outer family
      // once; a nested Work must not add its different family into that slot.
      local_values_failure_tags(original, (tag, value) => {
        if tag != 10 {
          emit(tag, value)
        }
      })
      1L
    }
    Policy(_) => 2L
    BindingMismatch => 3L
    Invocation(_) => 4L
    Service(_) => 5L
    Publication(original) => {
      let cause = match original {
        Prepare(primary) => local_publication_primary_tags(primary, emit)
        PrepareCleanup(primary, _) =>
          1000L + local_publication_primary_tags(primary, emit)
      }
      emit(12, cause)
      6L
    }
  }
  emit(10, 10L)
  if family != 1L {
    emit(11, 8000L + family)
  }
}

///|
fn local_completed_export_issue_tag(
  issue : @execution.CompletedExportIssue,
) -> Int64 {
  match issue {
    Unavailable => 1L
    NotCellRepresentation => 2L
    InvalidTarget => 3L
    NotFinished => 4L
    Closed => 5L
    ForeignMaterial => 6L
    Admission(_) => 7L
    Wire(original) =>
      match original {
        InvalidLimits => 201L
        OrderLimit => 202L
        InvalidLayout => 203L
        Encoding(cause) =>
          match cause {
            @encode.InvalidStructure => 2041L
            @encode.InvalidUnicode => 2042L
            @encode.InvalidNumber => 2043L
            @encode.OutputLimit => 2044L
            @encode.ClosedWriter => 2045L
          }
      }
    Schema(original) =>
      match original {
        InvalidLimits => 301L
        FieldLimit => 302L
        Encoding(_) => 303L
        Closed => 304L
        NotFinished => 305L
      }
    ResultView(original) =>
      match original {
        InvalidLimits => 401L
        Unavailable => 402L
        ForeignOccurrence => 403L
        InvalidProjection => 404L
        Limit => 405L
        Comparison(_) => 406L
      }
    CanonicalRow => 11L
  }
}

///|
// Pack two CLOSED discriminants in one slot; the amount recorder accumulates
// writes, so a nested kind must not be emitted independently into that slot.
fn local_persisted_export_issue_tag(
  issue : @run_host.PublicationOutputExportIssue,
) -> Int64 {
  let outer = local_publication_export_tag(issue)
  match issue {
    @run_host.Output(original) =>
      outer + 1000L * local_completed_export_issue_tag(original)
    _ => outer
  }
}
