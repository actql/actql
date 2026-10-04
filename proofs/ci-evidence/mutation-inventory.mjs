// Shared required identities; independent of the submitted mutation report.
export const mutationIds = Object.freeze(['stale-token-reuse', 'zero-quantum', 'terminal-resume',
  'cleanup-changed-as-complete', 'cumulative-as-delta', 'reset-budget-history', 'accept-backward-work',
  'adapter-terminal-resume', 'premature-cleanup-success', 'cleanup-retry-reruns-callback',
  'actual-set-path-reaches-adapter', 'actual-nest-path-reaches-adapter', 'nest-parent-child-ports-swapped']);

// Independent registered experiment locations and selections. Do not infer
// them from a report, or accept thirteen copies of another experiment.
const session = Object.freeze({path: 'src/bounded_execution/session.mbt', suite: 'src/bounded_execution', filter: 'session contract*'});
const adapter = Object.freeze({path: 'src/connectors/local/bounded_session_provider.mbt', suite: 'src/connectors/local', filter: 'adapter contract*'});
const nest = Object.freeze({path: adapter.path, suite: 'src/query_integration/local_managed_nest_wbtest.mbt', filter: 'Local managed nest reaches two consumers*'});
export const mutationContracts = Object.freeze({
  'stale-token-reuse': session,
  'zero-quantum': session,
  'terminal-resume': session,
  'cleanup-changed-as-complete': session,
  'cumulative-as-delta': adapter,
  'reset-budget-history': adapter,
  'accept-backward-work': adapter,
  'adapter-terminal-resume': adapter,
  'premature-cleanup-success': adapter,
  'cleanup-retry-reruns-callback': adapter,
  'actual-set-path-reaches-adapter': Object.freeze({path: adapter.path,
    suite: 'src/query_integration/local_managed_set_wbtest.mbt', filter: 'Local managed row sets*'}),
  'actual-nest-path-reaches-adapter': nest,
  'nest-parent-child-ports-swapped': Object.freeze({...nest, path: 'src/connectors/local/nest_provider.mbt'}),
});
