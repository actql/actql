import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';

// Execute the original Native caller methods with explicit typed dependency
// ports. This is caller retirement/order evidence, not Model, Resource,
// Journal, Native ABI or physical cleanup acceptance.
test('Native Model local observation retains partial exports before issuer retirement', {timeout: 90_000}, t => {
  const source = readFileSync(new URL('../src/platform_native/client_host/mock_model_observation.mbt', import.meta.url), 'utf8');
  const names = ['close_observation', 'prepare_local_observation',
    'advance_local_observation', 'local_observation_original'];
  const bodies = names.map(name => {
    const block = source.split('///|').find(value =>
      value.includes(`fn NativeClientMockModelWork::${name}(`));
    assert(block, `Missing original Native method ${name}`);
    return block;
  }).join('\n');
  const root = mkdtempSync(join(tmpdir(), 'actql-model-observation-order-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  for (const name of ['src', 'src/execution', 'src/publication', 'src/infer'])
    mkdirSync(join(root, name));
  writeFileSync(join(root, 'moon.mod'), 'name = "actql/model-observation-order-probe"\nsource = "src"\n');
  for (const name of ['execution', 'publication'])
    writeFileSync(join(root, `src/${name}/moon.pkg`), 'supported_targets = "js"\n');
  writeFileSync(join(root, 'src/moon.pkg'),
    'supported_targets = "js"\nimport { "actql/model-observation-order-probe/execution" @execution, "actql/model-observation-order-probe/infer" @infer, "actql/model-observation-order-probe/publication" @publication } for "wbtest"\n');
  writeFileSync(join(root, 'src/infer/moon.pkg'),
    'supported_targets = "js"\nimport { "actql/model-observation-order-probe/execution" @execution, "actql/model-observation-order-probe/publication" @publication }\n');
  writeFileSync(join(root, 'src/publication/ports.mbt'),
    'pub(all) struct CapturedEffectDependencyBody { marker : Int }\n');
  writeFileSync(join(root, 'src/execution/ports.mbt'), `
pub(all) enum Issue { Refused } derive(Eq, Debug)
pub(all) struct CompletedOutput { events : Array[String]; mode : Int }
pub(all) struct CompletedRelationIdentityScan { output : CompletedOutput }
pub(all) struct CompletedRelationExportReceipt { output : CompletedOutput }
pub fn start_completed_relation_identity_scan(output : CompletedOutput, _ : Int, _ : Unit, _ : Unit, _ : Unit, _ : Unit, _ : Int, _ : Int) -> Result[CompletedRelationIdentityScan, Issue] {
  output.events.push("start")
  if output.mode == 1 { Err(Refused) } else { Ok({output,}) }
}
pub fn advance_completed_relation_identity_scan(value : CompletedRelationIdentityScan, _ : Int) -> Result[(Bool, Int), Issue] {
  value.output.events.push("advance")
  if value.output.mode == 2 { Err(Refused) } else { Ok((true, 1)) }
}
pub fn finish_completed_relation_identity_scan(value : CompletedRelationIdentityScan) -> Result[CompletedRelationExportReceipt, Issue] {
  value.output.events.push("finish")
  if value.output.mode == 4 { Err(Refused) } else { Ok({output: value.output}) }
}
pub fn cancel_completed_relation_identity_scan(value : CompletedRelationIdentityScan) -> Bool { value.output.events.push("scan"); true }
pub fn cancel_completed_relation_export_receipt(value : CompletedRelationExportReceipt) -> Unit { value.output.events.push("receipt") }
`);
  writeFileSync(join(root, 'src/infer/ports.mbt'), `
pub(all) enum Issue { IdentityExport(@execution.Issue) } derive(Eq, Debug)
pub(all) struct Execution { output : @execution.CompletedOutput }
pub(all) struct OutputUse { owner : Execution; mut released : Bool }
pub(all) struct ObservationIssuance { events : Array[String]; mut pending : Bool; mut closed : Bool }
pub(all) struct OriginalModelPublicationCapacity { events : Array[String]; mut released : Bool }
pub(all) struct LocalModelObservation { held : OutputUse; issuer : ObservationIssuance }
pub fn observation_issuance_value(value : ObservationIssuance) -> Unit? { if value.closed { None } else { Some(()) } }
pub fn acquire_output(owner : Execution) -> OutputUse? { owner.output.events.push("acquire"); Some({owner, released: false}) }
pub fn borrow_original_live_model_relations(held : OutputUse, _ : Int, _ : Int, _ : Int) -> (Unit, @execution.CompletedOutput)? { if held.released { None } else { Some(((), held.owner.output)) } }
pub fn issue_original_local_model_observation_from_scope(held : OutputUse, issuer : ObservationIssuance, receipt : @execution.CompletedRelationExportReceipt, _ : Int, _ : Int, _ : Int) -> LocalModelObservation? {
  receipt.output.events.push("project")
  if receipt.output.mode == 3 { None } else { Some({held, issuer}) }
}
pub fn original_local_model_observation_body(value : LocalModelObservation) -> @publication.CapturedEffectDependencyBody? {
  if value.held.released || value.issuer.closed { None } else { Some({marker: 1}) }
}
pub fn release_output(value : OutputUse) -> Bool { value.owner.output.events.push("use"); value.released = true; true }
pub fn cancel_observation_issuance(value : ObservationIssuance) -> Bool { value.events.push("cancel"); true }
pub fn advance_observation_issuance(_ : ObservationIssuance, _ : Int) -> Result[(Bool, Int), Issue] { Ok((false, 1)) }
pub fn cleanup_observation_issuance(value : ObservationIssuance) -> Result[Bool, Issue] {
  value.events.push("issuer")
  if value.pending { Ok(false) } else { value.closed = true; Ok(true) }
}
pub fn release_original_infer_publication_capacity(value : OriginalModelPublicationCapacity) -> Result[Bool, Issue] {
  value.events.push("capacity"); value.released = true; Ok(true)
}
`);
  writeFileSync(join(root, 'src/probe_wbtest.mbt'), `
pub(all) enum NativeClientMockModelIssue { ForeignOriginal; Model(@infer.Issue) } derive(Eq, Debug)
priv struct IdentityLimits { wire : Unit; logical_wire : Unit; schema : Unit; work : Int; workspace : Int }
priv struct Limits { output_rows : Int; output_values : Unit; identity : IdentityLimits }
struct NativeClientMockModelWork {
  closing : Bool; closed : Bool; mut advancing : Bool
  mut publication_capacity : @infer.OriginalModelPublicationCapacity?
  active : @infer.Execution?; mut observation : @infer.ObservationIssuance?
  mut local_use : @infer.OutputUse?; mut local_scan : @execution.CompletedRelationIdentityScan?
  mut local_receipt : @execution.CompletedRelationExportReceipt?; mut local_observation : @infer.LocalModelObservation?
  compiled : Int; definition : Int; graph : Int; _retained_limits : Limits
}
${bodies}
test "same production partial constructor and retirement matrix" {
  for mode in 0..<6 {
    let events : Array[String] = []
    let issuer : @infer.ObservationIssuance = {events, pending: mode == 5, closed: false}
    let capacity : @infer.OriginalModelPublicationCapacity = {events, released: false}
    let work : NativeClientMockModelWork = {
      closing: false, closed: false, advancing: false,
      publication_capacity: Some(capacity), observation: Some(issuer),
      active: Some({output: {events, mode}}), local_use: None, local_scan: None,
      local_receipt: None, local_observation: None, compiled: 1, definition: 2, graph: 3,
      _retained_limits: {output_rows: 2, output_values: (), identity: {wire: (), logical_wire: (), schema: (), work: 1000, workspace: 1000}},
    }
    let opened = work.prepare_local_observation()
    assert_eq(events[0], "acquire")
    assert_eq(events[1], "start")
    assert_true(work.local_use is Some(_))
    if mode == 1 { assert_true(opened is Err(_)); assert_true(work.local_scan is None) }
    else {
      assert_true(opened is Ok(_))
      let result = work.advance_local_observation()
      if mode == 0 || mode == 5 {
        assert_eq(result, Ok(true))
        assert_true(work.local_observation_original() is Some(_))
      } else { assert_true(result is Err(_)) }
    }
    events.clear()
    assert_eq(work.close_observation(), Ok(mode != 5))
    let expected : Array[String] = []
    if mode != 1 { expected.push("scan") }
    if mode == 0 || mode == 3 || mode == 5 { expected.push("receipt") }
    expected.push("use"); expected.push("cancel"); expected.push("issuer")
    if mode != 5 { expected.push("capacity") }
    assert_eq(events, expected)
    assert_true(work.local_observation is None)
    assert_true(work.local_use is None)
    assert_true(work.local_scan is None)
    assert_true(work.local_receipt is None)
    if mode == 5 {
      assert_false(capacity.released)
      assert_true(work.observation is Some(_))
      issuer.pending = false
      events.clear()
      assert_eq(work.close_observation(), Ok(true))
      assert_eq(events, ["cancel", "issuer", "capacity"])
    }
    assert_true(capacity.released)
  }
}
`);
  const result = spawnSync('moon', ['test', '--target', 'js', '--deny-warn'], {
    cwd: root, encoding: 'utf8', timeout: 75_000, maxBuffer: 4 * 1024 * 1024,
  });
  assert.equal(result.error, undefined, result.error?.message);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout + result.stderr, /Total tests: 1, passed: 1, failed: 0/);
});

// This executes the exact production exception shell with a controlled close
// outcome. It proves compiler control-flow/exception precedence, not physical
// Native Host execution or permission to bypass an unsupported platform guard.
test('Native reply cleanup preserves one close and one cancellation prefix', {timeout: 90_000}, t => {
  const source = readFileSync(new URL('../src/cmd/native_client/local_adoption.mbt', import.meta.url), 'utf8');
  const start = source.indexOf('  let reply = {\n    errdefer');
  assert.notEqual(start, -1);
  const body = source.indexOf('      // Static check', start);
  const tail = source.indexOf('    } catch {\n      ClientStop(reason)', body);
  const end = source.indexOf('\n  reply\n}', tail) + '\n  reply\n}'.length;
  assert.ok(start < body && body < tail && tail < end);
  const shell = source.slice(start, body) + '      operation()\n' + source.slice(tail, end);
  assert.equal((shell.match(/host\.close\(\)/g) ?? []).length, 2);
  const operations = readFileSync(new URL('../src/cmd/native_client/local_operations.mbt', import.meta.url), 'utf8');
  const formatter = operations.split('///|').find(block => block.includes('fn local_cancellation_unknown('));
  assert.ok(formatter);
  const root = mkdtempSync(join(tmpdir(), 'actql-cleanup-order-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  mkdirSync(join(root, 'src'));
  writeFileSync(join(root, 'moon.mod'), 'name = "actql/cleanup-order-probe"\nsource = "src"\n');
  writeFileSync(join(root, 'src/moon.pkg'), 'supported_targets = "js"\n');
  writeFileSync(join(root, 'src/probe_wbtest.mbt'), `
priv suberror ClientStop { ClientStop(String) }
fn[T] stop(message : String) -> T raise ClientStop { raise ClientStop(message) }
priv struct ProbeHost { succeeds : Bool; mut closes : Int }
fn ProbeHost::close(self : ProbeHost) -> Result[Unit, Unit] {
  self.closes += 1
  if self.succeeds { Ok(()) } else { Err(()) }
}
${formatter}
fn probe(host : ProbeHost, cancellation_recovery : Ref[String?], operation : () -> String raise ClientStop) -> String raise ClientStop {
${shell}

test "exact production exception shell transition matrix" {
  for body_success in [false, true] {
    for close_success in [false, true] {
      for reference in [None, Some("original-reference")] {
        let host = ProbeHost::{ succeeds: close_success, closes: 0 }
        let actual = try {
          probe(host, Ref(reference), () => {
            if body_success { "original-reply" } else { stop("OriginalBodyFailure") }
          })
        } catch { ClientStop(reason) => reason }
        let reason = if !close_success { "LocalHostCleanupPending" } else { "OriginalBodyFailure" }
        let expected = if body_success && close_success { "original-reply" } else {
          match reference {
            None => reason
            Some(value) => "LocalCancellationUnknown cancel-ref=" + value + " lookup=lookup-cancellation reason=" + reason
          }
        }
        assert_eq(actual, expected)
        assert_eq(host.closes, 1)
      }
    }
  }
}
`);
  const result = spawnSync('moon', ['test', '--target', 'js', '--deny-warn'], {
    cwd: root, encoding: 'utf8', timeout: 75_000, maxBuffer: 4 * 1024 * 1024,
  });
  assert.equal(result.error, undefined, result.error?.message);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout + result.stderr, /Total tests: 1, passed: 1, failed: 0/);
});

// Execute the exact Native caller record and its accounting/close methods.
// The two dependency packages are explicit typed Resource/transport ports:
// this is a caller transition counter, not actual Native IO, debit or ACK.
function nativeTargetCleanupProbe(t) {
  const source = readFileSync(new URL('../src/cmd/native_client/local_effect_mock_targets.mbt', import.meta.url), 'utf8');
  const begin = source.indexOf('priv struct LocalNativeMockEffectTarget {');
  const end = source.indexOf('fn LocalCommandBusinessPreparation::observe_mock_effect_targets(');
  assert(begin >= 0 && end > begin);
  const actual = source.slice(begin, end);
  const root = mkdtempSync(join(tmpdir(), 'actql-target-cleanup-order-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  for (const name of ['src', 'src/resources', 'src/transport']) mkdirSync(join(root, name));
  writeFileSync(join(root, 'moon.mod'), 'name = "actql/target-cleanup-order-probe"\nsource = "src"\n');
  for (const name of ['resources', 'transport']) writeFileSync(join(root, `src/${name}/moon.pkg`), 'supported_targets = "js"\n');
  writeFileSync(join(root, 'src/resources/ports.mbt'), `
pub(all) enum LedgerIssue { TransferLimit } derive(Eq, Debug)
pub(all) enum ClientInstalledManagedRunIssue { ForeignOriginal; Ledger(LedgerIssue) } derive(Eq, Debug)
pub(all) struct ClientInstalledEffectOperationBorrow {
  mut refusing : Bool
  mut charged : Int64
  mut retire_calls : Int
}
pub fn charge_installed_effect_operation(value : ClientInstalledEffectOperationBorrow, bytes : Int64) -> Result[Unit, ClientInstalledManagedRunIssue] {
  if value.refusing { return Err(Ledger(TransferLimit)) }
  value.charged += bytes
  Ok(())
}
pub fn retire_installed_effect_operation(value : ClientInstalledEffectOperationBorrow, confirmed : Bool) -> Result[Bool, ClientInstalledManagedRunIssue] {
  if !confirmed { return Ok(false) }
  value.retire_calls += 1
  Ok(true)
}
`);
  writeFileSync(join(root, 'src/transport/ports.mbt'), `
pub(all) enum NativeRelationFileIssue { Unavailable; FileLimit } derive(Eq, Debug)
pub(all) struct NativeRelationFileTargetIO {
  mut close_kind : Int
  mut close_calls : Int
  mut closed : Bool
  mut advance_refuses : Bool
  mut advances : Int
}
pub fn NativeRelationFileTargetIO::byte_counts(_self : Self) -> (Int64, Int64) { (32L, 0L) }
pub fn NativeRelationFileTargetIO::advance(self : Self) -> Result[Bool, NativeRelationFileIssue] {
  self.advances += 1
  if self.advance_refuses { Err(FileLimit) } else { Ok(false) }
}
pub fn NativeRelationFileTargetIO::snapshot(_self : Self) -> (String, String)? { Some(("before", "version")) }

pub fn NativeRelationFileTargetIO::close(self : Self) -> Result[Bool, NativeRelationFileIssue] {
  self.close_calls += 1
  if self.close_kind == 1 { return Ok(false) }
  if self.close_kind == 2 { return Err(Unavailable) }
  self.closed = true
  Ok(true)
}
`);
  writeFileSync(join(root, 'src/moon.pkg'), 'import { "actql/target-cleanup-order-probe/resources" @local_values, "actql/target-cleanup-order-probe/transport" @row_file, } for "wbtest"\nsupported_targets = "js"\n');
  return {root, actual};
}

test('Native target cleanup reaches its original child after accounting refusal', {timeout: 90_000}, t => {
  const {root, actual} = nativeTargetCleanupProbe(t);
  writeFileSync(join(root, 'src/probe_wbtest.mbt'), `
priv enum LocalNativeMockEffectProposalIssue { Managed(@local_values.ClientInstalledManagedRunIssue) } derive(Eq, Debug)
priv enum LocalCommandPreparationIssue { CommandBusinessEffectProposals(LocalNativeMockEffectProposalIssue); CommandBusinessSource(@row_file.NativeRelationFileIssue) } derive(Eq, Debug)
${actual}
test "same original debt and physical close remain separate" {
  for kind in [0, 1, 2] {
    let operation : @local_values.ClientInstalledEffectOperationBorrow = { refusing: true, charged: 0L, retire_calls: 0 }
    let request : @local_values.ClientInstalledEffectOperationBorrow = { refusing: false, charged: 0L, retire_calls: 0 }
    let child : @row_file.NativeRelationFileTargetIO = { close_kind: kind, close_calls: 0, closed: false, advance_refuses: false, advances: 0 }
    let held : LocalNativeMockEffectTarget = {
      operation, child: Some(child), observed: Some(("original-before", "original-version")),
      request_operation: Some(request), _retained_request: Some(("original-request", "original-cid")),
      charged: 0L, received: 0L, _retained_account_issue: None,
    }
    let refused = held.close()
    assert_eq(child.close_calls, 1)
    match kind {
      0 => {
        assert_true(refused is Err(CommandBusinessEffectProposals(Managed(Ledger(TransferLimit)))))
        assert_true(child.closed && held.child is None)
      }
      1 => { assert_eq(refused, Ok(false)); assert_true(held.child is Some(_)) }
      _ => { assert_true(refused is Err(CommandBusinessSource(Unavailable))); assert_true(held.child is Some(_)) }
    }
    assert_eq(held.charged, 0L)
    assert_eq(operation.charged, 0L)
    assert_eq(operation.retire_calls, 0)
    assert_eq(request.retire_calls, 0)
    assert_eq(held.observed, Some(("original-before", "original-version")))
    assert_eq(held._retained_request, Some(("original-request", "original-cid")))
    // Retry only cleanup, without another advance/read or another operation.
    child.close_kind = 0
    operation.refusing = false
    assert_eq(held.close(), Ok(true))
    assert_true(child.closed && held.child is None)
    assert_eq(child.close_calls, if kind == 0 { 1 } else { 2 })
    assert_eq(operation.charged, 32L)
    assert_eq(held.charged, 32L)
    assert_eq(operation.retire_calls, 1)
    assert_eq(request.retire_calls, 1)
    assert_true(held.observed is None && held._retained_request is None)
  }
}
`);
  const result = spawnSync('moon', ['test', '--target', 'js', '--deny-warn'], {
    cwd: root, encoding: 'utf8', timeout: 75_000, maxBuffer: 4 * 1024 * 1024,
  });
  assert.equal(result.error, undefined, result.error?.message);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout + result.stderr, /Total tests: 1, passed: 1, failed: 0/);
});

// Same original error-retention shell, with only its typed dependency ports
// substituted. No ordinary Native failure cause or physical ACK is inferred.
test('Native target retains its physical first cause before failed accounting', {timeout: 90_000}, t => {
  const {root, actual} = nativeTargetCleanupProbe(t);
  const source = readFileSync(new URL('../src/cmd/native_client/local_effect_mock_targets.mbt', import.meta.url), 'utf8');
  const begin = source.indexOf('          let result = held.child.unwrap().advance()');
  const end = source.indexOf('\n        })\n      }\n      authorize()', begin);
  assert(begin > 0 && end > begin);
  const step = source.slice(begin, end);
  const proposal = readFileSync(new URL('../src/cmd/native_client/local_effect_mock_proposals.mbt', import.meta.url), 'utf8');
  const helper = proposal.split('///|').find(block => block.includes('fn[T] Result::native_effect_proposal('));
  const preparation = readFileSync(new URL('../src/cmd/native_client/local_command_preparation.mbt', import.meta.url), 'utf8');
  const primary = preparation.split('///|').find(block => block.includes('fn LocalCommandPreparationOriginal::retain_primary('));
  assert(helper && primary);
  writeFileSync(join(root, 'src/probe_wbtest.mbt'), `
priv enum LocalNativeMockEffectProposalIssue { Managed(@local_values.ClientInstalledManagedRunIssue) } derive(Eq, Debug)
priv enum LocalCommandPreparationIssue { CommandBusinessEffectProposals(LocalNativeMockEffectProposalIssue); CommandBusinessSource(@row_file.NativeRelationFileIssue) } derive(Eq, Debug)
priv suberror ClientStop { ClientStop(String) }
fn[T] stop(message : String) -> T raise ClientStop { raise ClientStop(message) }
priv struct LocalCommandPreparationOriginal { mut primary : LocalCommandPreparationIssue? }
priv struct Preparation { original : LocalCommandPreparationOriginal }
${actual}
${primary}
${helper}
fn Preparation::step(self : Self, held : LocalNativeMockEffectTarget) -> Bool raise ClientStop {
${step}
}
test "physical failure survives a distinct accounting refusal" {
  for (physical_failure, accounting_failure) in [(true, true), (false, true), (true, false)] {
    let operation : @local_values.ClientInstalledEffectOperationBorrow = { refusing: accounting_failure, charged: 0L, retire_calls: 0 }
    let child : @row_file.NativeRelationFileTargetIO = { close_kind: 0, close_calls: 0, closed: false, advance_refuses: physical_failure, advances: 0 }
    let held : LocalNativeMockEffectTarget = {
      operation, child: Some(child), observed: None, request_operation: None, _retained_request: None,
      charged: 0L, received: 0L, _retained_account_issue: None,
    }
    let original : LocalCommandPreparationOriginal = { primary: None }
    let caller : Preparation = { original, }
    let mut stopped = false
    try { caller.step(held) |> ignore } catch { ClientStop(_) => stopped = true }
    assert_true(stopped)
    assert_eq(child.advances, 1)
    assert_eq(child.close_calls, 0)
    if physical_failure {
      assert_eq(original.primary, Some(CommandBusinessSource(FileLimit)))
    } else {
      assert_eq(original.primary, Some(CommandBusinessEffectProposals(Managed(Ledger(TransferLimit)))))
    }
    assert_eq(held.received, 32L)
    if accounting_failure {
      assert_eq(held._retained_account_issue, Some(Ledger(TransferLimit)))
      assert_eq(operation.charged, 0L)
    } else { assert_eq(operation.charged, 32L) }
    assert_eq(operation.retire_calls, 0)
    assert_true(held.observed is None)
    held.close() |> ignore
    assert_eq(child.close_calls, 1)
  }
}
`);
  const result = spawnSync('moon', ['test', '--target', 'js', '--deny-warn'], {
    cwd: root, encoding: 'utf8', timeout: 75_000, maxBuffer: 4 * 1024 * 1024,
  });
  assert.equal(result.error, undefined, result.error?.message);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout + result.stderr, /Total tests: 1, passed: 1, failed: 0/);
});
