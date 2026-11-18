// Narrow source-side guard for the frozen original keyed protocol lifecycle.
// The compiler owns typing; actual Owner tests own lifetime/settlement proof.
// This token guard does not prove arbitrary callback control flow or foreign ABI safety.
import {readFileSync, readdirSync} from 'node:fs';
import {join} from 'node:path';
import {tokens} from './portable-core.mjs';

const directory = 'src/run_publication_host/';
const entry = (file, name) => [directory + file + '.mbt', name];
export const keyedProtocolConstructionInventory = Object.freeze([
  entry('client_keyed_declared_file_journal', 'prepare_declared_file_lookup_dependencies'),
  entry('client_effect_generic_keyed_dependency', 'prepare_client_effect_keyed_generic_dependencies'),
  entry('client_keyed_native_transport', 'prepare_client_keyed_native_transport'),
  entry('client_effect_generic_keyed_completion', 'prepare_client_effect_keyed_generic_source_metadata'),
  entry('client_effect_generic_keyed_completion', 'prepare_client_effect_keyed_generic_completion'),
  entry('client_keyed_captured_source_metadata', 'bind_client_keyed_captured_source_metadata'),
  entry('client_keyed_declared_file_journal', 'prepare_client_keyed_declared_file_activation_record_original'),
  entry('client_keyed_declared_file_journal', 'prepare_client_keyed_declared_file_retention'),
  entry('client_keyed_declared_file_journal', 'prepare_client_keyed_declared_file_page_record_original'),
  entry('client_keyed_declared_file_journal', 'prepare_client_keyed_declared_file_raw_capture'),
  entry('client_keyed_lookup_identity', 'prepare_keyed_lookup_request_metadata'),
  entry('client_keyed_native_activation', 'prepare_client_keyed_native_activation'),
  entry('client_keyed_native_completion', 'prepare_native_keyed_lookup_completion'),
  entry('client_keyed_native_page', 'build_client_keyed_native_captured_page'),
  entry('client_keyed_native_raw_response', 'prepare_client_keyed_native_raw_response'),
  entry('client_keyed_native_sources', 'build_client_keyed_native_whole_source_evidence'),
  entry('client_keyed_native_sources', 'prepare_client_keyed_native_left_relation'),
  entry('client_keyed_request_plan', 'prepare_client_keyed_native_batch_plan'),
].map(Object.freeze));
export const keyedScanConstructionInventory = Object.freeze([
  entry('client_keyed_lookup_body', 'build_keyed_lookup_identity_bodies'),
  entry('client_keyed_native_left_identity', 'build_client_keyed_native_left_identity'),
  entry('client_keyed_native_page', 'build_client_keyed_native_captured_page'),
  entry('client_keyed_native_sources', 'build_client_keyed_native_whole_source_evidence'),
].map(Object.freeze));
const scanBuilders = new Set([
  'scan_keyed_lookup_identity_bodies', 'scan_client_keyed_native_left_identity',
  'scan_client_keyed_native_page', 'scan_client_keyed_native_whole_source',
]);
const identity = ([module, name]) => `${module}:${name}`;
const common = directory + 'client_keyed_protocol_construction.mbt';
const beginFinish = new Set(['grow_keyed_lookup_protocol_metadata', 'finish_keyed_lookup_protocol_metadata']);
const privateTypes = new Set(['KeyedProtocolConstruction', 'KeyedProtocolBuilt', 'SettledKeyedProtocolMetadata', 'KeyedBodyConstruction']);
const rawResource = new Set(['grow_execution_reservation_capacity', 'reduce_execution_reservation_capacity',
  'reduce_execution_reservation']);
