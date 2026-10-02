import { distinctMutations } from './distinct-mutations.mjs';
import { sites } from './sites.mjs';
import { connectionAnchor, connectionMismatch, orderAnchor, orderMismatch } from './mismatch.mjs';
import { renameMutations } from './rename-mutations.mjs';
export const variants = [
  { ...sites[0], eligible: c => c.steps.length >= 2, anchor: c => connectionAnchor(c), preserves: connectionMismatch },
  { ...sites[1], eligible: () => true, anchor: orderAnchor, preserves: orderMismatch },
  ...renameMutations,
  ...distinctMutations,
];
