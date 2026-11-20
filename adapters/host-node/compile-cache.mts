// V8 code cache only. It never caches ActQL checking, authority, or material.
// Node may decline this optional optimization; execution remains unchanged.
import * as nodeModule from 'node:module';

export function enableNodeCompileCache() {
  if (process.env.NODE_V8_COVERAGE ||
      process.execArgv.includes('--experimental-test-coverage')) return;
  return nodeModule.enableCompileCache?.();
}
