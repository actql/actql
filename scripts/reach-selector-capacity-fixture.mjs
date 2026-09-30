// Acceptance input only. This module is not shipped in an ActQL package.
export function reachSelectorChainSource(template, count) {
  if (!Number.isInteger(count) || count < 1 || count > 99) {
    throw new Error('InvalidReachChainFixtureSize');
  }
  if (!template.includes('DATA seeds = FROM nodes;')) {
    throw new Error('ReachChainFixtureRequiresSharedProducer');
  }
  const id = index => `N${String(index).padStart(2, '0')}`;
  const nodes = Array.from({length: count}, (_, index) =>
    ({id: id(count - index - 1)}));
  const edges = Array.from({length: count - 1}, (_, index) =>
    ({src: id(index), dst: id(index + 1)}));
  let source = template;
  for (const [before, after] of [
    ['"rows":[{"id":"A"},{"id":"B"}]',
      '"rows":' + JSON.stringify(nodes)],
    ['"rows":[{"src":"A","dst":"B"}]',
      '"rows":' + JSON.stringify(edges)],
    ['max_depth: 2', `max_depth: ${count - 1}`],
  ]) {
    if (!source.includes(before)) throw new Error('ReachChainFixtureDrift');
    source = source.replace(before, after);
  }
  return source;
}
