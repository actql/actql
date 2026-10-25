// Test-only typed observation. Numeric tags are fixture diagnostics, never authority,
// public wire, cleanup acknowledgement or an operational result. No string payload
// or physical handle is read/rendered. Production registration remains unchanged.

///|
fn test_observe_adoption(
  issue : NativeLocalAdoptionIssue,
  emit : (Int) -> Unit,
  depth : Int,
) -> Unit {
  if depth <= 0 {
    emit(9999)
    return
  }
  match issue {
    InvalidInput => emit(100)
    ConfigurationLimit => emit(101)
    Configuration(_) => emit(102)
    ForeignAccount => emit(103)
    UninstalledBootstrapProfile => emit(104)
    CustodyLost => emit(105)
    SourceChanged => emit(106)
    AmbiguousInitialization => emit(107)
    Closed => emit(108)
    Encoding => emit(109)
    Crypto(p0) => {
      emit(110)
      test_observe_crypto(p0, emit, depth - 1)
    }
    Filesystem(p0) => {
      emit(111)
      test_observe_fs(p0, emit, depth - 1)
    }
    ReadAcquisitionFailure(_) => emit(112)
    ReadPending(_, _) => emit(113)
    WritePending(_, _) => emit(114)
    Physical(p0) => {
      emit(115)
      test_observe_sql(p0, emit, depth - 1)
    }
    Epoch(p0) => {
      emit(116)
      test_observe_epoch(p0, emit, depth - 1)
    }
    Journal(p0) => {
      emit(117)
      test_observe_run(p0, emit, depth - 1)
    }
    Fenced => emit(118)
    TransactionUnknown => emit(119)
    DatabasePending(_, p1) => {
      emit(120)
      test_observe_adoption(p1, emit, depth - 1)
    }
    Inspection(p0) => {
      emit(121)
      test_observe_inspection(p0, emit, depth - 1)
    }
    InstallationReadTransactionFailure(p0, p1) => {
      emit(122)
      test_observe_adoption(p0, emit, depth - 1)
      test_observe_run(p1, emit, depth - 1)
    }
    OriginalResources(p0) => {
      emit(123)
      test_observe_arena(p0, emit, depth - 1)
    }
    OriginalResourceScopePending => emit(124)
    OriginalResourceLeave(p0, p1) => {
      emit(125)
      match p0 {
        Some(prior) => {
          emit(1)
          test_observe_adoption(prior, emit, depth - 1)
        }
        None => emit(2)
      }
      test_observe_arena(p1, emit, depth - 1)
    }
    InspectionCleanup(p0) => {
      emit(126)
      test_observe_journal(p0, emit, depth - 1)
    }
    InspectionPending(p0, p1, _) => {
      emit(127)
      match p0 {
        Some(prior) => {
          emit(1)
          test_observe_adoption(prior, emit, depth - 1)
        }
        None => emit(2)
      }
      test_observe_adoption(p1, emit, depth - 1)
    }
  }
}

///|
fn test_observe_custody(
  issue : NativeClientCustodyIssue,
  emit : (Int) -> Unit,
  depth : Int,
) -> Unit {
  if depth <= 0 {
    emit(9999)
    return
  }
  match issue {
    Epoch(p0) => {
      emit(200)
      test_observe_epoch(p0, emit, depth - 1)
    }
    Run(p0) => {
      emit(201)
      test_observe_run(p0, emit, depth - 1)
    }
    Submission(p0) => {
      emit(202)
      test_observe_run(p0, emit, depth - 1)
    }
  }
}

///|
fn test_observe_inspection(
  issue : NativeClientStateInspectionIssue,
  emit : (Int) -> Unit,
  depth : Int,
) -> Unit {
  if depth <= 0 {
    emit(9999)
    return
  }
  match issue {
    InvalidLimit => emit(300)
    Custody(p0) => {
      emit(301)
      test_observe_custody(p0, emit, depth - 1)
    }
    Inspection(p0, p1) => {
      emit(302)
      test_observe_journal(p0, emit, depth - 1)
      match p1 {
        Some(prior) => {
          emit(1)
          test_observe_custody(prior, emit, depth - 1)
        }
        None => emit(2)
      }
    }
  }
}

