///|
let installed_host_subject_account : String =
  #|{"version":"actql-execution-account-config/0.1","account_id":"operator","entries":[{"entry_id":"current-machine-resolve","outcome":"allow","principal":{"any_of":["machine-user"]},"connection":{"any_of":["cli"]},"resource":{"any_of":["run"]},"operation":{"any_of":["resolve"]},"exclusions":[]},{"entry_id":"host-sign","outcome":"allow","principal":{"any_of":["host-machine"]},"connection":{"any_of":["host-cli"]},"resource":{"any_of":["key/initial-host-attestation"]},"operation":{"any_of":["sign"]},"exclusions":[]}]}

///|
fn installed_subject_reviewer(
  host : NativeLocalHostConnection,
  file : String,
) -> NativeLocalInstalledEffectReviewer {
  host
  .install_initial_effect_reviewer(
    host.restore_initial_signing_original().unwrap(),
    "machine-user",
    "cli",
    file,
  )
  .unwrap()
}

///|
test "installed Host signing subject restores exact actor and still requires actual Sign" {
  let (host, file) = initial_reviewer_fixture(
    "installed-host-subject",
    account=installed_host_subject_account,
    host_signing_subject=Some(
      ("host-machine", "host-cli", "key/initial-host-attestation"),
    ),
  )
  let original = host.restore_initial_host_signing_original().unwrap()
  assert_eq(
    original.signing_subject,
    Some(("host-machine", "host-cli", "key/initial-host-attestation")),
  )
  let installed = installed_subject_reviewer(host, file)
  let account = host.restore_initial_host_signing_account(installed).unwrap()
  assert_eq(
    (account.principal, account.connection, account.resource),
    ("host-machine", "host-cli", "key/initial-host-attestation"),
  )
  assert_true(account.require_current_account() is Ok(_))
  assert_true(
    host.acquire_initial_host_signing_account(
      original, installed, "machine-user", "cli", "key/initial-host-attestation",
    )
    is Err(SigningUnavailable),
  )
  assert_true(
    host.acquire_initial_host_signing_account(
      original, installed, "host-machine", "host-cli", "key/different",
    )
    is Err(SigningUnavailable),
  )
  assert_eq(host.installation_custody().unwrap(), (0, 0L))
  assert_true(
    host.database.scan_after("client_local_grant_originals", "")
    is Err(@sqlite.NotFound),
  )
  host.close().unwrap()
  assert_true(account.require_current_account() is Err(_))
}

///|
test "installed Host subject cannot supply missing Sign and legacy control cannot discover a role" {
  let subject = Some(
    ("host-machine", "host-cli", "key/initial-host-attestation"),
  )
  let (denied, file) = initial_reviewer_fixture(
    "installed-host-subject-denied",
    host_signing_subject=subject,
  )
  let installed = installed_subject_reviewer(denied, file)
  assert_true(
    denied.authorize({
      principal: "host-machine",
      connection: "host-cli",
      resource: "key/initial-host-attestation",
      operation: "sign",
    })
    is Ok(@authorization.Deny(_)),
  )
  assert_true(
    denied.restore_initial_host_signing_account(installed)
    is Err(SigningUnavailable),
  )
  denied.close().unwrap()
  let (legacy, file) = initial_reviewer_fixture(
    "installed-host-subject-legacy",
    account=installed_host_subject_account,
  )
  let original = legacy.restore_initial_host_signing_original().unwrap()
  assert_eq(original.signing_subject, None)
  let installed = installed_subject_reviewer(legacy, file)
  // Existing explicit trusted assembly can use its actual Allow, but the new
  // installed route cannot invent a role even when the same tuple is allowed.
  assert_true(
    legacy.acquire_initial_host_signing_account(
      original, installed, "host-machine", "host-cli", "key/initial-host-attestation",
    )
    is Ok(_),
  )
  assert_true(
    legacy.restore_initial_host_signing_account(installed)
    is Err(SigningUnavailable),
  )
  assert_eq(
    local_initial_signing_control_header(original.reviewer.control_body)
    .unwrap()
    .length(),
    3,
  )
  legacy.close().unwrap()
}

///|
test "installed Host subject cold restore preserves original role key epoch and authenticated context" {
  let name = "installed-host-subject-cold"
  let subject = ("host-machine", "host-cli", "key/initial-host-attestation")
  let (host, file) = initial_reviewer_fixture(
    name,
    account=installed_host_subject_account,
    host_signing_subject=Some(subject),
  )
  let original = host.restore_initial_host_signing_original().unwrap()
  let public_cid = original.public_key.cid()
  let generation = host.session.root
    .inspect_generation("local-host-attestation-key.pem")
    .unwrap()
  let control = original.reviewer.control_body
  assert_eq(local_initial_signing_control_header(control).unwrap().length(), 4)
  assert_true(control.length() <= 8192)
  let fields = read_local_initial_host_signing_control(host, control).unwrap()
  host.database.begin_immediate().unwrap()
  let foreign = initial_host_signing_subject_payload(
    "sha256:" + "f".repeat(64),
    fields.issuer,
    fields.policy.cid(),
    fields.public_key.cid(),
    subject,
  ).unwrap()
  let packet = local_installation_packet_in_transaction(
    host.database,
    host.epoch.crypto,
    foreign,
  ).unwrap()
  host.database.commit().unwrap()
  let header = local_initial_signing_control_header(control).unwrap()
  let changed = local_adoption_record([
    ("adoption_body", header[0]),
    ("initial_signing_original", header[1]),
    ("initial_host_attestation_original", header[2]),
    ("initial_host_signing_subject", @base64.encode(packet)),
  ]).unwrap()
  assert_true(
    read_initial_host_signing_subject(host, changed, fields) is Err(CustodyLost),
  )
  assert_true(original.require_current() is Ok(_))
  let top = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let crypto = host.epoch.crypto
  host.close().unwrap()
  let session = begin_native_local_host_adoption(
    top + "/" + name,
    "store",
    top + "/" + name,
    "account.json",
    "operator",
    crypto,
    configuration_files=["host.json"],
    existing_only=true,
  ).unwrap()
  assert_true(
    session.create_initial_signing_material(
      crypto,
      host_signing_subject=Some(("replacement", "replacement", "replacement")),
    )
    is Err(_),
  )
  let reopened = session
    .open_journal(local_journal_test_library(), crypto, 100.0, 8, 8388608L)
    .unwrap()
  let restored = reopened.restore_initial_host_signing_original().unwrap()
  assert_eq(restored.signing_subject, Some(subject))
  assert_eq(restored.public_key.cid(), public_cid)
  assert_eq(restored.reviewer.control_body, control)
  assert_eq(
    reopened.session.root
    .inspect_generation("local-host-attestation-key.pem")
    .unwrap(),
    generation,
  )
  assert_true(
    reopened.restore_initial_host_signing_account(
      installed_subject_reviewer(reopened, file),
    )
    is Ok(_),
  )
  reopened.close().unwrap()
}
