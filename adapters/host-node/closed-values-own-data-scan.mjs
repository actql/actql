import {types} from 'node:util';

const DECLINED = Symbol('closed Values proof unavailable');
const HEADER_TOKEN = Symbol('private Closed Values header constructor');
const objectPrototype = Object.prototype;
const arrayPrototype = Array.prototype;
const ownDescriptor = Object.getOwnPropertyDescriptor;
const prototypeOf = Object.getPrototypeOf;
const isArray = Array.isArray;
const isProxy = types.isProxy;

// Logical owned allocations only, NOT V8 heap/RSS bytes or a grant. The
// original Root must admit this before header/scan. State and returned facts,
// two overlapping descriptor objects, and the input-bound header: 5 records.
// References: phase1 + descriptors4 (accessor get/set maxima) + header3.
// Scalars: state12 + facts13 + descriptor flags6 + header F/R/retired3.
// Fixed nonrecursive VM frames/module methods belong to runtime baseline;
// unlike the previous historical vector they are not charged per request.
// No per-call closure or input-sized key/descriptor array is created here.
// V8 internal enumeration backing/GC remain explicitly opaque.
export const closedValuesOwnDataScanControlInventory = Object.freeze({
  recordHeaders: 5, referenceSlots: 8, scalarWords: 34,
  ownedUtf16Units: 0, ownedWireBytes: 0,
});

function work(s, amount = 1) {
  s.phase.spendWork(amount); // SAME original admitted scan owner, before work.
  s.work += amount;
  if (!Number.isSafeInteger(s.work)) throw DECLINED;
}
function add(s, amount) {
  if (!Number.isSafeInteger(amount) || amount < 0 ||
      !Number.isSafeInteger(s.bytes + amount)) throw DECLINED;
  s.bytes += amount;
}
function descriptor(s, value, key) {
  work(s);
  return ownDescriptor(value, key);
}
function noToJson(s, value) {
  const d = descriptor(s, value, 'toJSON');
  if (d !== undefined && (!Object.hasOwn(d, 'value') || d.value !== undefined)) throw DECLINED;
}
function plain(s, value, array) {
  work(s);
  if (value === null || typeof value !== 'object' || isProxy(value) ||
      isArray(value) !== array) throw DECLINED;
  const prototype = prototypeOf(value);
  if (prototype !== null && prototype !== (array ? arrayPrototype : objectPrototype)) throw DECLINED;
  noToJson(s, value);
  noToJson(s, objectPrototype);
  if (array) noToJson(s, arrayPrototype);
}
function data(s, value, key) {
  const d = descriptor(s, value, key);
  if (d === undefined || !Object.hasOwn(d, 'value') || !d.enumerable) throw DECLINED;
  return d.value;
}
function text(s, value) {
  if (typeof value !== 'string') throw DECLINED;
  // Allocation-free source JSON envelope, not lexical/semantic admission.
  // JSON.stringify needs at most six bytes per UTF16 unit (escaping covers
  // controls, lone surrogates and supplementary pairs). Common later checks
  // ASCII eligibility on the funded original serialization.
  work(s);
  if (s.ascii) for (let i = 0; i < value.length; i++) {
    work(s);
    const unit = value.charCodeAt(i);
    if (unit < 0x20 || unit > 0x7e || unit === 0x22 || unit === 0x5c) throw DECLINED;
  }
  s.quoted++; s.units += value.length;
  s.longestQuoted = Math.max(s.longestQuoted, value.length);
  add(s, value.length * 6 + 2);
}
function record(s, value, expected, depth) {
  plain(s, value, false);
  let count = 0;
  // Bounded visible traversal; no claim is made about V8's hidden enum cache.
  // Proxies/custom prototypes were declined before enumeration can trap.
  for (const key in value) {
    work(s);
    const d = descriptor(s, value, key);
    // An inherited enumerable key must not extend the F/R work envelope.
    if (d === undefined || !d.enumerable) throw DECLINED;
    if (!Object.hasOwn(d, 'value') || ++count > expected) throw DECLINED;
    text(s, key); add(s, 1); s.fields++;
  }
  if (count !== expected) throw DECLINED;
  s.objects++; s.depth = Math.max(s.depth, depth);
  add(s, 2 + Math.max(0, count - 1));
}
function array(s, value, depth) {
  plain(s, value, true);
  const length = descriptor(s, value, 'length')?.value;
  if (!Number.isSafeInteger(length) || length < 0) throw DECLINED;
  s.arrays++; s.depth = Math.max(s.depth, depth);
  add(s, 2 + Math.max(0, length - 1));
  return length;
}
function item(s, value, index) { return data(s, value, index); }
function singleKey(s, value, depth) {
  record(s, value, 1, depth);
  for (const key in value) { work(s); return key; }
  throw DECLINED;
}
function number(s, value) {
  work(s);
  if (typeof value !== 'number' || !Number.isFinite(value)) throw DECLINED;
  // Common finite binary64 wire proof: longest accepted lexeme is <=25 bytes.
  // No toString/stringify allocation occurs during this inspection.
  s.atoms++; s.longestAtom = Math.max(s.longestAtom, 25); add(s, 25);
}
function falseValue(s, value) {
  work(s);
  if (value !== false) throw DECLINED;
  s.atoms++; s.longestAtom = Math.max(s.longestAtom, 5); add(s, 5);
}

