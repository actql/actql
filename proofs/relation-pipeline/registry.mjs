import { take } from './take.mjs';
import { filter } from './filter.mjs';
import { select } from './select.mjs';
import { sort } from './sort.mjs';
export const baseRegistry = Object.freeze([filter, select, sort]);
export const registry = Object.freeze([...baseRegistry, take]);
