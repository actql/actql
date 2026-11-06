///|
// Test-only phase/variant metadata. No original values or error payloads escape.
struct JournalTestFixtureIssue {
  phase : String
  kind : String
}

///|
fn journal_test_run(
  request_id : String,
  run_id : String,
  scope? : String = "sha256:" + "a".repeat(64),
) -> (
  @host.ClientRequestIdentity,
  @host.PreparedClientProgram,
  @host.ClientCompiledRun,
  @publication.PublicationContract,
) {
  journal_test_run_result(request_id, run_id, scope~).unwrap()
}

///|
fn journal_test_prepared_run(
  prepared : @host.PreparedClientProgram,
  request_id : String,
  run_id : String,
  scope? : String = "sha256:" + "a".repeat(64),
) -> (
  @host.ClientRequestIdentity,
  @host.PreparedClientProgram,
  @host.ClientCompiledRun,
  @publication.PublicationContract,
) {
  journal_test_prepared_run_result(prepared, request_id, run_id, scope~).unwrap()
}

///|
fn[T] journal_test_fixture_require(
  value : Result[T, JournalTestFixtureIssue],
) -> T raise {
  match value {
    Ok(original) => original
    Err(issue) => fail("fixture phase=" + issue.phase + " issue=" + issue.kind)
  }
}

///|
fn journal_test_run_result(
  request_id : String,
  run_id : String,
  scope? : String = "sha256:" + "a".repeat(64),
) -> Result[
  (
    @host.ClientRequestIdentity,
    @host.PreparedClientProgram,
    @host.ClientCompiledRun,
    @publication.PublicationContract,
  ),
  JournalTestFixtureIssue,
] {
  let environment = match preparation_environment_original() {
    Some(value) => value
    None => return Err({ phase: "prepare_environment", kind: "Unavailable", })
  }
  let prepared = match
    @host.prepare_effect_free_client_program(
      preparation_values_document(),
      Json,
      environment,
      None,
      @host.client_standard_program_preparation_limits(),
    ) {
    Ok(value) => value
    Err(issue) =>
      return Err({
        phase: "prepare",
        kind: journal_test_preparation_issue(issue),
      })
  }
  journal_test_prepared_run_result(prepared, request_id, run_id, scope~)
}

///|
fn journal_test_prepared_run_result(
  prepared : @host.PreparedClientProgram,
  request_id : String,
  run_id : String,
  scope? : String = "sha256:" + "a".repeat(64),
) -> Result[
  (
    @host.ClientRequestIdentity,
    @host.PreparedClientProgram,
    @host.ClientCompiledRun,
    @publication.PublicationContract,
  ),
  JournalTestFixtureIssue,
] {
  let manifests = match
    @host.admit_client_compilation_manifests(
      @environment.compiler_grammar_manifest_wire(),
      @environment.compiler_barrier_contract_manifest_wire(),
      10000,
      1000,
      20,
    ) {
    Ok(value) => value
    Err(issue) =>
      return Err({
        phase: "manifest",
        kind: journal_test_manifest_issue(issue),
      })
  }
  let compilation = match
    @host.issue_prepared_client_values_compilation(
      prepared,
      manifests,
      {
        max_steps: 10,
        max_rows: 10,
        max_cells: 10,
        max_bindings: 10,
        max_name_bytes: 1000,
        expressions: {
          max_nodes: 100,
          max_work: 1000,
          max_depth: 10,
          max_literal_nodes: 100,
          max_literal_text_bytes: 1000,
        },
      },
      32,
      64,
      100000,
      10000,
      100,
    ) {
    Ok(value) => value
    Err(issue) =>
      return Err({
        phase: "compilation",
        kind: journal_test_compilation_issue(issue),
      })
  }
  let compiled = match
    @host.issue_client_values_compiled_run(
      prepared,
      compilation,
      scope,
      "sha256:" + "b".repeat(64),
      "2099-01-01T00:00:00.000Z",
    ) {
    Ok(value) => value
    Err(issue) =>
      return Err({
        phase: "compiled_run",
        kind: journal_test_compiled_issue(issue),
      })
  }
  let definition = match
    @host.issue_client_compiled_run_definition(
      compiled, "local-test", run_id, "2026-10-10T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
    ) {
    Ok(value) => value
    Err(issue) =>
      return Err({
        phase: "definition",
        kind: journal_test_compiled_issue(issue),
      })
  }
  let request = match
    @host.prepare_source_free_client_request_identity(
      prepared, scope, request_id,
    ) {
    Ok(value) => value
    Err(issue) =>
      return Err({ phase: "request", kind: journal_test_request_issue(issue), })
  }
  Ok((request, prepared, compiled, definition))
}