// Precondition: phase is an internal adapter over the already admitted SAME
// Root scan-control reservation. It is not a public SDK numeric budget API.
// Unsupported/callback-bearing inputs return undefined WITHOUT invoking them;
// the owner chooses the unchanged conservative path and retires this phase.
export function scanClosedValuesOwnData(input, options, phase, header) {
  return scanClosedValues(input, options, phase, header, false);
}
// Second, separately funded eligibility phase BEFORE SDK serialization. Its
// work bound is the original structural W plus first-pass quotedUtf16Units.
// Unsupported text declines to legacy only after the original owner cleans up;
// this function never releases capacity or invokes a fallback itself.
export function scanClosedValuesOwnDataAscii(input, options, phase) {
  return scanClosedValues(input, options, phase, undefined, true);
}
function scanClosedValues(input, options, phase, header, ascii) {
  if (options !== undefined || prototypeOf(objectPrototype) !== null ||
      prototypeOf(arrayPrototype) !== objectPrototype) return undefined;
  if (header !== undefined && !ClosedValuesHeader.matches(header, input)) return undefined;
  const s = {phase, ascii, bytes:0, work:0, objects:0, arrays:0, fields:0,
    quoted:0, units:0, longestQuoted:0, longestAtom:0, atoms:0, depth:0};
  try {
    record(s, input, 4, 1);
    const version = data(s, input, 'version'); if (version !== 'actql/0.1') throw DECLINED; text(s, version);
    text(s, data(s, input, 'id'));
    const stages = data(s, input, 'stages'); if (array(s, stages, 2) !== 1) throw DECLINED;
    const stage = item(s, stages, 0); record(s, stage, 4, 3);
    const stageId = data(s, stage, 'id'); text(s, stageId);
    record(s, data(s, stage, 'inputs'), 0, 4);
    const steps = data(s, stage, 'steps'); if (array(s, steps, 4) !== 1) throw DECLINED;
    const step = item(s, steps, 0); record(s, step, 2, 5);
    const stepName = data(s, step, 'as'); text(s, stepName);
    const values = data(s, step, 'values'); record(s, values, 2, 6);
    const stageResults = data(s, stage, 'results');
    const resultName = singleKey(s, stageResults, 4);
    const selection = data(s, stageResults, resultName); record(s, selection, 2, 5);
    const from = data(s, selection, 'from'); if (from !== stepName) throw DECLINED; text(s, from);
    const fields = data(s, selection, 'fields'); const fieldCount = array(s, fields, 6);
    if (fieldCount === 0 || header !== undefined && !header.matchesFields(fields, fieldCount)) throw DECLINED;
    for (let i = 0; i < fieldCount; i++) {
      const field = item(s, fields, i); text(s, field);
      for (let j = 0; j < i; j++) { work(s); if (item(s, fields, j) === field) throw DECLINED; }
    }
    const schema = data(s, values, 'schema'); record(s, schema, fieldCount, 7);
    for (let i = 0; i < fieldCount; i++) {
      const field = item(s, fields, i), contract = data(s, schema, field);
      record(s, contract, 2, 8);
      const type = data(s, contract, 'type'); if (type !== 'number') throw DECLINED; text(s, type);
      falseValue(s, data(s, contract, 'nullable'));
    }
    const rows = data(s, values, 'rows'); const rowCount = array(s, rows, 7);
    if (header !== undefined && !header.matchesRows(rows, rowCount)) throw DECLINED;
    for (let r = 0; r < rowCount; r++) {
      const row = item(s, rows, r); record(s, row, fieldCount, 8);
      for (let c = 0; c < fieldCount; c++) number(s, data(s, row, item(s, fields, c)));
    }
    const results = data(s, input, 'results'), alias = singleKey(s, results, 2);
    const rootResult = data(s, results, alias); record(s, rootResult, 1, 3);
    const rootFrom = data(s, rootResult, 'from'); record(s, rootFrom, 2, 4);
    const selectedStage = data(s, rootFrom, 'stage'), selectedResult = data(s, rootFrom, 'result');
    if (selectedStage !== stageId || selectedResult !== resultName) throw DECLINED;
    text(s, selectedStage); text(s, selectedResult);
    return Object.freeze({inputBytesUpper:s.bytes,
      nodeUpper:s.objects+s.arrays+s.quoted+s.atoms, objects:s.objects,arrays:s.arrays,
      fieldsUpper:s.fields,quotedTokens:s.quoted,quotedUtf16Units:s.units,
      longestQuotedUtf16:s.longestQuoted,longestAtomUtf16:s.longestAtom,
      depthUpper:s.depth,rowCount,fieldCount,inspectionWork:s.work});
  } catch (cause) {
    if (cause === DECLINED) return undefined;
    throw cause; // Original resource refusal/uncertainty is never fallback success.
  } finally { if (header !== undefined) header.retire(); }
}