///|
fn test_observe_epoch(
  issue : NativeClientEpochIssue,
  emit : (Int) -> Unit,
  depth : Int,
) -> Unit {
  if depth <= 0 {
    emit(9999)
    return
  }
  match issue {
    InvalidInput => emit(400)
    Encoding => emit(401)
    AlreadyInitialized => emit(402)
    CustodyLost => emit(403)
    AuthorizationDenied => emit(404)
    Unverifiable => emit(405)
    ScopeMismatch => emit(406)
    Fenced => emit(407)
    TransactionUnknown => emit(408)
    Physical(p0) => {
      emit(409)
      test_observe_sql(p0, emit, depth - 1)
    }
    Crypto(p0) => {
      emit(410)
      test_observe_crypto(p0, emit, depth - 1)
    }
    Identity(_) => emit(411)
  }
}

///|
fn test_observe_run(
  issue : NativeClientRunJournalIssue,
  emit : (Int) -> Unit,
  depth : Int,
) -> Unit {
  if depth <= 0 {
    emit(9999)
    return
  }
  match issue {
    CustodyLost => emit(500)
    CapacityExceeded => emit(501)
    AuthorizationDenied => emit(502)
    ChangedIntent => emit(503)
    ForeignRun => emit(504)
    Fenced => emit(505)
    TransactionUnknown => emit(506)
    Encoding => emit(507)
    Physical(p0) => {
      emit(508)
      test_observe_sql(p0, emit, depth - 1)
    }
    Start(_) => emit(509)
    Epoch(p0) => {
      emit(510)
      test_observe_epoch(p0, emit, depth - 1)
    }
    InvalidSubmission => emit(511)
    SubmissionReferenceUsed => emit(512)
    NamedSubmission(_) => emit(513)
    SubmissionEpochRejected(_) => emit(514)
    UnsupportedPreparation => emit(515)
    MissingEffectMaterialOriginal => emit(516)
    ChangedEffectMaterialOriginal => emit(517)
    PublicationPolicy(_) => emit(518)
    Checkpoint(_) => emit(519)
    CancellationIdentity(_) => emit(520)
    CancellationOperation(_) => emit(521)
    PublicationObservation(_) => emit(522)
    RunIdIndexIncomplete => emit(523)
  }
}

///|
fn test_observe_journal(
  issue : @journal.NativeRemoteJournalIssue,
  emit : (Int) -> Unit,
  depth : Int,
) -> Unit {
  if depth <= 0 {
    emit(9999)
    return
  }
  match issue {
    UnsupportedTarget => emit(600)
    Closed => emit(601)
    CleanupPending => emit(602)
    Physical(p0) => {
      emit(603)
      test_observe_sql(p0, emit, depth - 1)
    }
    Protocol(_) => emit(604)
    StaleSiteBinding => emit(605)
    MissingDispatch => emit(606)
    StateCollision => emit(607)
    InitializationCleanupPending(p0, p1, _) => {
      emit(608)
      match p0 {
        Some(prior) => {
          emit(1)
          test_observe_journal(prior, emit, depth - 1)
        }
        None => emit(2)
      }
      test_observe_journal(p1, emit, depth - 1)
    }
  }
}

///|
fn test_observe_arena(
  issue : @arena.InstalledArenaLocalHostResourcesIssue,
  emit : (Int) -> Unit,
  depth : Int,
) -> Unit {
  if depth <= 0 {
    emit(9999)
    return
  }
  match issue {
    Read(p0) => {
      emit(700)
      test_observe_read(p0, emit, depth - 1)
    }
    Sqlite(p0) => {
      emit(701)
      test_observe_sqlite_library(p0, emit, depth - 1)
    }
    Domain(p0) => {
      emit(702)
      test_observe_backed(p0, emit, depth - 1)
    }
  }
}

///|
fn test_observe_read(
  issue : @arena.InstalledArenaOriginalReadIssue,
  emit : (Int) -> Unit,
  depth : Int,
) -> Unit {
  if depth <= 0 {
    emit(9999)
    return
  }
  match issue {
    Domain(p0) => {
      emit(800)
      test_observe_backed(p0, emit, depth - 1)
    }
    Child(p0) => {
      emit(801)
      test_observe_child(p0, emit, depth - 1)
    }
    Read(p0) => {
      emit(802)
      test_observe_original_read(p0, emit, depth - 1)
    }
    Buffer(_) => emit(803)
  }
}

