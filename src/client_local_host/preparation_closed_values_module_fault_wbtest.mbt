///|
extern "js" fn closed_module_test_raise() -> Unit =
  #|() => { throw new Error('closed-module-original-callback'); }

///|
fn closed_module_test_throw() -> Array[@local.ManagedProvider] {
  closed_module_test_raise()
  []
}

///|
extern "js" fn closed_module_test_catch(body : () -> Unit) -> Bool =
  #|(body) => { try { body(); return false; } catch(error) { if(error.message!=='closed-module-original-callback')throw error; return true; } }
