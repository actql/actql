// Large selections include the complete source/graph inventory. Keep that
// evidence in a step-local JSON file instead of an exec environment string.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

export function readCiInput(name, environment = process.env) {
  const inline = environment[name], path = environment[`${name}_PATH`];
  assert(!(inline && path), `Conflicting ${name} transports`);
  if (path) return JSON.parse(readFileSync(path, 'utf8'));
  return inline ? JSON.parse(inline) : undefined;
}
