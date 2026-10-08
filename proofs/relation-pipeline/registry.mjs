import { take } from './take.mjs';
import { filter } from './filter.mjs';
import { select } from './select.mjs';
import { sort } from './sort.mjs';
import { rename } from './rename.mjs';
import { distinct } from './distinct.mjs';
import { derive } from './derive.mjs';
export const baseRegistry = Object.freeze([filter, select, sort]);
export const takeRegistry = Object.freeze([...baseRegistry, take]);
// Keep the integrated fixed corpus when adding a descriptor: a changed random
// stream must not silently replace the earlier successful-domain witnesses.
export const corpusBaseline = Object.freeze([...takeRegistry, rename, distinct]);
export const deriveRegistry = Object.freeze([...corpusBaseline, derive]);
// Keep each accepted registry stage explicit. A later descriptor is appended
// after these stages; regenerating only the latest registry loses prior inputs.
export const corpusFoundations = Object.freeze([corpusBaseline, deriveRegistry]);
export const registry = deriveRegistry;
