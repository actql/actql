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
const serialDependencyFunding = new Set([
  'begin_keyed_dependency_serial_cursor', 'grow_keyed_dependency_body',
]);
const serialDependencyModule = directory + 'client_keyed_dependency_serial_cursor.mbt';
const measuredDependencyRange = 'ReturnedKeyedDependencyRange';
const serialPrivateTypes = new Set([
  'KeyedDependencySerialCursor', 'KeyedDependencySerialCompletion', 'KeyedDependencyWitnessChunk',
]);
const serialConstructorFields = new Map([
  ['extent_workspace_depth', 'begin_keyed_dependency_serial_cursor'],
  ['serial_range', 'close_keyed_dependency_collection'],
  ['serial_witness', 'begin_keyed_dependency_serial_cursor'],
]);
const serialDependencyConsumers = new Set([
  `${directory}client_keyed_declared_file_journal.mbt:prepare_declared_file_lookup_dependencies`,
  `${directory}client_effect_generic_keyed_dependency.mbt:prepare_client_effect_keyed_generic_dependencies`,
]);
const scanBuilders = new Set([
  'scan_keyed_lookup_identity_bodies', 'scan_client_keyed_native_left_identity',
  'scan_client_keyed_native_page', 'scan_client_keyed_native_whole_source',
]);
const identity = ([module, name]) => `${module}:${name}`;
const common = directory + 'client_keyed_protocol_construction.mbt';
const dependencyCollection = 'with_keyed_dependency_collection';
const protocolOwners = new Set(['with_keyed_protocol_construction', dependencyCollection]);
const beginFinish = new Set(['grow_keyed_lookup_protocol_metadata', 'finish_keyed_lookup_protocol_metadata']);
const privateTypes = new Set(['KeyedProtocolConstruction', 'KeyedProtocolBuilt', 'KeyedProtocolDependencies', 'SettledKeyedProtocolMetadata', 'KeyedBodyConstruction']);
const rawResource = new Set(['grow_execution_reservation_capacity', 'reduce_execution_reservation_capacity',
  'reduce_execution_reservation']);
