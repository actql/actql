///|
let publication_binding_adoption : Bytes = b"{\"configuration_custody_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"device\":\"7\",\"inode\":\"9\",\"intent_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"version\":\"actql-native-local-journal-custody/0.1\"}"

///|
let publication_binding_account_wire : String =
  #|{"version":"actql-execution-account-config/0.1","account_id":"local-account","entries":[{"entry_id":"publish","outcome":"allow","principal":{"all":true},"connection":{"any_of":["python.local"]},"resource":{"any_of":["run"]},"operation":{"any_of":["publish"]},"exclusions":[]},{"entry_id":"submit","outcome":"allow","principal":{"all":true},"connection":{"any_of":["python.local"]},"resource":{"any_of":["runs"]},"operation":{"any_of":["submit"]},"exclusions":[]}]}

///|
fn publication_binding_fixture(
  text? : String = "SELECT 1 AS n",
  publish? : Bool = true,
  finite? : Bool = false,
) -> (
  LocalRunPlan,
  @input.LocalSubmittedPreparation,
  LocalSubmittedRunRows,
  @host.ClientJournalPhysicalRow,
  @host.ClientJournalPhysicalRow,
  Ref[Int],
  @host.ClientLocalAdoptedHostMaterial[Ref[Int], String],
  Ref[@host.ClientLocalAdoptionCurrentObservation[Ref[Int]]],
) {
  let preparation = submitted_rows_preparation(text)
  let account_wire = if publish {
    publication_binding_account_wire
  } else {
    publication_binding_account_wire.replace(
      old="\"entry_id\":\"publish\",\"outcome\":\"allow\"",
      new="\"entry_id\":\"publish\",\"outcome\":\"deny\"",
    )
  }
  let account = @authorization.admit_account_configuration_json(account_wire).unwrap()
  let store = Ref(0)
  let observation : @host.ClientLocalAdoptionCurrentObservation[Ref[Int]] = @host.Observed(
    store,
    account,
    @utf8.encode(account_wire),
    { key: "adoption", revision: 0L, body: publication_binding_adoption, },
    (7UL, 9UL),
  )
  let current = Ref(observation)
  let material : @host.ClientLocalAdoptedHostMaterial[Ref[Int], String] = @host.bind_client_local_adopted_host_material(
    store,
    () => Ok(current.val),
  ).unwrap()
  let scope = "sha256:" +
    @sha.hex(
      @host.client_local_adopted_authority_scope_body(
        material,
        store,
        tuple().principal,
        tuple().connection,
      ).unwrap(),
    )
  let reference = @host.admit_client_submission_reference_record(
    submitted_rows_reference_wire.replace(
      old="sha256:" + "b".repeat(64),
      new=scope,
    ),
  ).unwrap()
  let input = @input.local_submitted_preparation_input(preparation)
  let plan = prepare_source_free_local_publication_run(
    input,
    scope,
    @host.client_submission_reference_record_request_id(reference),
    permit(input, account),
    account,
    tuple(),
    context_cid(),
    "sha256:" + "c".repeat(64),
    "local",
    "original-publication-run",
    if finite {
      "2026-10-13T00:00:00.001Z"
    } else {
      "2026-10-12T00:00:00.000Z"
    },
    if finite {
      "2026-10-14T00:00:00.001Z"
    } else {
      "2099-01-01T00:00:00.000Z"
    },
    (source_free_original_policy_cid, source_free_original_policy),
  ).unwrap()
  let finite_policy = if finite {
    let originals = @host.client_local_product_common_originals(
      "/private/local",
      "2026-10-12T00:00:00.000Z",
      @host.client_local_product_assets(),
    ).unwrap()
    let profile = @host.client_local_run_policy_profile(originals).unwrap()
    let at = "2026-10-13T00:00:00.001Z"
    Some(
      @host.bind_client_local_run_policy_original(
        profile,
        reference,
        plan.request,
        plan.definition,
        @host.issue_client_local_run_retention_policy(profile, at).unwrap(),
        at,
        "sha256:" + @sha.hex(publication_binding_adoption),
        "sha256:" + "f".repeat(64),
      ).unwrap(),
    )
  } else {
    None
  }
  let rows = prepare_local_submitted_run_rows(
    plan,
    preparation,
    reference,
    @host.client_submitted_intent_journal_row_body(
      @host.client_submission_reference_record_wire(reference),
      @input.local_submitted_preparation_intent(preparation),
    ).unwrap(),
    permit(input, account),
    account,
    tuple(),
    context_cid(),
    1000.0,
    local_policy_original=finite_policy,
  ).unwrap()
  let (run_key, submitted_key, _, run, submitted) = local_submitted_run_rows(
    rows, plan, preparation,
  ).unwrap()
  (
    plan,
    preparation,
    rows,
    { key: run_key, revision: 0L, body: run, },
    { key: submitted_key, revision: 0L, body: submitted, },
    store,
    material,
    current,
  )
}

