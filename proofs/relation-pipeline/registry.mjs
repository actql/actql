import { take } from './take.mjs';
import { filter } from './filter.mjs';
import { select } from './select.mjs';
import { sort } from './sort.mjs';
import { rename } from './rename.mjs';
export const baseRegistry = Object.freeze([filter, select, sort]);
export const takeRegistry = Object.freeze([...baseRegistry, take]);
export const registry = Object.freeze([...takeRegistry, rename]);
