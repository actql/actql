///|
// Test-only use of the already source-qualified closed error discriminants.
// The exact failed original call is observed without formatting its SQL,
// identity, paths or receivers, and without allocating a diagnostic payload.
extern "C" fn relation_original_submission_amount(
  tag : Int,
  amount : Int64,
) -> Unit = "actql_native_timing_amount"

///|
// Closed diagnostic tags only, using the existing opt-in Native counters.
// No String, SQL, path, identity, receiver or cleanup capability is serialized.
// These scalar projections allocate no diagnostic payload in the failed Read.
fn relation_original_submission_ledger_tag(
  issue : @resources.LedgerIssue,
) -> Int64 {
  match issue {
    InvalidLimits => 1L
    PlanningLimit => 2L
    AttemptLimit => 3L
    HoldingLimit => 4L
    TransferLimit => 5L
    RetentionLimit => 6L
    ExecutionLimit => 7L
    ForeignOwner => 8L
    ClosedReservation => 9L
    ClosedHolding => 10L
    InvalidCharge => 11L
    IdentityOverflow => 12L
    TokenLimit => 13L
    CostLimit => 14L
    DurationLimit => 15L
    ResourceParked => 16L
    ChildFundingUnavailable => 17L
  }
}

///|
fn relation_original_submission_sql_tag(
  issue : @sqlite.NativeSqliteIssue,
) -> Int64 {
  match issue {
    UnsupportedTarget => 1L
    InvalidName => 2L
    InvalidLimit => 3L
    LibraryLoad(_) => 4L
    DatabaseOpen(_) => 5L
    DatabaseClosed => 6L
    NotFound => 7L
    Collision => 8L
    Busy => 9L
    BodyTooLarge => 10L
    CapacityExceeded => 11L
    Physical(_) => 12L
    OperationRoutingBefore(_) => 13L
    OperationRoutingAfter(_, _) => 14L
  }
}

///|
fn relation_original_submission_backing_tags(
  issue : @bootstrap.NativeBackedExecutionIssue,
  base : Int64,
  emit : (Int, Int64) -> Unit,
) -> Unit {
  let leaf = match issue {
    Bootstrap(cause) => {
      let tag = match cause {
        Unavailable => 1L
        ForeignOriginal => 2L
        AlreadyConsumed => 3L
        Closing => 4L
        ReadersPending => 5L
        Physical(code) => {
          // Exact signed Int32 status in a nonnegative Int64 diagnostic slot.
          emit(12, code.to_int64() + 2147483648L)
          6L
        }
        Resource(resource) => {
          emit(13, relation_original_submission_ledger_tag(resource))
          7L
        }
      }
      10L + tag
    }
    Accounting(cause) => {
      let tag = match cause {
        ForeignOriginal => 1L
        InvalidExtent => 2L
        ExtentConflict => 3L
        DuplicateChild => 4L
        RegionClosing => 5L
        Retired => 6L
        CleanupPending => 7L
        ChangedFinalUsage => 8L
        ReadUseAlreadyIssued => 9L
        LiveAccessAlreadyIssued => 10L
        LiveChildAlreadyAdmitted => 11L
        Resource(resource) => {
          emit(13, relation_original_submission_ledger_tag(resource))
          12L
        }
      }
      30L + tag
    }
  }
  emit(11, base + leaf)
}

///|
fn relation_original_submission_pair_tags(
  issue : @arena.InstalledArenaLocalHostResourcesIssue,
  emit : (Int, Int64) -> Unit,
) -> Unit {
  match issue {
    Read(Domain(cause)) =>
      relation_original_submission_backing_tags(cause, 1100L, emit)
    Read(Child(cause)) => {
      let tag = match cause {
        Unavailable => 1L
        Unknown => 2L
        ForeignOriginal => 3L
        AlreadyConsumed => 4L
        InvalidOriginal => 5L
        Resource(resource) => {
          emit(13, relation_original_submission_ledger_tag(resource))
          6L
        }
      }
      emit(11, 1200L + tag)
    }
    Read(Read(cause)) => {
      let tag = match cause {
        InvalidBootstrap => 1L
        IncompleteInventory => 2L
        ForeignOrigin => 3L
        ChangedOriginalState => 4L
        SpentClaim => 5L
        CleanupPending => 6L
        Resource(resource) => {
          emit(13, relation_original_submission_ledger_tag(resource))
          7L
        }
      }
      emit(11, 1300L + tag)
    }
    Read(Buffer(_)) => emit(11, 1400L)
    Sqlite(Domain(cause)) =>
      relation_original_submission_backing_tags(cause, 2000L, emit)
    Sqlite(Library(cause)) => {
      emit(11, 3000L)
      emit(15, relation_original_submission_sql_tag(cause))
    }
    Domain(cause) =>
      relation_original_submission_backing_tags(cause, 4000L, emit)
  }
}

///|
// At most four retained wrapper discriminants, packed as base-16 digits.
// Leave retains its own failed return and, if present, the earlier cause.
fn relation_original_submission_original_tags(
  issue : @client.NativeLocalAdoptionIssue,
  path : Int64,
  remaining : Int,
  emit : (Int, Int64) -> Unit,
) -> Unit {
  if remaining <= 0 {
    emit(10, path * 16L + 15L)
    return
  }
  match issue {
    OriginalResources(cause) => {
      emit(10, path * 16L + 1L)
      relation_original_submission_pair_tags(cause, emit)
    }
    OriginalResourceLeave(prior, cause) => {
      // Bits20+ retain a prior outer family separately from the failed leave;
      // do not add another value to the transaction-wrapper counter.
      let prior_tag = match prior {
        None => 0L
        Some(original) =>
          match original {
            OriginalResources(_) => 2L
            OriginalResourceScopePending => 3L
            Physical(_) => 4L
            _ => 5L
          }
      }
      emit(10, path * 16L + 2L + prior_tag * 1048576L)
      relation_original_submission_pair_tags(cause, emit)
    }
    Physical(cause) => {
      emit(10, path * 16L + 3L)
      emit(15, relation_original_submission_sql_tag(cause))
    }
    DatabasePending(_, original) =>
      relation_original_submission_original_tags(
        original,
        path * 16L + 4L,
        remaining - 1,
        emit,
      )
    OriginalResourceScopePending => emit(10, path * 16L + 5L)
    _ => emit(10, path * 16L + 6L)
  }
}

///|
fn relation_original_submission_failure_tags(
  issue : @client.NativeLocalAdoptionIssue,
  emit : (Int, Int64) -> Unit,
) -> Unit {
  // Slots8-15 were unselected in the existing64-counter recorder. They identify
  // this single failed acceptance, its original typed cause and transaction
  // uncertainty; transaction_with_reads records real outcomes in slots4-7.
  emit(8, 1L)
  match issue {
    InstallationReadTransactionFailure(original, transaction) => {
      emit(9, 1L)
      emit(
        14,
        match transaction {
          TransactionUnknown => 1L
          _ => 2L
        },
      )
      relation_original_submission_original_tags(original, 0L, 4, emit)
    }
    Journal(TransactionUnknown) => {
      emit(9, 6L)
      emit(14, 1L)
    }
    Journal(Epoch(TransactionUnknown)) => {
      emit(9, 7L)
      emit(14, 1L)
    }
    _ => relation_original_submission_original_tags(issue, 0L, 4, emit)
  }
}