///|
fn publication_binding_prepare(
  plan : LocalRunPlan,
  preparation : @input.LocalSubmittedPreparation,
  rows : LocalSubmittedRunRows,
  run : @host.ClientJournalPhysicalRow,
  submitted : @host.ClientJournalPhysicalRow,
  store : Ref[Int],
  material : @host.ClientLocalAdoptedHostMaterial[Ref[Int], String],
) -> Result[
  LocalRunPublicationBindingPlan[Ref[Int], String],
  LocalRunPublicationBindingIssue[String],
] {
  prepare_local_run_publication_binding(
    plan,
    rows,
    preparation,
    material,
    store,
    "local",
    "sha256:" + "d".repeat(64),
    21UL,
    29UL,
    run,
    submitted,
  )
}

///|
test "original publication binding projects only the same Run CAS and exact policy bytes" {
  let (plan, preparation, rows, run, submitted, store, material, _) = publication_binding_fixture()
  guard publication_binding_prepare(
      plan, preparation, rows, run, submitted, store, material,
    )
    is Ok(Append(step)) else {
    fail("Missing original publication binding candidate")
  }
  let (key, revision, body) = local_run_publication_binding_rows(step)
  assert_eq(key, run.key)
  assert_eq(revision, 0L)
  let (actual, policy) = @host.decode_client_run_journal_row_with_local_policy(
    body,
  ).unwrap()
  let (prior, prior_policy) = @host.decode_client_run_journal_row_with_local_policy(
    run.body,
  ).unwrap()
  assert_eq(
    actual.publication_binding,
    Some("[\"local\",\"sha256:" + "d".repeat(64) + "\",\"21\",\"29\"]"),
  )
  assert_eq(
    actual.publication_policy_originals,
    Some(
      @host.issue_client_run_policy_originals(
        plan.prepared,
        compiled=plan.compiled,
      ).unwrap(),
    ),
  )
  assert_eq(policy, prior_policy)
  assert_true(
    @host.client_request_identity_relation(actual.request, prior.request)
    is @host.SameRequest,
  )
  assert_eq(
    @publication.publication_contract_json(actual.definition),
    @publication.publication_contract_json(prior.definition),
  )
  assert_false(
    actual.dispatch_reserved ||
    actual.physical_start_claimed ||
    actual.cancellation_requested,
  )
  assert_true(
    validate_local_run_publication_binding(step, run, submitted) is Ok(_),
  )
  assert_true(
    confirm_local_run_publication_binding(step, run, submitted)
    is Err(CustodyLost),
  )
  let saved = { ..run, revision: 1L, body, }
  let confirmed = confirm_local_run_publication_binding(step, saved, submitted).unwrap()
  assert_true(physical_equal(confirmed.plan, plan))
  assert_true(
    publication_binding_prepare(
      plan, preparation, rows, saved, submitted, store, material,
    )
    is Ok(Retained(_)),
  )
}

///|
test "submit permission does not supply the independent publication permission" {
  let (plan, preparation, rows, run, submitted, store, material, _) = publication_binding_fixture(
    publish=false,
  )
  assert_true(
    publication_binding_prepare(
      plan, preparation, rows, run, submitted, store, material,
    )
    is Err(AuthorizationMismatch),
  )
}

