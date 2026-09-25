// RelA-only Node composition. The generated bridge excludes SGA, TEA and
// VecA while sharing the standard Host lifecycle and publication policy.
import {installStrategyContributions} from
  '../connectors-builtin-rela/strategy.generated.mjs';
import {createNodeHostEntry} from './entry.mjs';

const runtimeUrl = new URL(
  '../../_build/js/release/build/connectors_builtin_node_rela/connectors_builtin_node_rela.js',
  import.meta.url,
);
const entry = createNodeHostEntry(
  () => import(runtimeUrl.href), installStrategyContributions);

export const runCapturedStrategy = entry.runCapturedStrategy;
export const runCapturedInternalStrategy =
  entry.runCapturedInternalStrategy;
export const runCapturedEffectComputation =
  entry.runCapturedEffectComputation;
export const runPublishedCapturedStrategy =
  entry.runPublishedCapturedStrategy;
export const completeCapturedEffectRun =
  entry.completeCapturedEffectRun;
export const completeRecoveredEffectRun =
  entry.completeRecoveredEffectRun;