///|
fn test_observe_sqlite_library(
  issue : @arena.InstalledArenaSqliteIssue,
  emit : (Int) -> Unit,
  depth : Int,
) -> Unit {
  if depth <= 0 {
    emit(9999)
    return
  }
  match issue {
    Domain(p0) => {
      emit(900)
      test_observe_backed(p0, emit, depth - 1)
    }
    Library(p0) => {
      emit(901)
      test_observe_sql(p0, emit, depth - 1)
    }
  }
}

///|
fn test_observe_backed(
  issue : @bootstrap.NativeBackedExecutionIssue,
  emit : (Int) -> Unit,
  depth : Int,
) -> Unit {
  if depth <= 0 {
    emit(9999)
    return
  }
  match issue {
    Bootstrap(p0) => {
      emit(1000)
      test_observe_bootstrap(p0, emit, depth - 1)
    }
    Accounting(p0) => {
      emit(1001)
      test_observe_accounting(p0, emit, depth - 1)
    }
  }
}

///|
fn test_observe_bootstrap(
  issue : @bootstrap.NativeBootstrapIssue,
  emit : (Int) -> Unit,
  depth : Int,
) -> Unit {
  if depth <= 0 {
    emit(9999)
    return
  }
  match issue {
    Unavailable => emit(1100)
    ForeignOriginal => emit(1101)
    AlreadyConsumed => emit(1102)
    Closing => emit(1103)
    ReadersPending => emit(1104)
    Physical(p0) => {
      emit(1105)
      emit(p0)
    }
    Resource(p0) => {
      emit(1106)
      test_observe_ledger(p0, emit, depth - 1)
    }
  }
}

///|
fn test_observe_sql(
  issue : @sqlite.NativeSqliteIssue,
  emit : (Int) -> Unit,
  depth : Int,
) -> Unit {
  if depth <= 0 {
    emit(9999)
    return
  }
  match issue {
    UnsupportedTarget => emit(1200)
    InvalidName => emit(1201)
    InvalidLimit => emit(1202)
    LibraryLoad(_) => emit(1203)
    DatabaseOpen(_) => emit(1204)
    DatabaseClosed => emit(1205)
    NotFound => emit(1206)
    Collision => emit(1207)
    Busy => emit(1208)
    BodyTooLarge => emit(1209)
    CapacityExceeded => emit(1210)
    Physical(_) => emit(1211)
    OperationRoutingBefore(_) => emit(1212)
    OperationRoutingAfter(primary, _) => {
      emit(1213)
      if primary is Some(original) {
        test_observe_sql(original, emit, depth - 1)
      }
    }
  }
}

///|
fn test_observe_fs(
  issue : @filesystem.NativeFilesystemIssue,
  emit : (Int) -> Unit,
  depth : Int,
) -> Unit {
  if depth <= 0 {
    emit(9999)
    return
  }
  match issue {
    UnsupportedTarget => emit(1300)
    InvalidName => emit(1301)
    InvalidLimit => emit(1302)
    RootOpen(_) => emit(1303)
    Lock(_) => emit(1304)
    WriterCreate(_) => emit(1305)
    CapacityExceeded => emit(1306)
    WriterClosed => emit(1307)
    Write(_) => emit(1308)
    Conflict => emit(1309)
    GenerationMismatch => emit(1310)
    InvalidReadSize => emit(1311)
    IncompleteRead => emit(1312)
    ReaderClosed => emit(1313)
    Read(_) => emit(1314)
    Seal(_) => emit(1315)
    Cleanup(_) => emit(1316)
  }
}

///|
fn test_observe_crypto(
  issue : @crypto.NativeSignatureIssue,
  emit : (Int) -> Unit,
  depth : Int,
) -> Unit {
  if depth <= 0 {
    emit(9999)
    return
  }
  match issue {
    UnsupportedTarget => emit(1400)
    InvalidInput => emit(1401)
    LibraryLoad(_) => emit(1402)
    InvalidPublicKey(_) => emit(1403)
    InvalidPrivateKey(_) => emit(1404)
    UnsupportedKey(_) => emit(1405)
    Verification(_) => emit(1406)
    Signing(_) => emit(1407)
    CleanupPending => emit(1408)
    CloseUnconfirmed(_) => emit(1409)
  }
}