///|
test "foreign original Store and changed adoption do not issue or confirm a CAS" {
  let (plan, preparation, rows, run, submitted, store, material, current) = publication_binding_fixture()
  assert_true(
    publication_binding_prepare(
      plan,
      preparation,
      rows,
      run,
      submitted,
      Ref(0),
      material,
    )
    is Err(Current(@host.ForeignStore)),
  )
  let step = match
    publication_binding_prepare(
      plan, preparation, rows, run, submitted, store, material,
    ).unwrap() {
    Append(value) => value
    _ => fail("Missing original candidate")
  }
  current.val = @host.CommitUnknown
  assert_true(
    validate_local_run_publication_binding(step, run, submitted)
    is Err(Current(@host.CommitUnknown)),
  )
  let (_, _, body) = local_run_publication_binding_rows(step)
  assert_true(
    confirm_local_run_publication_binding(
      step,
      { ..run, revision: 1L, body, },
      submitted,
    )
    is Err(Current(@host.CommitUnknown)),
  )
}

///|
test "foreign rows preparation revisions and changed policy cannot confirm the original" {
  let (plan, preparation, rows, run, submitted, store, material, _) = publication_binding_fixture()
  let (foreign_plan, foreign_preparation, _, _, _, _, _, _) = publication_binding_fixture(
    text="SELECT 2 AS n",
  )
  assert_true(
    publication_binding_prepare(
      foreign_plan, preparation, rows, run, submitted, store, material,
    )
    is Err(ForeignPreparation),
  )
  assert_true(
    publication_binding_prepare(
      plan, foreign_preparation, rows, run, submitted, store, material,
    )
    is Err(ForeignPreparation),
  )
  let step = match
    publication_binding_prepare(
      plan, preparation, rows, run, submitted, store, material,
    ).unwrap() {
    Append(value) => value
    _ => fail("Missing original candidate")
  }
  let (_, _, body) = local_run_publication_binding_rows(step)
  for
    observed in [
      { ..run, revision: 2L, body, },
      { ..run, revision: 1L, body: run.body, },
      { key: "foreign", revision: 1L, body, },
    ] {
    assert_true(
      confirm_local_run_publication_binding(step, observed, submitted)
      is Err(CustodyLost),
    )
  }
  assert_true(
    validate_local_run_publication_binding(
      step,
      { ..run, revision: 1L, },
      submitted,
    )
    is Err(CustodyLost),
  )
}

///|
test "started Run cannot recreate missing publication originals or renew finite policy" {
  let (plan, preparation, rows, run, submitted, store, material, _) = publication_binding_fixture()
  let (encoding, policy) = @host.decode_client_run_journal_row_with_local_policy(
    run.body,
  ).unwrap()
  for
    changed in [
      { ..encoding, dispatch_reserved: true, },
      { ..encoding, dispatch_reserved: true, physical_start_claimed: true, },
    ] {
    let body = @host.client_run_journal_row_body(
      changed,
      local_run_policy_originals=policy,
    ).unwrap()
    assert_true(
      publication_binding_prepare(
        plan,
        preparation,
        rows,
        { ..run, revision: 2L, body, },
        submitted,
        store,
        material,
      )
      is Err(MissingOriginal),
    )
  }
}

///|
test "original publication binding refuses cancelled Run and a substituted Store binding" {
  let (plan, preparation, rows, run, submitted, store, material, _) = publication_binding_fixture()
  let (encoding, policy) = @host.decode_client_run_journal_row_with_local_policy(
    run.body,
  ).unwrap()
  for
    changed in [
      { ..encoding, cancellation_requested: true, },
      { ..encoding, publication_binding: Some("foreign-Store"), },
      { ..encoding, publication_policy_originals: Some("{}"), },
    ] {
    let body = @host.client_run_journal_row_body(
      changed,
      local_run_policy_originals=policy,
    ).unwrap()
    assert_true(
      publication_binding_prepare(
        plan,
        preparation,
        rows,
        { ..run, body, },
        submitted,
        store,
        material,
      )
      is Err(CustodyLost),
    )
  }
}

