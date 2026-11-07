///|
// Existing failed Work variants only. Keep the actual failed occurrence and
// its cleanup with the caller; counters carry no document, identity or handle.
fn local_values_failure_tags(
  issue : @local_host.NativeClientValuesWorkIssue,
  emit : (Int, Int64) -> Unit,
) -> Unit {
  emit(10, 9L)
  let family = match issue {
    AuthorizationDenied => 1L
    UnsupportedProfile => 2L
    Configuration => 3L
    Journal(original) => {
      emit(
        12,
        match original {
          CapacityExceeded => 1L
          CustodyLost => 2L
          ForeignRun => 3L
          TransactionUnknown => 4L
          Physical(cause) => {
            emit(15, local_submission_sql_tag(cause))
            5L
          }
          _ => 99L
        },
      )
      4L
    }
    Start(_) => 5L
    Normalization(original) => {
      emit(
        12,
        match original {
          Inventory(_) => 1L
          ForeignPreparation => 2L
          ForeignCatalog => 3L
          SubstitutedJournal => 4L
          Evidence(_) => 5L
          CommonInventory(cause) => {
            let leaf = match cause {
              InvalidLimits => 1L
              BudgetExceeded => 2L
              ForeignOriginal => 3L
              CompletionObserved => 4L
              UnsupportedRequirement => 5L
            }
            100L + leaf
          }
        },
      )
      6L
    }
    Execution(original) => {
      emit(
        12,
        match original {
          InvalidLimits => 1L
          Fenced => 2L
          UnsupportedGraph => 3L
          MissingLocalModule => 4L
          Driver(_) => 5L
          Estimate(_) => 6L
          FinalizationLimit => 7L
          MissingOutput => 8L
        },
      )
      7L
    }
    Export(original) => {
      emit(
        12,
        match original {
          MissingOutput => 1L
          UnknownResult => 2L
          Bridge(_) => 3L
          Export(cause) => {
            if cause is @run_host.Output(original) {
              emit(13, local_completed_export_issue_tag(original))
            }
            100L + local_publication_export_tag(cause)
          }
        },
      )
      8L
    }
    OriginalOperation(_, original) => {
      emit(
        12,
        match original {
          StoreOperationUnavailable => 1L
          StoreOperationForeignOriginal => 2L
          StoreOperationCapture(_) => 3L
          StoreOperationResources(_) => 4L
          StoreOperationExecution(_) => 5L
          StoreOperationSqlite(cause) => {
            emit(15, local_submission_sql_tag(cause))
            6L
          }
        },
      )
      9L
    }
  }
  emit(11, 7000L + family)
}
