// Private association of the existing installed Run control, not a resource
// token or grant. Every consumer still calls the actual Core numeric owner.
const originals=new WeakMap();
export function registerInstalledEffectDependencyOriginal(view,original){
  if(typeof view!=='function'||original===null||typeof original!=='object'||originals.has(view))
    throw new TypeError('ForeignInstalledEffectDependencyOriginal');
  originals.set(view,Object.freeze({...original}));
}
export function installedEffectDependencyOriginal(view,runtime){
  const original=originals.get(view);
  if(original===undefined||original.runtime!==runtime)throw new TypeError('ForeignInstalledEffectDependencyOriginal');
  original.current();
  return original;
}
export function retireInstalledEffectDependencyOriginal(view){originals.delete(view);}