///|
fn journal_test_preparation_issue(
  issue : @host.ClientProgramPreparationIssue,
) -> String {
  match issue {
    Syntax(_) => "Syntax"
    EffectNotSupported(_) => "EffectNotSupported"
    NeedsInputs(_) => "NeedsInputs"
    Check(_) => "Check"
    MissingCheckedStage(_) => "MissingCheckedStage"
    MissingStageIdentity(_) => "MissingStageIdentity"
    Lowering(_) => "Lowering"
    Binding(_) => "Binding"
    Graph(_) => "Graph"
    ValuesProfileUnsupported => "ValuesProfileUnsupported"
  }
}

///|
fn journal_test_manifest_issue(
  issue : @host.ClientCompilationManifestIssue,
) -> String {
  match issue {
    InvalidBudget => "InvalidBudget"
    InvalidGrammarManifest => "InvalidGrammarManifest"
    InvalidBarrierManifest => "InvalidBarrierManifest"
    GrammarManifestMismatch => "GrammarManifestMismatch"
    BarrierManifestMismatch => "BarrierManifestMismatch"
  }
}

///|
fn journal_test_compilation_issue(
  issue : @host.ClientValuesCompilationIssue,
) -> String {
  match issue {
    Plan(_) => "Plan"
    Material(_) => "Material"
    AoA(_) => "AoA"
    Fragment(_) => "Fragment"
    Template(_) => "Template"
    CompiledPlan(_) => "CompiledPlan"
  }
}

///|
fn journal_test_compiled_issue(issue : @host.ClientCompiledRunIssue) -> String {
  match issue {
    ForeignOwner => "ForeignOwner"
    MissingResultPolicy => "MissingResultPolicy"
    InvalidResultPolicy => "InvalidResultPolicy"
    Policy(_) => "Policy"
    Admission(_) => "Admission"
    Contract(_) => "Contract"
    ValuesBinding(_) => "ValuesBinding"
    TaskBinding(_) => "TaskBinding"
    EffectBinding(_) => "EffectBinding"
  }
}

///|
fn journal_test_request_issue(
  issue : @host.ClientRequestIdentityIssue,
) -> String {
  match issue {
    InvalidAuthorityScope => "InvalidAuthorityScope"
    InvalidRequestId => "InvalidRequestId"
    InvalidInputIntent => "InvalidInputIntent"
    InvalidCheckedIdentity => "InvalidCheckedIdentity"
    IdentityMismatch => "IdentityMismatch"
    Encoding => "Encoding"
  }
}