const interpolationOperations = /\b(?:grow_keyed_lookup_protocol_metadata|finish_keyed_lookup_protocol_metadata|keyed_lookup_body_grow|keyed_protocol_built|grow_keyed_body_construction|with_keyed_body_construction|scan_keyed_lookup_identity_bodies|scan_client_keyed_native_left_identity|scan_client_keyed_native_page|scan_client_keyed_native_whole_source|grow_execution_reservation_capacity|reduce_execution_reservation_capacity|reduce_execution_reservation|retained_bytes|execution_bytes)\b/u;
const lowOwners = new Set([
  entry('client_keyed_lookup_body', 'keyed_lookup_body_grow'),
  entry('client_keyed_lookup_identity', 'grow_keyed_lookup_protocol_metadata'),
  entry('client_keyed_lookup_identity', 'finish_keyed_lookup_protocol_metadata'),
  entry('client_keyed_protocol_construction', 'with_keyed_body_construction'),
  // Different lifetimes: persistent Request/cache entries and resumable wire/response intake.
  entry('client_keyed_request_plan', 'keyed_lookup_plan_grow'),
  entry('client_keyed_lookup_input', 'keyed_lookup_grow_execution'),
  entry('client_keyed_lookup_input', 'begin_client_keyed_lookup_response'),
].map(identity));
// Operation/function exceptions, never whole-file exemptions. Their backing is
// retained at an independently owned predecessor/physical lifetime. The four
// finished scan portions now use their separate original managed construction.
const bodyGrowthOwners = new Map([
  [...entry('client_keyed_protocol_construction', 'with_keyed_body_construction'), 'original scan first-entry backing'],
  [...entry('client_keyed_protocol_construction', 'grow_keyed_body_construction'), 'latched original scan grow port'],
  [...entry('client_keyed_lookup_identity', 'finish_keyed_lookup_protocol_metadata'), 'pre-admitted extent walk'],
  [...entry('client_keyed_lookup_body', 'build_keyed_lookup_identity_bodies'), 'original supplied-input/output predecessor'],
  [...entry('client_keyed_native_page', 'build_client_keyed_native_captured_page'), 'original RowRun/capture/output predecessor'],
  [...entry('client_keyed_native_sources', 'keyed_lookup_source_metadata_state'), 'retained Source state'],
  [...entry('client_keyed_declared_file_journal', 'prepare_client_keyed_declared_file_raw_store'), 'physical Store/failed-writer overlap'],
  [...entry('client_keyed_declared_file_journal', 'bind_client_keyed_declared_file_physical_source'), 'retained immutable Source aliases'],
  [...entry('client_effect_generic_keyed_completion', 'finish_client_effect_keyed_generic_publication_input'), 'retained observation controls'],
  [...entry('client_effect_generic_keyed_completion', 'prepare_client_effect_keyed_generic_source_metadata'), 'retained generic Source/state controls'],
].map(([module, name, reason]) => [`${module}:${name}`, reason]));

function close(list, start, open, end) {
  let depth = 0;
  for (let i = start; i < list.length; i++) {
    if (list[i].kind !== 'symbol') continue;
    if (list[i].value === open) depth++;
    else if (list[i].value === end && --depth === 0) return i;
  }
  throw new Error(`Unclosed lifecycle delimiter ${open}`);
}

// Named top-level functions and their balanced bodies only, using the existing
// comment/string-aware lexer. No evaluation, source slicing execution or new parser.
function functions(list) {
  const result = [], declarations = new Set();
  let depth = 0;
  for (let i = 0; i < list.length; i++) {
    if (list[i].kind === 'symbol' && list[i].value === '{') depth++;
    if (list[i].kind === 'symbol' && list[i].value === '}') depth--;
    if (depth !== 0 || list[i].kind !== 'word' || list[i].value !== 'fn') continue;
    let name = i + 1;
    if (list[name]?.value === '[') name = close(list, name, '[', ']') + 1;
    if (list[name]?.kind !== 'word') continue;
    declarations.add(name);
    let j = name + 1, parens = 0, brackets = 0;
    for (; j < list.length; j++) {
      if (list[j].kind !== 'symbol') continue;
      const value = list[j].value;
      if (value === '(') parens++;
      if (value === ')') parens--;
      if (value === '[') brackets++;
      if (value === ']') brackets--;
      if (parens === 0 && brackets === 0 && ['{', '='].includes(value)) break;
    }
    if (list[j]?.value !== '{') continue;
    const end = close(list, j, '{', '}');
    result.push({name: list[name].value, start: i, body: j, end});
    i = end;
  }
  return {result, declarations};
}