// Private-brand receipt, not a caller-supplied numeric proof. Its only retained
// references are the same borrowed input and its exact fields/rows arrays.
class ClosedValuesHeader {
  #input; #fields; #rows; #fieldCount; #rowCount; #retired = false;
  constructor(token, input, fields, rows, fieldCount, rowCount) {
    if (token !== HEADER_TOKEN) throw DECLINED;
    this.#input=input; this.#fields=fields; this.#rows=rows;
    this.#fieldCount=fieldCount; this.#rowCount=rowCount;
    Object.freeze(this);
  }
  static matches(value, input) {
    return value !== null && typeof value === 'object' && #input in value &&
      !value.#retired && value.#input === input;
  }
  matchesFields(value,count) {return !this.#retired && value===this.#fields && count===this.#fieldCount;}
  matchesRows(value,count) {return !this.#retired && value===this.#rows && count===this.#rowCount;}
  fields() {return this.#fieldCount;}
  rows() {return this.#rowCount;}
  retire() {this.#retired=true;this.#input=undefined;this.#fields=undefined;this.#rows=undefined;}
}
Object.freeze(ClosedValuesHeader.prototype);
Object.freeze(ClosedValuesHeader);
function headerLength(s, value) {
  plain(s,value,true);
  const length=descriptor(s,value,'length')?.value;
  if (!Number.isSafeInteger(length)||length<0) throw DECLINED;
  return length;
}

// Fixed visible header transitions only: no text-content scan, key array,
// caller callback or iteration over rows/fields. Sole Result discovery visits
// at most two keys; V8's hidden enum backing remains explicitly opaque.
export function probeClosedValuesOwnDataHeader(input, options, phase) {
  if (options!==undefined || prototypeOf(objectPrototype)!==null ||
      prototypeOf(arrayPrototype)!==objectPrototype) return undefined;
  const s={phase,work:0};
  try {
    plain(s,input,false);
    const stages=data(s,input,'stages');if(headerLength(s,stages)!==1)throw DECLINED;
    const stage=item(s,stages,0);plain(s,stage,false);
    const steps=data(s,stage,'steps');if(headerLength(s,steps)!==1)throw DECLINED;
    const step=item(s,steps,0);plain(s,step,false);
    const values=data(s,step,'values');plain(s,values,false);
    const rows=data(s,values,'rows');const rowCount=headerLength(s,rows);
    const results=data(s,stage,'results');plain(s,results,false);
    let selected,visits=0;
    for(const key in results){
      work(s);if(++visits>2)throw DECLINED;
      const d=descriptor(s,results,key);
      if(d===undefined)break; // inherited keys follow all own keys
      if(!d.enumerable)continue;
      if(!Object.hasOwn(d,'value')||selected!==undefined||d.value===undefined)throw DECLINED;
      selected=d.value;
    }
    plain(s,selected,false);
    const fields=data(s,selected,'fields');const fieldCount=headerLength(s,fields);
    if(fieldCount===0)throw DECLINED;
    return new ClosedValuesHeader(HEADER_TOKEN,input,fields,rows,fieldCount,rowCount);
  }catch(cause){if(cause===DECLINED)return undefined;throw cause;}
}
export function closedValuesOwnDataHeaderFields(header,input) {
  return ClosedValuesHeader.matches(header,input)?header.fields():undefined;
}
export function closedValuesOwnDataHeaderRows(header,input) {
  return ClosedValuesHeader.matches(header,input)?header.rows():undefined;
}
export function retireClosedValuesOwnDataHeader(header,input) {
  if(ClosedValuesHeader.matches(header,input))header.retire();
}
// Source-derived valid-shape work: record(K)=3+3K, array=5, scalar/key=1;
// duplicate field checks=F(F-1); each row=4+6F. Common owns authority and
// performs the corresponding checked arithmetic on these original counts.
export function closedValuesOwnDataScanWorkUpper(header,input) {
  if(!ClosedValuesHeader.matches(header,input))return undefined;
  const f=header.fields(),r=header.rows(),maximum=Number.MAX_SAFE_INTEGER;
  if(f>Math.floor((maximum-140)/(f+19)))return undefined;
  const base=140+f*f+19*f,perRow=4+6*f;
  if(!Number.isSafeInteger(perRow)||r>Math.floor((maximum-base)/perRow))return undefined;
  return base+r*perRow;
}
