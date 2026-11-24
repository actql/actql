// Private association of the existing installed Run control, not a resource
// token or grant. Every consumer still calls the actual Core numeric owner.
type UncheckedDependencyOriginal = {readonly runtime: unknown; current(): unknown; readonly [key: string]: unknown};
const originals=new WeakMap<object, Readonly<UncheckedDependencyOriginal>>();
export function registerInstalledEffectDependencyOriginal(view: unknown,original: unknown){
  if(typeof view!=='function'||original===null||typeof original!=='object'||originals.has(view))
    throw new TypeError('ForeignInstalledEffectDependencyOriginal');
  originals.set(view,Object.freeze({...original}) as Readonly<UncheckedDependencyOriginal>);
}
export function installedEffectDependencyOriginal(view: unknown,runtime: unknown){
  const original=originals.get(view as object);
  if(original===undefined||original.runtime!==runtime)throw new TypeError('ForeignInstalledEffectDependencyOriginal');
  original.current();
  return original;
}
export function retireInstalledEffectDependencyOriginal(view: unknown){originals.delete(view as object);}