///|
test "Native Run journal commits exact binding and start claim only once across reopen" {
  let database = epoch_test_database("client-runs-reopen")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "request-one", "run-one",
  )
  assert_true(journal.lookup(request, true) is Ok(UnresolvedHistory))
  assert_true(journal.lookup(request, false) is Err(AuthorizationDenied))
  let bound = journal
    .bind_run(request, prepared, compiled, definition, true)
    .unwrap()
  assert_eq(
    @publication.publication_contract_identity(
      native_client_run_definition(bound),
    ),
    @publication.publication_contract_identity(definition),
  )
  assert_eq(
    journal.bind_run(request, prepared, compiled, definition, true).unwrap().revision,
    bound.revision,
  )
  assert_false(journal.claim_physical_start(request, true).unwrap())
  assert_eq(
    journal.reserve_dispatch(request, true).unwrap(),
    @host.ReserveDispatch,
  )
  assert_eq(
    journal.reserve_dispatch(request, true).unwrap(),
    @host.ReconcileReservedDispatch,
  )
  database.close_checked().unwrap()
  let reopened = epoch_test_database("client-runs-reopen")
  let journal = open_native_client_run_journal(reopened, 8).unwrap()
  assert_true(
    journal.claim_physical_start(request, false) is Err(AuthorizationDenied),
  )
  assert_true(journal.claim_physical_start(request, true).unwrap())
  reopened.close_checked().unwrap()
  let reopened = epoch_test_database("client-runs-reopen")
  let journal = open_native_client_run_journal(reopened, 8).unwrap()
  assert_false(journal.claim_physical_start(request, true).unwrap())
  guard journal.lookup(request, true) is Ok(Retained(record)) else {
    fail("original binding lost")
  }
  assert_eq(
    @publication.publication_contract_identity(record.definition),
    @publication.publication_contract_identity(definition),
  )
  assert_true(record.physical_start_claimed)
  reopened.close_checked().unwrap()
}

///|
test "Native Run journal refuses changed intent foreign Run and finite-capacity overflow" {
  let database = epoch_test_database("client-runs-refused")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 2).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "request-one", "run-one",
  )
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  let (same_request, _, _, other_definition) = journal_test_run(
    "request-one", "run-two",
  )
  assert_true(
    journal.bind_run(same_request, prepared, compiled, other_definition, true)
    is Err(ForeignRun),
  )
  let changed = @host.prepare_effect_free_client_program(
    preparation_values_document().replace(old="{\"id\":1}", new="{\"id\":3}"),
    Json,
    preparation_environment(),
    None,
    @host.client_standard_program_preparation_limits(),
  ).unwrap()
  let changed_request = @host.prepare_source_free_client_request_identity(
    changed,
    "sha256:" + "a".repeat(64),
    "request-one",
  ).unwrap()
  assert_true(journal.lookup(changed_request, true) is Err(ChangedIntent))
  assert_true(
    journal.reserve_dispatch(changed_request, true) is Err(ChangedIntent),
  )
  assert_true(
    journal.claim_physical_start(changed_request, true) is Err(ChangedIntent),
  )
  assert_true(
    journal.bind_run(changed_request, changed, compiled, definition, true)
    is Err(ChangedIntent),
  )
  let (second_request, _, _, second_definition) = journal_test_run(
    "request-two", "run-two",
  )
  assert_true(
    journal.bind_run(second_request, prepared, compiled, definition, true)
    is Err(ForeignRun),
  )
  journal
  .bind_run(second_request, prepared, compiled, second_definition, true)
  .unwrap()
  |> ignore
  let (third_request, _, _, third_definition) = journal_test_run(
    "request-three", "run-three",
  )
  assert_true(
    journal.bind_run(third_request, prepared, compiled, third_definition, true)
    is Err(CapacityExceeded),
  )
  database.close_checked().unwrap()
}

///|
test "Native Run journal refuses lost issuance custody instead of inventing fresh history" {
  let database = epoch_test_database("client-runs-custody")
  assert_true(open_native_client_run_journal(database, 8) is Err(CustodyLost))
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "request-one", "run-one",
  )
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  let retained = database.read("client_run_custody", "issued").unwrap()
  database
  .compare_exchange("client_run_custody", "issued", retained.revision, b"0")
  .unwrap()
  |> ignore
  assert_true(journal.lookup(request, true) is Err(CustodyLost))
  assert_true(journal.claim_physical_start(request, true) is Err(CustodyLost))
  assert_true(open_native_client_run_journal(database, 8) is Err(CustodyLost))
  assert_true(
    journal.transaction(() => {
      initialize_native_client_run_journal_rows(database)
    })
    is Err(CustodyLost),
  )
  database.close_checked().unwrap()
}
