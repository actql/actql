import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, readdirSync, mkdtempSync, mkdirSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';

// Exact Native methods with explicit typed dependency ports: caller ordering,
// not Model/Resource/Journal/Native ABI or physical cleanup acceptance.
test('Native Model local observation retains partial exports before issuer retirement', {timeout: 90_000}, t => {
  const source = readFileSync(new URL('../src/platform_native/client_host/mock_model_observation.mbt', import.meta.url), 'utf8');
  const capacities = readFileSync(new URL('../src/platform_native/client_host/mock_model_observation_capacity.mbt', import.meta.url), 'utf8');
  const names = ['close_observation', 'prepare_local_observation', 'advance_local_observation', 'local_observation_original', 'local_observation_dependency_bodies'];
  const bodies = names.map(name => {
    const block = source.split('///|').find(value => value.includes(`fn NativeClientMockModelWork::${name}(`));
    assert(block, name); return block.trim();
  }).join('\n');
  const grow = capacities.split('///|').find(value => value.includes('fn NativeClientMockModelWork::grow_observation_capacity('));
  const startup = capacities.split('///|').find(value => value.includes('pub fn native_client_mock_model_observation_capacity('));
  assert(grow && startup);
  const representation = readFileSync(new URL('../src/execution_relation/preparation_representation.mbt', import.meta.url), 'utf8');
  const arrayRepresentation = representation.split('///|').find(value =>
    value.includes('pub fn preparation_array_representation('));
  assert(arrayRepresentation);
  const root = mkdtempSync(join(tmpdir(), 'actql-native-model-observation-order-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  for (const name of ['', 'execution', 'publication', 'infer', 'counts']) mkdirSync(join(root, 'src', name), {recursive: true});
  writeFileSync(join(root, 'moon.mod'), 'name = "actql/model-observation-order-probe"\nsource = "src"\n');
  for (const name of ['execution', 'publication', 'counts']) writeFileSync(join(root, `src/${name}/moon.pkg`), 'supported_targets = "js"\n');
  writeFileSync(join(root, 'src/execution/moon.pkg'), 'supported_targets = "js"\nimport { "actql/model-observation-order-probe/counts" @preparation_counts }\n');
  // The pure representation helper is the actual Source, not another byte
  // tariff or Ledger. Resource growth below remains an explicit refusal port.
  writeFileSync(join(root, 'src/counts/counts.mbt'), readFileSync(new URL('../src/capacity_arithmetic/preparation_counts.mbt', import.meta.url), 'utf8'));
  writeFileSync(join(root, 'src/moon.pkg'), 'supported_targets = "js"\nimport { "actql/model-observation-order-probe/execution" @execution, "actql/model-observation-order-probe/infer" @infer, "actql/model-observation-order-probe/publication" @publication } for "wbtest"\n');
  writeFileSync(join(root, 'src/infer/moon.pkg'), 'supported_targets = "js"\nimport { "actql/model-observation-order-probe/execution" @execution, "actql/model-observation-order-probe/publication" @publication }\n');
  writeFileSync(join(root, 'src/publication/ports.mbt'), `
pub(all) struct CapturedEffectDependencyBody { marker : Int }
pub(all) struct RunEvidenceValue { marker : Int }
`);
  writeFileSync(join(root, 'src/execution/ports.mbt'), `
pub(all) enum Issue { Refused } derive(Eq, Debug)
pub(all) struct ExecutionCapacity { retained : Int64; execution : Int64 } derive(Eq, Debug)
pub(all) struct PreparationRepresentationUnits { record_headers : Int64; reference_slots : Int64; scalar_words : Int64; owned_utf16_units : Int64; owned_wire_bytes : Int64 } derive(Eq, Debug)
${arrayRepresentation}
pub(all) struct PreparationExecutionInventory { retained : PreparationRepresentationUnits; workspace : PreparationRepresentationUnits; retained_nodes : Int64; workspace_nodes : Int64; retained_bytes : Int64; workspace_bytes : Int64 }
let observed_units : Ref[PreparationExecutionInventory?] = Ref(None)
pub fn preparation_execution_capacity(value : PreparationExecutionInventory) -> ExecutionCapacity? { observed_units.val = Some(value); Some({retained: 1L, execution: 1L}) }
pub fn startup_units() -> PreparationExecutionInventory { observed_units.val.unwrap() }
pub fn execution_capacity(retained : Int64, execution : Int64) -> ExecutionCapacity? { Some({retained, execution}) }
pub fn execution_capacity_retained_bytes(v : ExecutionCapacity) -> Int64 { v.retained }
pub fn execution_capacity_execution_bytes(v : ExecutionCapacity) -> Int64 { v.execution }
pub fn add_execution_capacity(a : ExecutionCapacity, b : ExecutionCapacity) -> ExecutionCapacity? { Some({retained: a.retained+b.retained, execution: a.execution+b.execution}) }
pub(all) struct CompletedOutput { events : Array[String]; mode : Int }
pub(all) struct CompletedRelationIdentityScan { output : CompletedOutput }
pub(all) struct CompletedRelationExportReceipt { output : CompletedOutput }
pub fn completed_relation_identity_scan_start_construction_capacity(_ : CompletedOutput, retain_body? : Bool = false) -> ExecutionCapacity? {
  if !retain_body { abort("expected same-scan retained body") }
  Some({retained: 20L, execution: 20L})
}
pub fn completed_relation_identity_scan_next_construction_capacity(_ : CompletedRelationIdentityScan) -> ExecutionCapacity? { Some({retained: 15L, execution: 15L}) }
pub fn start_completed_relation_identity_scan(output : CompletedOutput, _ : Int, _ : Unit, _ : Unit, _ : Unit, _ : Unit, _ : Int, _ : Int, incremental_metadata? : Bool = false, retain_body? : Bool = false) -> Result[CompletedRelationIdentityScan, Issue] {
  if !incremental_metadata || !retain_body { abort("expected incremental metadata and same-scan retained body") }
  output.events.push("start")
  if output.mode == 1 { Err(Refused) } else { Ok({output,}) }
}
pub fn advance_completed_relation_identity_scan(value : CompletedRelationIdentityScan, _ : Int, construction_capacity? : ExecutionCapacity? = None) -> Result[(Bool, Int), Issue] {
  if construction_capacity is None { abort("expected held construction boundary") }
  value.output.events.push("advance")
  if value.output.mode == 2 { Err(Refused) } else { Ok((true, 1)) }
}
pub fn finish_completed_relation_identity_scan(value : CompletedRelationIdentityScan) -> Result[CompletedRelationExportReceipt, Issue] {
  value.output.events.push("finish")
  if value.output.mode == 4 { Err(Refused) } else { Ok({output: value.output}) }
}
pub fn completed_relation_identity_scan_body(_ : CompletedRelationIdentityScan, _ : CompletedRelationExportReceipt) -> String? { Some("original-body") }
pub fn completed_relation_export_schema_identity(_ : CompletedRelationExportReceipt) -> String { "original-schema" }
pub fn relation_schema_wire(value : String) -> String { value }
pub fn cancel_completed_relation_identity_scan(value : CompletedRelationIdentityScan) -> Bool { value.output.events.push("scan"); true }
pub fn cancel_completed_relation_export_receipt(value : CompletedRelationExportReceipt) -> Unit { value.output.events.push("receipt") }
`);
  writeFileSync(join(root, 'src/infer/ports.mbt'), `
pub(all) enum Issue { IdentityExport(@execution.Issue); Refused } derive(Eq, Debug)
pub(all) struct ModelLimits { max_items : Int }
pub(all) struct Limits { model : ModelLimits }
pub(all) struct Execution { output : @execution.CompletedOutput }
pub(all) struct OutputUse { owner : Execution; mut released : Bool }
pub(all) struct LocalModelObservation { marker : Int }
pub(all) struct ObservationIssuance { events : Array[String]; mut pending : Bool; mut closed : Bool }
pub(all) struct OriginalModelPublicationCapacity { events : Array[String]; mut released : Bool }
pub fn observation_issuance_value(_ : ObservationIssuance) -> Int? { Some(1) }
pub fn acquire_output(owner : Execution) -> OutputUse? { owner.output.events.push("acquire"); Some({owner, released: false}) }
pub fn borrow_original_live_model_relations(held : OutputUse, _ : Int, _ : Int, _ : Int) -> (Int, @execution.CompletedOutput)? { Some((0, held.owner.output)) }
pub fn issue_original_local_model_observation_from_scope(_ : OutputUse, _ : ObservationIssuance, receipt : @execution.CompletedRelationExportReceipt, _ : Int, _ : Int, _ : Int) -> LocalModelObservation? {
  receipt.output.events.push("project")
  if receipt.output.mode == 3 { None } else { Some({marker: 9}) }
}
pub fn original_local_model_observation_body(value : LocalModelObservation) -> @publication.CapturedEffectDependencyBody? { Some({marker: value.marker}) }
pub fn original_local_model_observation_input_bodies(_ : LocalModelObservation) -> Array[(String, String)]? {
  Some([("relation_value", "original-input"), ("relation_schema", "original-input-schema")])
}
pub fn grow_original_infer_publication_capacity(owner : Execution, value : OriginalModelPublicationCapacity, retained : Int64, _ : Int64) -> Result[Unit, Issue] {
  if owner.output.mode == 6 || (owner.output.mode == 7 && retained > 30L) ||
    (owner.output.mode == 8 && retained > 70L) {
    value.events.push("grow-refused"); Err(Refused)
  } else { value.events.push("grow"); Ok(()) }
}
pub fn release_output(value : OutputUse) -> Bool { value.owner.output.events.push("use"); value.released = true; true }
pub fn cancel_observation_issuance(value : ObservationIssuance) -> Bool { value.events.push("cancel"); true }
pub fn advance_observation_issuance(_ : ObservationIssuance, _ : Int) -> Result[(Bool, Int), Issue] { Ok((false, 1)) }
pub fn cleanup_observation_issuance(value : ObservationIssuance) -> Result[Bool, Issue] { value.events.push("issuer"); if value.pending { Ok(false) } else { value.closed = true; Ok(true) } }
pub fn release_original_infer_publication_capacity(value : OriginalModelPublicationCapacity) -> Result[Bool, Issue] { value.events.push("capacity"); value.released = true; Ok(true) }
`);
  writeFileSync(join(root, 'src/probe_wbtest.mbt'), `
pub(all) enum NativeClientMockModelIssue { ForeignOriginal; Encoding; Model(@infer.Issue) } derive(Eq, Debug)
pub(all) struct Identity { wire : Unit; logical_wire : Unit; schema : Unit; work : Int; workspace : Int }
pub(all) struct Limits { output_rows : Int; output_values : Unit; identity : Identity }
struct NativeClientMockModelWork {
  closing : Bool; closed : Bool; mut advancing : Bool
  mut publication_capacity : @infer.OriginalModelPublicationCapacity?
  mut publication_retained : Int64; mut publication_execution : Int64
  mut observation : @infer.ObservationIssuance?; active : @infer.Execution?
  mut local_use : @infer.OutputUse?; mut local_scan : @execution.CompletedRelationIdentityScan?
  mut local_receipt : @execution.CompletedRelationExportReceipt?; mut local_observation : @infer.LocalModelObservation?
  mut publication_inputs : (Array[String], Array[@publication.RunEvidenceValue])?
  compiled : Int; definition : Int; graph : Int; _retained_limits : Limits
}
fn NativeClientMockModelWork::observation_issuer_capacity(_self : Self) -> @execution.ExecutionCapacity? { Some({retained: 10L, execution: 10L}) }
fn NativeClientMockModelWork::local_observation_projection_capacity(self : Self, _ : @execution.CompletedRelationExportReceipt) -> @execution.ExecutionCapacity? { Some({retained: self.publication_retained+40L, execution: self.publication_execution+40L}) }
${grow}
${startup}
${bodies}
test "same production partial constructor and retirement matrix" {
  for mode in 0..<9 {
    let events : Array[String] = []
    let issuer : @infer.ObservationIssuance = {events, pending: mode == 5, closed: false}
    let capacity : @infer.OriginalModelPublicationCapacity = {events, released: false}
    let work : NativeClientMockModelWork = {
      closing: false, closed: false, advancing: false,
      publication_capacity: Some(capacity), publication_retained: 10L, publication_execution: 10L,
      observation: Some(issuer), active: Some({output: {events, mode}}), local_use: None, local_scan: None,
      local_receipt: None, local_observation: None, compiled: 1, definition: 2, graph: 3,
      publication_inputs: Some((["original-input"], [{marker: 41}])),
      _retained_limits: {output_rows: 2, output_values: (), identity: {wire: (), logical_wire: (), schema: (), work: 1000, workspace: 1000}},
    }
    assert_true(work.local_observation_dependency_bodies() is None)
    // Mode8 permits exactly held30+new projection40. The held scan already
    // owns the body; any independent second body debit must fail this port.
    let opened = work.prepare_local_observation()
    assert_eq(events[0], "acquire")
    assert_eq(events[1], if mode == 6 { "grow-refused" } else { "grow" })
    assert_true(work.local_use is Some(_))
    if mode == 1 || mode == 6 {
      assert_true(opened is Err(_)); assert_true(work.local_scan is None)
      if mode == 6 { assert_eq(work.publication_retained, 10L); assert_false(events.contains("start")) }
    } else {
      assert_eq(events[2], "start")
      assert_true(opened is Ok(_))
      let result = work.advance_local_observation()
      if mode == 0 || mode == 5 || mode == 8 { assert_eq(result, Ok(true)); assert_true(work.local_observation_original() is Some(_)) }
      else { assert_true(result is Err(_)) }
      if mode == 3 || mode == 7 { assert_true(work.local_receipt is Some(_)) }
      if mode == 7 { assert_eq(work.publication_retained, 30L); assert_false(events.contains("project")) }
    }
    if mode == 0 || mode == 5 || mode == 8 {
      assert_eq(work.local_observation_dependency_bodies(), Some([
        ("relation_value", "original-input"), ("relation_schema", "original-input-schema"),
        ("relation_value", "original-body"), ("relation_schema", "original-schema"),
      ]))
      work.advancing = true
      assert_true(work.local_observation_dependency_bodies() is None)
      work.advancing = false
    } else { assert_true(work.local_observation_dependency_bodies() is None) }
    assert_eq(events.filter(value => value == "grow").length(),
      if mode == 6 { 0 } else if mode == 0 || mode == 3 || mode == 5 || mode == 8 { 2 } else { 1 })
    events.clear()
    assert_true(work.publication_inputs is Some(_))
    assert_eq(work.close_observation(), Ok(mode != 5))
    assert_true(work.publication_inputs is None)
    assert_true(work.local_observation_dependency_bodies() is None)
    let expected : Array[String] = []
    if mode != 1 && mode != 6 { expected.push("scan") }
    if mode == 0 || mode == 3 || mode == 5 || mode == 7 || mode == 8 { expected.push("receipt") }
    expected.push("use"); expected.push("cancel"); expected.push("issuer")
    if mode != 5 { expected.push("capacity") }
    assert_eq(events, expected)
    assert_true(work.local_observation is None); assert_true(work.local_use is None)
    assert_true(work.local_scan is None); assert_true(work.local_receipt is None)
    if mode == 5 {
      assert_false(capacity.released); assert_true(work.observation is Some(_))
      issuer.pending = false; events.clear()
      assert_eq(work.close_observation(), Ok(true)); assert_eq(events, ["cancel", "issuer", "capacity"])
    }
    assert_true(capacity.released)
    assert_eq(work.publication_retained, 0L); assert_eq(work.publication_execution, 0L)
  }
}
test "startup selects fixed controls without reading output maxima" {
  for count in [2, 10000] {
    assert_true(native_client_mock_model_observation_capacity({model: {max_items: count}}) is Some(_))
    let units = @execution.startup_units()
    // Original fixed controls plus dependency-triple/map holders and one
    // growing two-entry input array (3H/19R/2W), independent of output maxima.
    assert_eq(units.retained.record_headers, 32L + 4L + 3L)
    assert_eq(units.retained.reference_slots, 128L + 10L + 13L + 3L * 2L)
    assert_eq(units.retained.scalar_words, 64L + 1L + 2L)
    assert_eq(units.retained.owned_utf16_units, 0L)
    assert_eq(units.retained.owned_wire_bytes, 0L)
    assert_eq(units.workspace.record_headers, 0L)
  }
}
`);
  const result = spawnSync('moon', ['test', '--target', 'js', '--deny-warn'], {
    cwd: root, encoding: 'utf8', timeout: 75_000, maxBuffer: 4 * 1024 * 1024,
  });
  assert.equal(result.error, undefined, result.error?.message);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout + result.stderr, /Total tests: 2, passed: 2, failed: 0/);
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
// The dependency packages are explicit typed Resource/transport/DATA ports:
// this is a caller transition counter, not actual Native IO, debit or ACK.
function nativeTargetCleanupProbe(t) {
  const source = readFileSync(new URL('../src/cmd/native_client/local_effect_mock_targets.mbt', import.meta.url), 'utf8');
  const begin = source.indexOf('priv struct LocalNativeMockEffectTarget {');
  const end = source.indexOf('fn LocalCommandBusinessPreparation::observe_mock_effect_targets(');
  assert(begin >= 0 && end > begin);
  const actual = source.slice(begin, end);
  const root = mkdtempSync(join(tmpdir(), 'actql-target-cleanup-order-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  for (const name of ['src', 'src/resources', 'src/transport', 'src/execution']) mkdirSync(join(root, name));
  writeFileSync(join(root, 'moon.mod'), 'name = "actql/target-cleanup-order-probe"\nsource = "src"\n');
  for (const name of ['resources', 'transport', 'execution']) writeFileSync(join(root, `src/${name}/moon.pkg`), 'supported_targets = "js"\n');
  writeFileSync(join(root, 'src/execution/ports.mbt'), 'pub(all) struct ExecutionCapacity { retained : Int64; execution : Int64 }\n');
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
  writeFileSync(join(root, 'src/moon.pkg'), 'import { "actql/target-cleanup-order-probe/resources" @local_values, "actql/target-cleanup-order-probe/transport" @row_file, "actql/target-cleanup-order-probe/execution" @execution, } for "wbtest"\nsupported_targets = "js"\n');
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
    let input : LocalNativeMockEffectRequestInput = {
      value: Json::null(), before: "original-input-before", version: "original-input-version",
      initial: {retained: 1L, execution: 2L},
    }
    let held : LocalNativeMockEffectTarget = {
      operation, child: Some(child), observed: Some(("original-before", "original-version")),
      request_operation: Some(request), request_input: Some(input), _retained_request: Some(("original-request", "original-cid")),
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
    assert_true(physical_equal(held.request_input.unwrap(), input))
    assert_true(input.value is Null)
    assert_eq(input.before, "original-input-before"); assert_eq(input.version, "original-input-version")
    assert_eq(input.initial.retained, 1L); assert_eq(input.initial.execution, 2L)
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
    assert_true(held.observed is None && held.request_input is None && held._retained_request is None)
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
  const helper = proposal.split('///|').find(block => block.includes('fn[T] Result::native_effect_proposal_with_cause('));
  const proposalReporter = source.match(/^  let report_proposal = .+$/mu)?.[0];
  const preparation = readFileSync(new URL('../src/cmd/native_client/local_command_preparation.mbt', import.meta.url), 'utf8');
  const primary = preparation.split('///|').find(block => block.includes('fn LocalCommandPreparationOriginal::retain_primary('));
  assert(helper && proposalReporter && primary);
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
  let report = issue => self.original.retain_primary(issue)
${proposalReporter}
  let mut complete = false
${step}
  complete
}
test "physical failure survives a distinct accounting refusal" {
  for (physical_failure, accounting_failure) in [(true, true), (false, true), (true, false)] {
    let operation : @local_values.ClientInstalledEffectOperationBorrow = { refusing: accounting_failure, charged: 0L, retire_calls: 0 }
    let child : @row_file.NativeRelationFileTargetIO = { close_kind: 0, close_calls: 0, closed: false, advance_refuses: physical_failure, advances: 0 }
    let input : LocalNativeMockEffectRequestInput = {
      value: Json::null(), before: "original-input-before", version: "original-input-version",
      initial: {retained: 1L, execution: 2L},
    }
    let held : LocalNativeMockEffectTarget = {
      operation, child: Some(child), observed: None, request_operation: None, request_input: Some(input), _retained_request: None,
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
    assert_true(physical_equal(held.request_input.unwrap(), input))
    assert_true(input.value is Null)
    assert_eq(input.before, "original-input-before"); assert_eq(input.version, "original-input-version")
    assert_eq(input.initial.retained, 1L); assert_eq(input.initial.execution, 2L)
    held.close() |> ignore
    assert_eq(child.close_calls, 1)
    if accounting_failure { assert_true(physical_equal(held.request_input.unwrap(), input)) }
    else { assert_true(held.request_input is None) }
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


// Exact callbackful Native boundary with explicit dependency ports, not actual
// Model/Core/Resource execution, ABI, physical ACK or ordinary acceptance.
test('Native Model Effect Invocation fences reentry and refuses after retirement', {timeout: 90_000}, t => {
  const source = readFileSync(new URL('../src/platform_native/client_host/mock_model_observation.mbt', import.meta.url), 'utf8');
  const body = source.split('///|').find(value => value.includes('fn NativeClientMockModelWork::local_effect_invocation('));
  assert(body);
  const root = mkdtempSync(join(tmpdir(), 'actql-native-model-effect-invocation-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  for (const name of ['', 'host', 'infer']) mkdirSync(join(root, 'src', name), {recursive: true});
  writeFileSync(join(root, 'moon.mod'), 'name = "actql/local-model-effect-invocation-probe"\nsource = "src"\n');
  writeFileSync(join(root, 'src/moon.pkg'), 'supported_targets = "js"\nimport { "actql/local-model-effect-invocation-probe/host" @host, "actql/local-model-effect-invocation-probe/infer" @infer } for "wbtest"\n');
  writeFileSync(join(root, 'src/host/moon.pkg'), 'supported_targets = "js"\n');
  writeFileSync(join(root, 'src/infer/moon.pkg'), 'supported_targets = "js"\nimport { "actql/local-model-effect-invocation-probe/host" @host }\n');
  writeFileSync(join(root, 'src/host/ports.mbt'), 'pub(all) struct ClientEffectLocalInvocation { marker : Int }\n');
  writeFileSync(join(root, 'src/infer/ports.mbt'), `
pub(all) struct LocalModelObservation { probe : () -> Unit; fail : Bool }
pub fn issue_original_local_model_effect_invocation(value : LocalModelObservation, _ : Int, _ : Int, _ : Int) -> @host.ClientEffectLocalInvocation? {
  (value.probe)()
  if value.fail { None } else { Some({marker: 7}) }
}
`);
  writeFileSync(join(root, 'src/probe_wbtest.mbt'), `
struct NativeClientMockModelWork {
  mut closing : Bool; closed : Bool; mut advancing : Bool
  mut local_observation : @infer.LocalModelObservation?
}
${body}
test "same Native original guards and callbackful reentry" {
  let calls = Ref(0)
  let latched = Ref(false)
  let reentry_refused = Ref(false)
  let work : NativeClientMockModelWork = {closing: false, closed: false, advancing: false, local_observation: None}
  assert_true(work.local_effect_invocation(10, 10, 10) is None)
  work.local_observation = Some({fail: false, probe: () => {
    calls.val += 1
    latched.val = work.advancing
    reentry_refused.val = work.local_effect_invocation(10, 10, 10) is None
  }})
  assert_true(work.local_effect_invocation(10, 10, 10) is Some({marker: 7}))
  assert_false(work.advancing)
  assert_true(latched.val)
  assert_true(reentry_refused.val)
  assert_eq(calls.val, 1)
  work.local_observation = Some({fail: true, probe: () => calls.val += 1})
  assert_true(work.local_effect_invocation(10, 10, 10) is None)
  assert_false(work.advancing)
  assert_eq(calls.val, 2)
  work.closing = true
  assert_true(work.local_effect_invocation(10, 10, 10) is None)
  assert_eq(calls.val, 2)
}
`);
  const result = spawnSync('moon', ['test', '--target', 'js', '--deny-warn'], {cwd: root, env: process.env, encoding: 'utf8', timeout: 80_000});
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stdout+'\n'+result.stderr);
  assert.match(result.stdout+'\n'+result.stderr, /Total tests: 1, passed: 1, failed: 0/);
});

// The exact Native initial-owner method with explicit read/current/refusal
// ports. This is constructor ordering, not Native ABI or ordinary acceptance.
test('Native Host settings keeps the same retained prefix and rejects construction before entry', {timeout: 90_000}, t => {
  const source = readFileSync(new URL('../src/cmd/native_client/local_host_settings_preparation.mbt', import.meta.url), 'utf8');
  const actual = source.split('///|').find(value => value.includes('fn LocalCommandPreparationOriginal::prepare_host_metadata('));
  assert(actual);
  const root = mkdtempSync(join(tmpdir(), 'actql-native-host-settings-order-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  for (const name of ['', 'execution', 'arena', 'counts']) mkdirSync(join(root, 'src', name), {recursive: true});
  writeFileSync(join(root, 'moon.mod'), 'name = "actql/host-settings-order-probe"\nsource = "src"\n');
  writeFileSync(join(root, 'src/moon.pkg'), 'supported_targets = "js"\nimport { "actql/host-settings-order-probe/arena" @initial_arena, "actql/host-settings-order-probe/execution" @execution } for "wbtest"\n');
  writeFileSync(join(root, 'src/counts/moon.pkg'), 'supported_targets = "js"\n');
  writeFileSync(join(root, 'src/counts/counts.mbt'), readFileSync(new URL('../src/capacity_arithmetic/preparation_counts.mbt', import.meta.url), 'utf8'));
  writeFileSync(join(root, 'src/execution/moon.pkg'), 'supported_targets = "js"\nimport { "actql/host-settings-order-probe/counts" @preparation_counts }\n');
  const representation = readFileSync(new URL('../src/execution_relation/preparation_representation.mbt', import.meta.url), 'utf8');
  const arithmetic = representation.split('///|').find(value => value.includes('pub fn checked_preparation_add_product('));
  assert(arithmetic);
  writeFileSync(join(root, 'src/execution/arithmetic.mbt'), arithmetic);
  writeFileSync(join(root, 'src/arena/moon.pkg'), 'supported_targets = "js"\n');
  writeFileSync(join(root, 'src/arena/ports.mbt'), `
pub(all) enum Issue { Refused } derive(Eq, Debug)
pub(all) struct InstalledArenaOriginalRead { marker : Int }
pub(all) struct InstalledArenaHost { original : InstalledArenaOriginalRead; ceiling : Int64; calls : Array[(Int64, Int64, Int64)] }
pub fn InstalledArenaHost::prepare_domain_original_read_construction(self : Self, read : InstalledArenaOriginalRead, r : Int64, e : Int64, raw : Int64) -> Result[Unit, Issue] {
  if !physical_equal(read, self.original) { abort("foreign Read") }
  self.calls.push((r, e, raw))
  if r > self.ceiling || e > self.ceiling { Err(Refused) } else { Ok(()) }
}
`);
  writeFileSync(join(root, 'src/probe_wbtest.mbt'), `
priv enum LocalCommandPreparationIssue { CommandUnavailable; CommandRead(@initial_arena.Issue) } derive(Eq, Debug)
priv struct LocalCommandPreparationOriginal {
  host : @initial_arena.InstalledArenaHost?; read : @initial_arena.InstalledArenaOriginalRead?
  mut phase_open : Bool; journal_read_open : Bool; mut closing : Bool; closed : Bool
  mut primary : LocalCommandPreparationIssue?; read_failure : Unit?; mut metadata_retained : Int64
}
${actual}
fn original(ceiling : Int64) -> (LocalCommandPreparationOriginal, @initial_arena.InstalledArenaHost) {
  let read : @initial_arena.InstalledArenaOriginalRead = {marker: 41}
  let host : @initial_arena.InstalledArenaHost = {original: read, ceiling, calls: []}
  ({host: Some(host), read: Some(read), phase_open: true, journal_read_open: false, closing: false, closed: false, primary: None, read_failure: None, metadata_retained: 0L}, host)
}
test "same prefix is retained while completed scratch is not accumulated" {
  let (value, host) = original(1000L)
  assert_eq(value.prepare_host_metadata(10L, 100L), Ok(()))
  assert_eq(value.prepare_host_metadata(20L, 30L), Ok(()))
  assert_eq(value.prepare_host_metadata(0L, 50L), Ok(()))
  assert_eq(host.calls, [(10L, 100L, 100L), (30L, 40L, 30L), (30L, 80L, 50L)])
  assert_eq(value.metadata_retained, 30L)
}
test "a refused next constructor publishes no retained output" {
  let (value, host) = original(100L)
  assert_eq(value.prepare_host_metadata(10L, 20L), Ok(()))
  assert_eq(value.prepare_host_metadata(20L, 91L), Err(CommandRead(Refused)))
  assert_eq(value.metadata_retained, 10L)
  assert_eq(host.calls.length(), 2)
}
test "cleanup currentness and arithmetic refusal precede the Host call" {
  let (value, host) = original(1000L)
  value.phase_open = false
  assert_eq(value.prepare_host_metadata(1L, 2L), Err(CommandUnavailable))
  value.phase_open = true; value.closing = true
  assert_eq(value.prepare_host_metadata(1L, 2L), Err(CommandUnavailable))
  value.closing = false; value.primary = Some(CommandUnavailable)
  assert_eq(value.prepare_host_metadata(1L, 2L), Err(CommandUnavailable))
  value.primary = None; value.metadata_retained = 9223372036854775807L
  assert_eq(value.prepare_host_metadata(1L, 2L), Err(CommandUnavailable))
  assert_eq(host.calls.length(), 0)
}
`);
  const result = spawnSync('moon', ['test', '--target', 'js', '--deny-warn'], {
    cwd: root, encoding: 'utf8', timeout: 75_000, maxBuffer: 4 * 1024 * 1024,
  });
  assert.equal(result.error, undefined, result.error?.message);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout + result.stderr, /Total tests: 3, passed: 3, failed: 0/);
});

// Actual Source preflight/parser/index/settings bodies. Only the Native Read
// growth/current port is explicit; this is not a physical Native supplier.
test('Native Host settings runs original staged decoding only after same Read construction admission', {timeout: 90_000}, t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-native-host-settings-parser-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const sourceRoot = new URL('../', import.meta.url);
  const read = path => readFileSync(new URL(path, sourceRoot), 'utf8');
  const blocks = path => read(path).split('///|');
  const pick = (path, marker) => {
    const value = blocks(path).find(body => body.includes(marker));
    assert(value, marker); return value;
  };
  mkdirSync(join(root, 'src'), {recursive: true});
  writeFileSync(join(root, 'moon.mod'), 'name = "actql/actql"\nsource = "src"\n');
  // A finite original production dependency closure, no generated runtime or
  // alternate grammar/encoder. Test-only bodies are not copied or executed.
  const packages = ['canonical_value', 'capacity_arithmetic', 'decode_core', 'decode_scalar',
    'decode_shape', 'encode_core', 'sha256', 'source_span', 'source_value'];
  for (const name of packages) {
    mkdirSync(join(root, 'src', name));
    writeFileSync(join(root, 'src', name, 'moon.pkg'), read(`src/${name}/moon.pkg`));
    for (const file of readdirSync(new URL(`src/${name}/`, sourceRoot))) {
      if (file.endsWith('.mbt') && !/_(?:wb|bb)?test\.mbt$/u.test(file))
        writeFileSync(join(root, 'src', name, file), read(`src/${name}/${file}`));
    }
  }
  for (const name of ['execution', 'arena', 'local_host']) mkdirSync(join(root, 'src', name));
  writeFileSync(join(root, 'src/local_host/moon.pkg'), 'supported_targets = "js"\n');
  writeFileSync(join(root, 'src/local_host/settings.mbt'),
    pick('src/platform_native/client_host/model_http_call.mbt', 'pub(all) struct NativeModelHttpConfigurationFiles {'));
  writeFileSync(join(root, 'src/execution/moon.pkg'), 'supported_targets = "js"\nimport { "actql/actql/capacity_arithmetic" @preparation_counts }\n');
  const representation = read('src/execution_relation/preparation_representation.mbt');
  writeFileSync(join(root, 'src/execution/representation.mbt'), representation.slice(0,
    representation.indexOf('///|\n/// Domain callers supply storage/slot inventories')));
  writeFileSync(join(root, 'src/arena/moon.pkg'), 'supported_targets = "js"\n');
  writeFileSync(join(root, 'src/arena/ports.mbt'), `
pub(all) enum Issue { Refused } derive(Eq, Debug)
pub(all) struct InstalledArenaOriginalRead { marker : Int }
pub(all) struct InstalledArenaHost { original : InstalledArenaOriginalRead; ceiling : Int64; calls : Array[(Int64, Int64, Int64)] }
pub fn InstalledArenaHost::prepare_domain_original_read_construction(self : Self, read : InstalledArenaOriginalRead, r : Int64, e : Int64, raw : Int64) -> Result[Unit, Issue] {
  if !physical_equal(read, self.original) { abort("foreign Read") }
  self.calls.push((r, e, raw))
  if r > self.ceiling || e > self.ceiling { Err(Refused) } else { Ok(()) }
}
`);
  writeFileSync(join(root, 'src/moon.pkg'), 'supported_targets = "js"\nimport { "actql/actql/arena" @initial_arena, "actql/actql/execution" @execution, "actql/actql/local_host" @local_host, "actql/actql/source_value" @source, "actql/actql/decode_core" @decode, "actql/actql/decode_shape" @shape, "moonbitlang/core/encoding/utf8" } for "wbtest"\n');
  const preparation = blocks('src/cmd/native_client/local_host_settings_preparation.mbt')
    .filter(body => !body.includes('fn local_host_configuration_text_file(')).join('///|');
  const settings = ['priv struct LocalHostSettings {', 'priv struct LocalModelHttpInstallationSettings {',
    'fn local_settings_text(', 'fn local_model_http_installation_settings(',
    'fn local_host_journal_record_limit(', 'fn local_host_settings(']
    .map(marker => pick('src/cmd/native_client/local_adoption.mbt', marker)).join('\n');
  const input = pick('src/cmd/native_client/local.mbt', 'fn local_input_cursor(');
  const primary = pick('src/cmd/native_client/local_command_preparation.mbt', 'fn LocalCommandPreparationOriginal::retain_primary(');
  const wire = JSON.stringify({version:'actql-config/0.1', account_config:'account.json', native:{local:{
    account_id:'account', principal:'principal', connection:'connection', state_parent:'/private/tmp', state_name:'state',
    managed_root:'/private/tmp/project', sqlite_library:'/private/libsqlite.dylib', signature_library:'/private/libcrypto.dylib',
    submission_ttl_ms:1000, journal_record_limit:1025, journal_snapshot_bytes:4096,
    installation_files:Array.from({length:9},(_,i)=>`original-${i}.json`),
  }}});
  const withModel = responseProfile => {
    const settings = JSON.parse(wire);
    settings.native.local.model_http_installation = {
      provider_id: 'models/fixture',
      credential_installation: 'original-0.json',
      installation_revision: 'original-1.json',
      configuration_contract: 'original-2.json',
      response_profile: responseProfile,
      response_profile_cid: 'sha256:' + '1'.repeat(64),
      execution_file: 'original-4.json',
      run_policy_file: 'original-5.json',
    };
    return JSON.stringify(settings);
  };
  writeFileSync(join(root, 'src/probe_wbtest.mbt'), `
priv suberror ClientStop { ClientStop(String) }
fn[T] stop(value : String) -> T raise ClientStop { raise ClientStop(value) }
priv enum LocalCommandPreparationIssue { CommandUnavailable; CommandRead(@initial_arena.Issue) } derive(Eq, Debug)
priv struct LocalCommandPreparationOriginal {
  host : @initial_arena.InstalledArenaHost?; read : @initial_arena.InstalledArenaOriginalRead?
  phase_open : Bool; journal_read_open : Bool; closing : Bool; closed : Bool
  mut primary : LocalCommandPreparationIssue?; read_failure : Unit?; mut metadata_retained : Int64
}
let command_preparation_invocation : Ref[LocalCommandPreparationOriginal?] = Ref(None)
fn native_timing_count(_ : Int) -> Unit { () }
fn[T] command_preparation_result(value : Result[T, LocalCommandPreparationIssue], stage? : String? = None) -> T raise ClientStop {
  ignore(stage)
  match value { Ok(value) => value; Err(_) => stop("budget-refused") }
}
${primary}
${preparation}
${settings}
${input}
fn original(ceiling : Int64) -> (LocalCommandPreparationOriginal, @initial_arena.InstalledArenaHost) {
  let read : @initial_arena.InstalledArenaOriginalRead = {marker: 41}
  let host : @initial_arena.InstalledArenaHost = {original: read, ceiling, calls: []}
  ({host: Some(host), read: Some(read), phase_open: true, journal_read_open: false, closing: false, closed: false, primary: None, read_failure: None, metadata_retained: 0L}, host)
}
let original_wire = ${JSON.stringify(wire)}
test "same staged parser accepts padded original Host settings and nine exact names" {
  let (value, host) = original(16000000L)
  command_preparation_invocation.val = Some(value)
  defer { command_preparation_invocation.val = None }
  let selected = local_host_settings(" ".repeat(70000) + original_wire)
  assert_eq(selected.installation_files.length(), 9)
  assert_eq(selected.installation_files[8], "original-8.json")
  assert_eq(selected.record_limit, 1025)
  assert_eq(selected.account_id, "account")
  assert_true(host.calls.length() >= 6)
  assert_eq(host.calls[0].0, 0L)
  assert_true(value.metadata_retained > 0L)
}
test "configured Model HTTP selects only the original admitted installation files" {
  let (value, host) = original(16000000L)
  command_preparation_invocation.val = Some(value)
  defer { command_preparation_invocation.val = None }
  let selected = local_host_settings(${JSON.stringify(withModel('original-3.json'))})
  let model = selected.model_http_installation.unwrap()
  assert_eq(model.files.setting, "original-0.json")
  assert_eq(model.files.installation_revision, "original-1.json")
  assert_eq(model.files.configuration_contract, "original-2.json")
  assert_eq(model.files.response_profile, "original-3.json")
  assert_eq(model.execution_file, Some("original-4.json"))
  assert_eq(model.policy_file, Some("original-5.json"))
  assert_true(host.calls.length() >= 6)
  let refused = try {
    ignore(local_host_settings(${JSON.stringify(withModel('foreign.json'))}))
    ""
  } catch { ClientStop(reason) => reason }
  assert_eq(refused, "LocalModelHttpOriginalNotSelected")
}
test "same original budget refuses before parsed settings can escape" {
  let (value, host) = original(1L)
  command_preparation_invocation.val = Some(value)
  defer { command_preparation_invocation.val = None }
  let stopped = try { ignore(local_host_settings(original_wire)); false } catch { ClientStop(_) => true }
  assert_true(stopped)
  assert_eq(host.calls.length(), 1)
  assert_eq(value.metadata_retained, 0L)
  assert_eq(value.primary, Some(CommandRead(Refused)))
}
test "duplicate schema fields and late duplicate installation names remain refused" {
  for wire in [${JSON.stringify(wire.replace('original-8.json', 'original-0.json'))}, ${JSON.stringify(wire.replace('"version":', '"version":"actql-config/0.1","version":'))}] {
    let (value, _) = original(16000000L)
    command_preparation_invocation.val = Some(value)
    let stopped = try { ignore(local_host_settings(wire)); false } catch { ClientStop(_) => true }
    command_preparation_invocation.val = None
    assert_true(stopped)
  }
}
`);
  const result = spawnSync('moon', ['test', '--target', 'js'], {
    cwd: root, encoding: 'utf8', timeout: 75_000, maxBuffer: 4 * 1024 * 1024,
  });
  assert.equal(result.error, undefined, result.error?.message);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout + result.stderr, /Total tests: 4, passed: 4, failed: 0/);
});
