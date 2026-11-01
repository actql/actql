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
