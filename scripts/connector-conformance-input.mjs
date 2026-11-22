// The CLI and the installed runner select the same finite input.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {isAbsolute} from 'node:path';

const sha256 = value => typeof value === 'string' && /^[a-f0-9]{64}$/u.test(value);
const gitIdentity = value => typeof value === 'string' && /^[a-f0-9]{40}$/u.test(value);
const absolute = value => typeof value === 'string' && isAbsolute(value);

export function readRestConformanceInput(path) {
  const selected = JSON.parse(readFileSync(path, 'utf8'));
  const fields = ['kind', 'sourceSha', 'sourceTree', 'manifestPath',
    'manifestSha256', 'outputRoot', 'accountConfigurationPath', 'mode'];
  if (selected?.mode === 'author') fields.push('casePath', 'caseSha256');
  assert(selected !== null && typeof selected === 'object' && !Array.isArray(selected) &&
    Object.keys(selected).length === fields.length && fields.every(key => Object.hasOwn(selected, key)) &&
    selected.kind === 'actql-standard-rest-normal/0.1' &&
    ['empty', 'one', 'paged', 'notion-users', 'author'].includes(selected.mode) &&
    gitIdentity(selected.sourceSha) && gitIdentity(selected.sourceTree) &&
    sha256(selected.manifestSha256) &&
    ['manifestPath', 'outputRoot', 'accountConfigurationPath'].every(key => absolute(selected[key])) &&
    (selected.mode !== 'author' || absolute(selected.casePath) && sha256(selected.caseSha256)),
  'Invalid actql-standard-rest-normal/0.1 descriptor; select a runtime, Account and case explicitly');
  return selected;
}
