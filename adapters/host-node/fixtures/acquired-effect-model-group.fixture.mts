import {registerHooks} from 'node:module';

type Ports = Readonly<{
  openNodeInferCaptureCustody?: unknown;
  prepareAcquiredEffectSourceUnits?: unknown;
  acquiredInferEffectPublicationPlan?: unknown;
  localContractLimits?: unknown;
  startCompleteInferObservation?: unknown;
  projectInferEvidence?: unknown;
  preparePrivatePublicationHolding?: unknown;
}>;
type GroupModule = typeof import('../acquired-effect-model-group.mjs');
let sequence = 0;

// The selected module instance uses the real group and publication code. A
// fixture can supply only the original dependency ports that it observes.
export async function loadAcquiredEffectModelGroup(ports: Ports): Promise<GroupModule['acquiredEffectModelGroup']> {
  const target = new URL('../acquired-effect-model-group.mjs', import.meta.url);
  target.searchParams.set('model-group', String(++sequence));
  const publication = new URL('../acquired-effect-model-publication.mjs', import.meta.url);
  publication.search = target.search;
  const key = 'actql.test.effect-model-group.' + sequence;
  const global = globalThis as typeof globalThis & Record<symbol, Ports | undefined>;
  const originalImports = new Map<string, string>();
  const typedImports = new Map<string, string>();
  const bind = (imports: Map<string, string>, parent: URL, specifier: string, names: readonly (keyof Ports)[]) => {
    const selected = names.filter(name => Object.hasOwn(ports, name));
    if (selected.length === 0) return;
    const base = new URL(specifier, parent).href;
    const constants = selected.map(name =>
      `export const ${name} = ports[${JSON.stringify(name)}];`).join('\n');
    const body = `export * from ${JSON.stringify(base)};
const ports = globalThis[Symbol.for(${JSON.stringify(key)})];
${constants}`;
    imports.set(specifier, 'data:text/javascript,' + encodeURIComponent(body));
  };
  bind(originalImports, target, './infer-capture-custody.mjs', ['openNodeInferCaptureCustody']);
  bind(originalImports, target, './local-values-plan.mjs',
    ['prepareAcquiredEffectSourceUnits', 'acquiredInferEffectPublicationPlan']);
  bind(originalImports, target, './local-publication-limits.mjs', ['localContractLimits']);
  bind(typedImports, publication, './infer-operation.mjs', ['startCompleteInferObservation']);
  bind(typedImports, publication, './infer-evaluation-evidence.mjs', ['projectInferEvidence']);
  bind(typedImports, publication, '../host-common/private-publication-holding.mjs', ['preparePrivatePublicationHolding']);
  global[Symbol.for(key)] = ports;
  const hook = registerHooks({resolve(specifier, context, next) {
    if (context.parentURL === target.href && specifier === './acquired-effect-model-publication.mjs') {
      return next(publication.href, context);
    }
    const url = context.parentURL === target.href ? originalImports.get(specifier) :
      context.parentURL === publication.href ? typedImports.get(specifier) : undefined;
    return url === undefined ? next(specifier, context) : {url, shortCircuit: true};
  }});
  try {
    const loaded = await import(target.href) as GroupModule;
    return loaded.acquiredEffectModelGroup;
  } finally {
    hook.deregister();
    delete global[Symbol.for(key)];
  }
}