///|
fn test_observe_accounting(
  issue : @resources.BackedExecutionIssue,
  emit : (Int) -> Unit,
  depth : Int,
) -> Unit {
  if depth <= 0 {
    emit(9999)
    return
  }
  match issue {
    ForeignOriginal => emit(1500)
    InvalidExtent => emit(1501)
    ExtentConflict => emit(1502)
    DuplicateChild => emit(1503)
    RegionClosing => emit(1504)
    Retired => emit(1505)
    CleanupPending => emit(1506)
    ChangedFinalUsage => emit(1507)
    ReadUseAlreadyIssued => emit(1508)
    LiveAccessAlreadyIssued => emit(1509)
    LiveChildAlreadyAdmitted => emit(1510)
    Resource(p0) => {
      emit(1511)
      test_observe_ledger(p0, emit, depth - 1)
    }
  }
}

///|
fn test_observe_child(
  issue : @resources.ImportedChildLedgerIssue,
  emit : (Int) -> Unit,
  depth : Int,
) -> Unit {
  if depth <= 0 {
    emit(9999)
    return
  }
  match issue {
    Unavailable => emit(1600)
    Unknown => emit(1601)
    ForeignOriginal => emit(1602)
    AlreadyConsumed => emit(1603)
    InvalidOriginal => emit(1604)
    Resource(p0) => {
      emit(1605)
      test_observe_ledger(p0, emit, depth - 1)
    }
  }
}

///|
fn test_observe_original_read(
  issue : @resources.OriginalReadIssue,
  emit : (Int) -> Unit,
  depth : Int,
) -> Unit {
  if depth <= 0 {
    emit(9999)
    return
  }
  match issue {
    InvalidBootstrap => emit(1700)
    IncompleteInventory => emit(1701)
    ForeignOrigin => emit(1702)
    ChangedOriginalState => emit(1703)
    SpentClaim => emit(1704)
    CleanupPending => emit(1705)
    Resource(p0) => {
      emit(1706)
      test_observe_ledger(p0, emit, depth - 1)
    }
  }
}

///|
fn test_observe_ledger(
  issue : @resources.LedgerIssue,
  emit : (Int) -> Unit,
  depth : Int,
) -> Unit {
  if depth <= 0 {
    emit(9999)
    return
  }
  match issue {
    InvalidLimits => emit(1800)
    PlanningLimit => emit(1801)
    AttemptLimit => emit(1802)
    HoldingLimit => emit(1803)
    TransferLimit => emit(1804)
    RetentionLimit => emit(1805)
    ExecutionLimit => emit(1806)
    ForeignOwner => emit(1807)
    ClosedReservation => emit(1808)
    ClosedHolding => emit(1809)
    InvalidCharge => emit(1810)
    TokenLimit => emit(1811)
    CostLimit => emit(1812)
    DurationLimit => emit(1813)
    ResourceParked => emit(1814)
    ChildFundingUnavailable => emit(1815)
    IdentityOverflow => emit(1816)
  }
}

///|
fn test_observe_journal_reply(
  reply : NativeLocalJournalCaptureReply,
  emit : (Int) -> Unit,
) -> Unit {
  match reply.issue() {
    None => emit(3)
    Some(JournalNotOpened) => emit(4)
    Some(JournalOpeningUnconfirmed) => emit(5)
    Some(JournalCaptureClosed) => emit(6)
    Some(JournalAdoption(issue)) => test_observe_adoption(issue, emit, 32)
  }
}

// End of test-only observer helpers.

///|
test "test-only original issue observer keeps phase and transaction causes" {
  let _observer = test_observe_journal_reply
  let tags : Array[Int] = []
  test_observe_adoption(
    InstallationReadTransactionFailure(
      OriginalResourceLeave(
        Some(CustodyLost),
        @arena.Domain(@bootstrap.Bootstrap(@bootstrap.Physical(-41))),
      ),
      TransactionUnknown,
    ),
    tag => tags.push(tag),
    32,
  )
  assert_eq(tags, [122, 125, 1, 105, 702, 1000, 1105, -41, 506])
}

///|
test "test-only original issue observer never renders private SQL diagnostics" {
  let first : Array[Int] = []
  let second : Array[Int] = []
  test_observe_adoption(
    Physical(@sqlite.DatabaseOpen("private-path-and-key-A")),
    tag => first.push(tag),
    32,
  )
  test_observe_adoption(
    Physical(@sqlite.DatabaseOpen("different-private-value-B")),
    tag => second.push(tag),
    32,
  )
  assert_eq(first, second)
  assert_eq(first, [115, 1204])
  let bounded : Array[Int] = []
  test_observe_adoption(CustodyLost, tag => bounded.push(tag), 0)
  assert_eq(bounded, [9999])
}
