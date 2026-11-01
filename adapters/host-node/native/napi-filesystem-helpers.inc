/* Shared value validation only; these helpers issue no filesystem custody. */
static napi_value unavailable(napi_env env, const char *code) {
  napi_throw_error(env, code, code); return NULL;
}
static napi_value undefined(napi_env env) {
  napi_value value; return napi_get_undefined(env, &value) == napi_ok ? value : NULL;
}
static bool bound(napi_env env, napi_value value, uint64_t high, uint64_t *out) {
  napi_valuetype type; double number;
  if (napi_typeof(env, value, &type) != napi_ok || type != napi_number ||
      napi_get_value_double(env, value, &number) != napi_ok ||
      !(number >= 1 && number <= (double)high)) return false;
  uint64_t integer = (uint64_t)number;
  if ((double)integer != number) return false;
  *out = integer; return true;
}
