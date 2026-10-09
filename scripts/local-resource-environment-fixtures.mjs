// Recognize the bounded registration forms used by the public resource suites.
// Read captured source bytes only; importing a suite would execute its tests,
// while importing a registry would bypass the validator's source snapshot.
export function registeredResourceEnvironmentCase(item, source, graphRegistry = '', operation) {
  if (item.suite === 'node:embedded_property_names') {
    const metadata = /for\s*\(const\s*\[kind,title\]\s*of\s*\[([\s\S]*?)\]\)\s*\{([\s\S]*?)\n\}/u.exec(source);
    if (item.case === 'compoundCompletionProgram' && metadata) {
      const registration = metadata[2].replace(/\s+/gu, '');
      const titles = [...metadata[1].matchAll(/\['(join|nest|interval|asof)','([^']+)'\]/gu)];
      if (titles.some(([, kind, title]) => title === item.fixture &&
          item.role === `${kind}_compound_metadata_public`) &&
          registration.includes('test(title,') &&
          registration.includes('=>verifyRetainedNames(t,`${kind}-source-metadata`,') &&
          registration.includes('id=>compoundCompletionProgram(id,kind,true),rows,contract)')) {
        return true;
      }
    }
    const sequence = /for\s*\(const\s+overlap\s+of\s+\['allow','disallow'\]\)\s*\{([\s\S]*?)\n\}/u.exec(source);
    if (item.case === 'sequencePositionProgram' && sequence) {
      const registration = sequence[1].replace(/\s+/gu, '');
      if (sequence[1].includes(`test(\`${item.fixture}\`,`) &&
          registration.includes('=>verifyRetainedNames(t,`sequence-position-${overlap}`,') &&
          registration.includes('id=>sequencePositionProgram(id,overlap),')) {
        return true;
      }
    }
  }
  if (item.suite === 'node:graph_public_host') {
    const registration = source.replace(/\s+/gu, '');
    const registry = graphRegistry.replace(/\s+/gu, '');
    if (!registration.includes("import{graphPublicHostCases}from'./fixtures/graph-host-cases.mjs';") ||
        !registration.includes('for(const{mode,profile,name}ofgraphPublicHostCases){test(name,') ||
        !graphRegistry.includes('name:`${title} ${mode}`') ||
        !registry.includes("exportconstgraphPublicHostCases=Object.freeze(['local','remote'].flatMap(mode=>Object.entries(profiles).map(([profile,title])=>Object.freeze({mode,profile,name:`${title}${mode}`}))))")) {
      return false;
    }
    const profiles = /^const profiles = \{([\s\S]*?)^\};/mu.exec(graphRegistry);
    const projectionBody = /if \(profile === 'graph-projections'\) \{([\s\S]*?)\n    \}/u
      .exec(source)?.[1].replace(/\s+/gu, '') ?? '';
    for (const [, profile, title] of profiles?.[1].matchAll(/^\s*'([^']+)': '([^']+)',$/gmu) ?? []) {
      const selection = operation === 'node_rows' && profile === 'presence-selection' &&
        registration.includes("presenceFilterScenario(empty,profile==='presence-selection')");
      const projection = ['node_rows', 'edge_rows'].includes(operation) &&
        profile === 'graph-projections' &&
        projectionBody.includes("for(constprojectionof['node_rows','edge_rows']){") &&
        projectionBody.includes("document.stages[0].steps[4]={from:'g',[projection]:true,as:'rows'}") &&
        projectionBody.includes('presenceRows[projection]');
      if (item.role === 'graph_projection_public_store' && (selection || projection) &&
          ['local', 'remote'].some(mode => item.fixture === `${title} ${mode}`)) return true;
    }
  }
  return false;
}
