// In-memory test-only parent substitution. No installed file, environment,
// Native argument, preparation receipt, or product branch is changed.
import {rewriteResidentControlSpawn} from '../diagnose-native-resident-functions.mjs';

let original;
export function initialize(data) { original = data; }
export async function load(url, context, nextLoad) {
  const result = await nextLoad(url, context);
  if (url !== original.sourceUrl) return result;
  return {...result, source: rewriteResidentControlSpawn(
    Buffer.from(result.source).toString('utf8'), original)};
}
