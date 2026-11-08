import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';

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
test('Native target cleanup reaches its original child after accounting refusal', {timeout: 90_000}, t => {
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
pub(all) enum NativeRelationFileIssue { Unavailable } derive(Eq, Debug)
pub(all) struct NativeRelationFileTargetIO {
  mut close_kind : Int
  mut close_calls : Int
  mut closed : Bool
}
pub fn NativeRelationFileTargetIO::byte_counts(_self : Self) -> (Int64, Int64) { (32L, 0L) }
pub fn NativeRelationFileTargetIO::close(self : Self) -> Result[Bool, NativeRelationFileIssue] {
  self.close_calls += 1
  if self.close_kind == 1 { return Ok(false) }
  if self.close_kind == 2 { return Err(Unavailable) }
  self.closed = true
  Ok(true)
}
`);
  writeFileSync(join(root, 'src/moon.pkg'), 'import { "actql/target-cleanup-order-probe/resources" @local_values, "actql/target-cleanup-order-probe/transport" @row_file, } for "wbtest"\nsupported_targets = "js"\n');
  writeFileSync(join(root, 'src/probe_wbtest.mbt'), `
priv enum LocalNativeMockEffectProposalIssue { Managed(@local_values.ClientInstalledManagedRunIssue) } derive(Eq, Debug)
priv enum LocalCommandPreparationIssue { CommandBusinessEffectProposals(LocalNativeMockEffectProposalIssue); CommandBusinessSource(@row_file.NativeRelationFileIssue) } derive(Eq, Debug)
${actual}
test "same original debt and physical close remain separate" {
  for kind in [0, 1, 2] {
    let operation : @local_values.ClientInstalledEffectOperationBorrow = { refusing: true, charged: 0L, retire_calls: 0 }
    let request : @local_values.ClientInstalledEffectOperationBorrow = { refusing: false, charged: 0L, retire_calls: 0 }
    let child : @row_file.NativeRelationFileTargetIO = { close_kind: kind, close_calls: 0, closed: false }
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
