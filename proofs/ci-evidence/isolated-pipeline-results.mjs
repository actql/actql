// Local pipeline consumers are loaded only after selecting a pipeline profile.
// Session execution must not evaluate the pipeline oracle/receipt import graph.
import assert from 'node:assert/strict';
import {encode} from '../bounded-session/action-inputs.mjs';
import {validatePristineReport} from '../relation-pipeline/pristine-replay.mjs';
import {validateRequestedProgram} from '../relation-pipeline/execution-original.mjs';
import {validateFixedJsReport} from '../relation-pipeline/fixed-js-replay.mjs';

export function checkPipelinePristineResult({payload, manifest, before}) {
  assert.equal(manifest.version, 'actql-isolated-pipeline-pristine-inputs/0.1');
  assert.equal(payload.version, 'actql-isolated-pipeline-pristine-observation/0.1');
  for (const field of ['root', 'platformInputs', 'environment'])
    assert.equal(encode(payload[field]), encode(manifest[field]), 'Changed physical pipeline input');
  assert.equal(payload.readOnlyConfirmed, true); assert.equal(payload.shellStartupConfirmed, true);
  assert.equal(payload.sourcePreserved, true); assert.equal(payload.reuseAuthorized, false);
  return validatePipelinePristineOriginal(payload.report, before, payload.files);
}

export function validatePipelinePristineOriginal(report, source, files) {
  validatePristineReport(report, source, files);
  for (const {receipt} of report.receipts) validateRequestedProgram(receipt);
  return true;
}

export function checkPipelineFixedJsResult({payload, manifest, before, tree}) {
  assert.equal(manifest.version, 'actql-isolated-pipeline-fixed-js-inputs/0.1');
  assert.equal(payload.version, 'actql-isolated-pipeline-fixed-js-observation/0.1');
  for (const field of ['root', 'platformInputs', 'environment'])
    assert.equal(encode(payload[field]), encode(manifest[field]), 'Changed physical pipeline input');
  assert.equal(payload.readOnlyConfirmed, true); assert.equal(payload.shellStartupConfirmed, true);
  assert.equal(payload.sourcePreserved, true); assert.equal(payload.reuseAuthorized, false);
  assert.equal(manifest.testedRevision, tree.revision);
  return validateFixedJsReport({report: payload.report, source: before, files: payload.files,
    revision: tree.revision, readSource: path => tree.read(path)});
}