///|
test "confirmed originals remain exact across start revisions without repairing lost policy" {
  let (plan, preparation, rows, run, submitted, store, material, current) = publication_binding_fixture()
  let step = match
    publication_binding_prepare(
      plan, preparation, rows, run, submitted, store, material,
    ).unwrap() {
    Append(value) => value
    _ => fail("Missing original candidate")
  }
  let (_, _, body) = local_run_publication_binding_rows(step)
  let saved = { ..run, revision: 1L, body, }
  let original = confirm_local_run_publication_binding(step, saved, submitted).unwrap()
  let (encoding, policy) = @host.decode_client_run_journal_row_with_local_policy(
    body,
  ).unwrap()
  let started = {
    ..encoding,
    dispatch_reserved: true,
    physical_start_claimed: true,
  }
  let started_body = @host.client_run_journal_row_body(
    started,
    local_run_policy_originals=policy,
  ).unwrap()
  let started_row = { ..run, revision: 3L, body: started_body, }
  assert_true(
    validate_local_run_publication_binding_original(
      original, started_row, submitted,
    )
    is Ok(_),
  )
  let missing = @host.client_run_journal_row_body(
    { ..started, publication_policy_originals: None, },
    local_run_policy_originals=policy,
  ).unwrap()
  assert_true(
    validate_local_run_publication_binding_original(
      original,
      { ..started_row, body: missing, },
      submitted,
    )
    is Err(MissingOriginal),
  )
  current.val = @host.NotAdopted
  assert_true(
    validate_local_run_publication_binding_original(
      original, started_row, submitted,
    )
    is Err(Current(@host.NotAdopted)),
  )
}

///|
test "publication CAS preserves the exact finite packet and original issued time" {
  let (plan, preparation, rows, run, submitted, store, material, _) = publication_binding_fixture(
    finite=true,
  )
  let step = match
    publication_binding_prepare(
      plan, preparation, rows, run, submitted, store, material,
    ).unwrap() {
    Append(value) => value
    _ => fail("Missing original finite candidate")
  }
  let (_, _, body) = local_run_publication_binding_rows(step)
  let (_, before) = @host.decode_client_run_journal_row_with_local_policy(
    run.body,
  ).unwrap()
  let (_, after) = @host.decode_client_run_journal_row_with_local_policy(body).unwrap()
  assert_true(before is Some(_))
  assert_eq(after, before)
  assert_true(
    validate_local_run_publication_binding(step, run, submitted) is Ok(_),
  )
  let original = confirm_local_run_publication_binding(
    step,
    { ..run, revision: 1L, body, },
    submitted,
  ).unwrap()
  assert_true(
    validate_local_run_publication_binding_original(
      original,
      { ..run, revision: 1L, body, },
      submitted,
    )
    is Ok(_),
  )
  let renewed = @utf8.encode(
    @utf8.decode(body).replace(
      old="2026-10-13T00:00:00.001Z",
      new="2026-10-13T00:00:00.002Z",
    ),
  )
  assert_true(
    confirm_local_run_publication_binding(
      step,
      { ..run, revision: 1L, body: renewed, },
      submitted,
    )
    is Err(CustodyLost),
  )
}

///|
test "publication binding candidate preserves existing selector bounds before encoding" {
  let (plan, preparation, rows, run, submitted, store, material, _) = publication_binding_fixture()
  for
    (namespace_id, target) in [
      ("", "sha256:" + "d".repeat(64)),
      ("x".repeat(129), "sha256:" + "d".repeat(64)),
      ("local", "sha256:" + "D".repeat(64)),
      ("local", "raw-target"),
    ] {
    assert_true(
      prepare_local_run_publication_binding(
        plan, rows, preparation, material, store, namespace_id, target, 21UL, 29UL,
        run, submitted,
      )
      is Err(CustodyLost),
    )
  }
}
