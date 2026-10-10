// Shared executable registrations. Keep the existing scientific names; separate
// independent contracts without raising per-case or per-process time budgets.
const profiles = {
  graph: 'keyed constructor and TRAIL reach public Named Results through',
  'graph-projections': 'Graph row projections preserve presence through Store and public',
  'graph-definitions': 'Graph definition selection preserves typed rows through Store and public',
  'graph-labels': 'Graph label selection preserves typed rows through Store and public',
  'graph-traversal-modes': 'Graph traversal node modes preserve identity and depth through Store and public',
  'graph-traversal-selectors': 'Graph traversal node selectors preserve eligibility through Store and public',
  'presence-filter': 'presence filter survives Relation Store and public Named Results through',
  'presence-selection': 'presence selection sort and take survives Relation Store and public Named Results through',
  'selector-derive': 'selector property derive survives Relation Store and public Named Results through',
  'relation-subgraph': 'external Relation-selected subgraph survives Store reload and public Named Results through',
  'presence-keyed-distinct': 'presence keyed distinct survives Relation Store and public Named Results through',
  'presence-whole-distinct': 'presence whole-row distinct survives Relation Store and public Named Results through',
  'presence-group': 'presence group survives Relation Store and public Named Results through',
  'delta-application': 'complete Delta application survives Graph and Relation Store reload through',
  'delta-relation-composition': 'Delta Relation DISTINCT and GROUP survive Store reload through',
  'delta-diff': 'Graph diff Delta survives Relation Store reload and reapplication through',
  'graph-union': 'Graph union preserves occurrences and sparse rows through Store reload and public',
  'graph-graft': 'Graph graft preserves complete records through Store reload and public',
  'graph-subtraction': 'Graph subtraction preserves typed records through Store reload and public',
};

export const graphPublicHostCases = Object.freeze(['local','remote'].flatMap(mode =>
  Object.entries(profiles).map(([profile,title]) => Object.freeze({mode,profile,
    name:`${title} ${mode}`}))));

export const graphPublicHostPattern = name => '^' +
  name.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&') + '$';
