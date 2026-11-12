// This hash-fenced test-only substitution changes only the control launcher.
// The actual fixture, Native environment, arguments and assertions stay intact.
import {rewriteChannelControlSpawn} from '../diagnose-native-resident-channel.mjs';
let original;
export function initialize(data) { original = data; }
export async function load(url, context, nextLoad) {
  const result = await nextLoad(url, context);
  if (url !== original.sourceUrl) return result;
  return {...result, source: rewriteChannelControlSpawn(Buffer.from(result.source).toString('utf8'), original)};
}