const interpolationOperations = /\b(?:grow_keyed_lookup_protocol_metadata|finish_keyed_lookup_protocol_metadata|keyed_lookup_body_grow|keyed_protocol_built|grow_keyed_body_construction|with_keyed_body_construction|with_keyed_dependency_collection|complete_unmeasured_keyed_dependencies|close_keyed_dependency_collection|begin_keyed_dependency_serial_cursor|grow_keyed_dependency_body|ReturnedKeyedDependencyRange|KeyedDependencySerialCursor|KeyedDependencySerialCompletion|KeyedDependencyWitnessChunk|scan_keyed_lookup_identity_bodies|scan_client_keyed_native_left_identity|scan_client_keyed_native_page|scan_client_keyed_native_whole_source|grow_execution_reservation_capacity|reduce_execution_reservation_capacity|reduce_execution_reservation|retained_bytes|execution_bytes)\b/u;
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
  [...entry('client_keyed_dependency_serial_cursor', 'begin_keyed_dependency_serial_cursor'), 'temporary serial cursor and funding closures'],
  [...entry('client_keyed_dependency_serial_cursor', 'grow_keyed_dependency_body'), 'same-lookup body and cursor allowance'],
  [...entry('client_keyed_dependency_serial_cursor', 'KeyedDependencySerialCursor::fund_keyed_dependency_witness'), 'prepaid original reference chunks'],
  [...entry('client_keyed_protocol_construction', 'with_keyed_body_construction'), 'original scan first-entry backing'],
  [...entry('client_keyed_protocol_construction', dependencyCollection), 'same-lookup completion and adopted slot observation'],
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
    let functionName = list[name].value;
    if (list[name + 1]?.value === ':' && list[name + 2]?.value === ':' &&
        list[name + 3]?.kind === 'word') {
      declarations.add(name);
      name += 3;
      functionName += `::${list[name].value}`;
    }
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
    result.push({name: functionName, start: i, body: j, end});
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
      if (list[i].kind === 'word' && (protocolOwners.has(list[i].value) || list[i].value === 'with_keyed_body_construction') &&
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
        const wrapper = serialDependencyConsumers.has(id) ? dependencyCollection : 'with_keyed_protocol_construction';
        if (!scopes.some(([start, end, kind]) => start > fn.body && end < fn.end &&
            kind === wrapper)) issue('missing-managed-construction', fn.body, fn);
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
      if (beginFinish.has(token.value) && !(module === common && protocolOwners.has(fn?.name))) {
        issue('manual-protocol-phase', i);
      }
      if (token.value === dependencyCollection && !serialDependencyConsumers.has(id) ||
          token.value === 'complete_unmeasured_keyed_dependencies' &&
            !(serialDependencyConsumers.has(id) && inScope(i)) ||
          token.value === 'close_keyed_dependency_collection' &&
            !(module === serialDependencyModule &&
              ['KeyedDependencySerialCursor::seal', 'complete_unmeasured_keyed_dependencies'].includes(fn?.name))) {
        issue('private-serial-dependency-forgery', i);
      }
      if ((token.value === 'grow_keyed_body_construction' || token.value === 'keyed_body_construction_controls') &&
          !(module === common && fn?.name === 'with_keyed_body_construction')) issue('manual-scan-phase', i);
      if (serialDependencyFunding.has(token.value) &&
          !(serialDependencyConsumers.has(id) && inScope(i) ||
            module === serialDependencyModule && bodyGrowthOwners.has(id))) {
        issue('unclassified-serial-dependency-funding', i);
      }
      if (token.value === measuredDependencyRange) {
        const prior = list[i - 1]?.value;
        const declaration = module === serialDependencyModule && fn === undefined && prior === '{' &&
          list[i - 2]?.value === 'KeyedDependencyMeasuredBodies' && list[i - 3]?.value === 'enum';
        const issuer = module === serialDependencyModule && fn?.name === 'KeyedDependencySerialCursor::record_body';
        const sealPattern = module === serialDependencyModule && fn?.name === 'KeyedDependencySerialCursor::seal' &&
          list[i - 2]?.value === 'Some' && prior === '(' && list[i + 2]?.value === 'bodies' &&
          list[i + 3]?.value === '=';
        const settlementPattern = module === directory + 'client_keyed_lookup_identity.mbt' &&
          fn?.name === 'finish_keyed_lookup_protocol_metadata' && ['let', 'is'].includes(prior);
        if (!declaration && !issuer && !sealPattern && !settlementPattern) issue('unclassified-measured-dependency-range', i);
      }
      if (token.value === 'Measured' && list[i + 1]?.value === '(' &&
          !(module === common && fn === undefined ||
            module === common && fn?.name === dependencyCollection ||
            module === directory + 'client_keyed_lookup_identity.mbt' &&
              fn?.name === 'finish_keyed_lookup_protocol_metadata')) {
        issue('private-serial-dependency-forgery', i);
      }
      if (serialPrivateTypes.has(token.value)) {
        const offsets = list.slice(i + 1, i + 4).map(item => item.value);
        const literal = offsets[0] === '{' || offsets[0] === '::' && offsets[1] === '{' ||
          offsets[0] === ':' && offsets[1] === ':' && offsets[2] === '{';
        const issuer = token.value === 'KeyedDependencySerialCursor' ? 'begin_keyed_dependency_serial_cursor' :
          token.value === 'KeyedDependencySerialCompletion' ? 'close_keyed_dependency_collection' :
            'KeyedDependencySerialCursor::remember_original';
        const serialBody = module === serialDependencyModule;
        const declaration = serialBody && fn === undefined && list[i - 1]?.value === 'struct';
        const sharedType = module === common && token.value === 'KeyedDependencySerialCompletion' &&
          (list[i - 2]?.value === 'Measured' && list[i - 1]?.value === '(' ||
            [dependencyCollection, 'validate_completed_keyed_dependencies'].includes(fn?.name));
        const consumerType = serialDependencyConsumers.has(id) && inScope(i) &&
          token.value === 'KeyedDependencySerialCursor' && list[i - 1]?.value === ':';
        if (!declaration && (literal ? (!serialBody || fn?.name !== issuer) : !(serialBody || sharedType || consumerType))) {
          issue('private-serial-dependency-forgery', i);
        }
      }
      if (serialConstructorFields.has(token.value) && ['{', ','].includes(list[i - 1]?.value) &&
          [':', ',', '}'].includes(list[i + 1]?.value)) {
        const issuer = serialConstructorFields.get(token.value);
        const sealWitness = token.value === 'serial_witness' && fn?.name === 'close_keyed_dependency_collection';
        if (module !== serialDependencyModule || (fn?.name !== issuer && !sealWitness)) {
          issue('private-serial-dependency-forgery', i);
        }
      }
      if (scanBuilders.has(token.value) && !inScope(i)) issue('unsettled-scan-builder', i);
      if (rawResource.has(token.value) && (keyedOwner || fn === undefined) && !lowOwners.has(id)) issue('unclassified-reservation-mutation', i);
      if (token.value === 'keyed_lookup_body_grow' && !inScope(i) && !bodyGrowthOwners.has(id)) issue('unclassified-body-growth', i);
      if (token.value === 'keyed_protocol_built' &&
          !scopes.some(([start, end, kind]) => i > start && i < end &&
            kind === 'with_keyed_protocol_construction')) issue('unsettled-builder-escape', i);
      if (privateTypes.has(token.value)) {
        const declaration = ['struct', 'enum'].includes(list[i - 1]?.value) &&
          module === common;
        const owner = module === common && [...protocolOwners, 'keyed_protocol_built', 'validate_completed_keyed_dependencies', 'with_keyed_body_construction', 'grow_keyed_body_construction'].includes(fn?.name) ||
          module === directory + 'client_keyed_lookup_identity.mbt' && beginFinish.has(fn?.name);
        const serialPhase = module === serialDependencyModule && token.value === 'KeyedProtocolConstruction' &&
          (fn === undefined || ['begin_keyed_dependency_serial_cursor', 'complete_unmeasured_keyed_dependencies',
            'close_keyed_dependency_collection'].includes(fn?.name));
        if (!declaration && !owner && !serialPhase && !inScope(i)) {
          issue('private-construction-forgery', i);
        }
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