export function resourceLifecycleProblems(sources, {
  inventory = keyedProtocolConstructionInventory,
  scanInventory = inventory === keyedProtocolConstructionInventory ? keyedScanConstructionInventory : [],
} = {}) {
  const problems = [], found = new Set(), expected = new Set(inventory.map(identity));
  const scanExpected = new Set(scanInventory.map(identity));
  for (const [module, source] of sources) {
    const list = tokens(source, true, true);
    const parsed = functions(list);
    for (const fn of parsed.result) {
      fn.keyedOwner = /\/client_(?:keyed_|effect_generic_keyed_)/u.test(module) ||
        list.slice(fn.start, fn.body).some(value => value.kind === 'word' && value.value === 'ClientKeyedLookupInput');
      fn.resourceReferences = list.slice(fn.body, fn.end).some(value => value.kind === 'word' &&
        (rawResource.has(value.value) || beginFinish.has(value.value) || ['keyed_lookup_body_grow', 'grow_keyed_body_construction'].includes(value.value)));
    }
    const scopes = [];
    const at = index => parsed.result.find(fn => index >= fn.start && index <= fn.end);
    const issue = (rule, index, fn = at(index)) => problems.push({module, function: fn?.name,
      rule, offset: list[index]?.begin ?? 0});
    for (let i = 0; i < list.length; i++) {
      if (list[i].kind === 'word' && ['with_keyed_protocol_construction', 'with_keyed_body_construction'].includes(list[i].value) &&
          list[i + 1]?.value === '(' && !parsed.declarations.has(i)) {
        scopes.push([i, close(list, i + 1, '(', ')'), list[i].value]);
      }
    }
    const inScope = index => scopes.some(([start, end]) => index > start && index < end);
    for (const fn of parsed.result) {
      const id = `${module}:${fn.name}`;
      if (scanExpected.has(id)) {
        found.add(id);
        if (!scopes.some(([start, end, kind]) => start > fn.body && end < fn.end &&
            kind === 'with_keyed_body_construction')) issue('missing-managed-scan', fn.body, fn);
      }
      if (expected.has(id)) {
        found.add(id);
        if (!scopes.some(([start, end]) => start > fn.body && end < fn.end)) issue('missing-managed-construction', fn.body, fn);
      }
    }
    for (let i = 0; i < list.length; i++) {
      const token = list[i], fn = at(i), id = `${module}:${fn?.name}`;
      const keyedOwner = fn?.keyedOwner === true;
      if (token.kind === 'string') {
        // Executable interpolation is not opaque DATA. Unknown interpolation
        // in an owned construction is refused, rather than silently ignored.
        if ((keyedOwner || fn?.resourceReferences || expected.has(id) || interpolationOperations.test(token.value)) &&
            /(?<!\\)(?:\\\\)*\\\{/u.test(token.value) &&
            !source.slice(token.begin, token.end).startsWith('#|')) issue('unclassified-interpolation', i);
        continue;
      }
      if (token.kind !== 'word' || parsed.declarations.has(i)) continue;
      if (beginFinish.has(token.value) && !(module === common && fn?.name === 'with_keyed_protocol_construction')) {
        issue('manual-protocol-phase', i);
      }
      if ((token.value === 'grow_keyed_body_construction' || token.value === 'keyed_body_construction_controls') &&
          !(module === common && fn?.name === 'with_keyed_body_construction')) issue('manual-scan-phase', i);
      if (scanBuilders.has(token.value) && !inScope(i)) issue('unsettled-scan-builder', i);
      if (rawResource.has(token.value) && (keyedOwner || fn === undefined) && !lowOwners.has(id)) issue('unclassified-reservation-mutation', i);
      if (token.value === 'keyed_lookup_body_grow' && !inScope(i) && !bodyGrowthOwners.has(id)) issue('unclassified-body-growth', i);
      if (token.value === 'keyed_protocol_built' && !inScope(i)) issue('unsettled-builder-escape', i);
      if (privateTypes.has(token.value)) {
        const declaration = ['struct', 'enum'].includes(list[i - 1]?.value) &&
          module === common;
        const owner = module === common && ['keyed_protocol_built', 'with_keyed_protocol_construction', 'with_keyed_body_construction', 'grow_keyed_body_construction'].includes(fn?.name) ||
          module === directory + 'client_keyed_lookup_identity.mbt' && beginFinish.has(fn?.name);
        if (!declaration && !owner && !inScope(i)) issue('private-construction-forgery', i);
      }
      if (['retained_bytes', 'execution_bytes'].includes(token.value) && list[i - 1]?.value === '.') {
        const next = list[i + 1]?.value, following = list[i + 2]?.value;
        if (keyedOwner && (next === '=' && following !== '=' || ['+', '-'].includes(next) && following === '=') && !lowOwners.has(id)) {
          issue('direct-byte-custody-assignment', i);
        }
      }
      const qualifiedConstructor = list[i - 1]?.value === '.' && list[i - 3]?.value === '@' &&
        (list[i - 2]?.value === 'encode' && ['writer', 'hashing_writer'].includes(token.value) ||
         list[i - 2]?.value === 'publication' && token.value.startsWith('issue_') ||
         list[i - 2]?.value === 'acquisition' && token.value === 'parameterized_request_canonical_document');
      if (expected.has(id) && !inScope(i) && (qualifiedConstructor || token.value === 'native_lookup_seal')) {
        issue('constructor-outside-managed-scope', i);
      }
      if (token.value === 'ClientKeyedLookupInput' && fn === undefined && list[i - 1]?.value === '=') {
        issue('unclassified-lookup-type-alias', i);
      }
    }
  }
  for (const id of [...expected, ...scanExpected]) if (!found.has(id)) problems.push({rule: 'missing-inventory-function', function: id});
  return problems;
}

export function checkResourceLifecycle(root) {
  const names = readdirSync(join(root, directory)).filter(name => name.endsWith('.mbt') &&
    !/_(?:wb|bb)?test\.mbt$/u.test(name) && !name.includes('.generated.'));
  const sources = new Map(names.map(name => [directory + name, readFileSync(join(root, directory, name), 'utf8')]));
  return {problems: resourceLifecycleProblems(sources),
    qualification: 'Narrow original keyed lifecycle token/issuer/custody guard; not complete control-flow or runtime proof',
    equivalentFunctions: keyedProtocolConstructionInventory.length,
    mixedScanFunctions: keyedScanConstructionInventory.length};
}
