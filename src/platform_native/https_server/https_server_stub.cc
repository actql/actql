#define CPPHTTPLIB_OPENSSL_SUPPORT
#define CPPHTTPLIB_NO_EXCEPTIONS

#include <cstring>

// moonbit.h declares memcpy when no macro with that name exists. The C++
// standard library has already declared it here with a platform-specific
// exception specification, so prevent the fallback declaration.
#define memcpy memcpy
#include "moonbit.h"
#undef memcpy
#include "../../../vendor/cpp-httplib/0.56.0/httplib.h"

#include <openssl/evp.h>
#include <openssl/ssl.h>
#include <openssl/x509.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <iomanip>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <unordered_set>

namespace {

struct RequestState {
  std::atomic<int> references{1};
  std::mutex mutex;
  std::condition_variable condition;
  std::string method;
  std::string path;
  httplib::Headers headers;
  std::string body;
  std::string peer_fingerprint;
  int response_status = 503;
  std::string response_type = "application/json";
  std::string response_body = "{\"error\":\"server_closed\"}";
  bool responded = false;
  bool header_present = false;
};

struct ServerState {
  std::unique_ptr<httplib::SSLServer> server;
  std::thread listener;
  std::mutex mutex;
  std::condition_variable condition;
  std::deque<RequestState *> pending;
  std::unordered_set<RequestState *> active;
  std::string error;
  int port = 0;
  size_t max_pending = 0;
  bool ready = false;
  bool closing = false;
  bool closed = false;
};

struct ServerHandle {
  ServerState *state;
};

struct RequestHandle {
  RequestState *state;
};

void release_request(RequestState *state) {
  if (state != nullptr && state->references.fetch_sub(1) == 1) {
    delete state;
  }
}

std::string text(moonbit_bytes_t bytes, int32_t length) {
  if (bytes == nullptr || length < 0) return {};
  return std::string(reinterpret_cast<const char *>(bytes),
                     static_cast<size_t>(length));
}

moonbit_bytes_t bytes(const std::string &value) {
  if (value.size() > static_cast<size_t>(INT32_MAX)) {
    return moonbit_make_bytes_raw(0);
  }
  auto result = moonbit_make_bytes_raw(static_cast<int32_t>(value.size()));
  if (!value.empty()) std::memcpy(result, value.data(), value.size());
  return result;
}

std::string fingerprint(const httplib::Request &request) {
  X509 *certificate = SSL_get1_peer_certificate(
      static_cast<const SSL *>(request.ssl));
  if (certificate == nullptr) return {};
  unsigned char digest[EVP_MAX_MD_SIZE];
  unsigned int length = 0;
  const bool valid = X509_digest(certificate, EVP_sha256(), digest, &length) == 1;
  X509_free(certificate);
  if (!valid || length != 32) return {};
  std::ostringstream output;
  output << std::uppercase << std::hex << std::setfill('0');
  for (unsigned int index = 0; index < length; index++) {
    if (index != 0) output << ':';
    output << std::setw(2) << static_cast<unsigned int>(digest[index]);
  }
  return output.str();
}

void settle(RequestState *state, int status, const std::string &type,
            const std::string &body) {
  std::lock_guard<std::mutex> lock(state->mutex);
  if (state->responded) return;
  state->response_status = status;
  state->response_type = type;
  state->response_body = body;
  state->responded = true;
  state->condition.notify_all();
}

void handle_request(ServerState *owner, const httplib::Request &request,
                    httplib::Response &response) {
  auto state = new RequestState();
  state->method = request.method;
  state->path = request.path;
  state->headers = request.headers;
  state->body = request.body;
  state->peer_fingerprint = fingerprint(request);
  {
    std::lock_guard<std::mutex> lock(owner->mutex);
    if (owner->closing || owner->pending.size() >= owner->max_pending ||
        state->peer_fingerprint.empty()) {
      settle(state, owner->closing ? 503 : 429, "application/json",
             "{\"error\":\"request_unavailable\"}");
    } else {
      state->references.fetch_add(1);
      owner->active.insert(state);
      owner->pending.push_back(state);
      owner->condition.notify_one();
    }
  }
  {
    std::unique_lock<std::mutex> lock(state->mutex);
    state->condition.wait(lock, [&]() { return state->responded; });
    response.status = state->response_status;
    response.set_content(state->response_body, state->response_type);
    response.set_header("cache-control", "no-store");
  }
  {
    std::lock_guard<std::mutex> lock(owner->mutex);
    owner->active.erase(state);
  }
  release_request(state);
}

void close_state(ServerState *state) {
  if (state == nullptr) return;
  {
    std::lock_guard<std::mutex> lock(state->mutex);
    if (state->closing) return;
    state->closing = true;
    for (auto *request : state->active) {
      settle(request, 503, "application/json",
             "{\"error\":\"server_closed\"}");
    }
    while (!state->pending.empty()) {
      auto *request = state->pending.front();
      state->pending.pop_front();
      release_request(request);
    }
    state->condition.notify_all();
  }
  if (state->server) state->server->stop();
  if (state->listener.joinable()) state->listener.join();
  {
    std::lock_guard<std::mutex> lock(state->mutex);
    state->closed = true;
    state->ready = false;
  }
}

void finalize_server(void *value) {
  auto *handle = static_cast<ServerHandle *>(value);
  if (handle->state != nullptr) {
    close_state(handle->state);
    delete handle->state;
    handle->state = nullptr;
  }
}

void finalize_request(void *value) {
  auto *handle = static_cast<RequestHandle *>(value);
  release_request(handle->state);
  handle->state = nullptr;
}

} // namespace

extern "C" {

void *actql_native_https_server_open(
    moonbit_bytes_t host, int32_t host_length, int32_t port,
    moonbit_bytes_t certificate_path, int32_t certificate_path_length,
    moonbit_bytes_t key_path, int32_t key_path_length,
    moonbit_bytes_t client_ca_path, int32_t client_ca_path_length,
    int32_t max_request_bytes, int32_t max_pending_requests) {
  auto *handle = static_cast<ServerHandle *>(moonbit_make_external_object(
      finalize_server, sizeof(ServerHandle)));
  handle->state = new ServerState();
  auto *state = handle->state;
  state->max_pending = max_pending_requests > 0
      ? static_cast<size_t>(max_pending_requests)
      : 0;
  if (port < 0 || port > 65535 || max_request_bytes <= 0 ||
      max_pending_requests <= 0) {
    state->error = "invalid HTTPS server configuration";
    return handle;
  }
  const auto host_text = text(host, host_length);
  const auto certificate_text = text(certificate_path, certificate_path_length);
  const auto key_text = text(key_path, key_path_length);
  const auto ca_text = text(client_ca_path, client_ca_path_length);
  state->server = std::make_unique<httplib::SSLServer>(
      certificate_text.c_str(), key_text.c_str(), ca_text.c_str());
  if (!state->server->is_valid()) {
    state->error = "initialize HTTPS server failed";
    return handle;
  }
  if (SSL_CTX_set_min_proto_version(
          static_cast<SSL_CTX *>(state->server->tls_context()),
          TLS1_3_VERSION) != 1) {
    state->error = "configure HTTPS protocol failed";
    return handle;
  }
  state->server->set_payload_max_length(
      static_cast<size_t>(max_request_bytes));
  state->server->set_read_timeout(30, 0);
  state->server->set_write_timeout(30, 0);
  auto handler = [state](const httplib::Request &request,
                         httplib::Response &response) {
    handle_request(state, request, response);
  };
  state->server->Get("/.*", handler);
  state->server->Post("/.*", handler);
  state->server->Put("/.*", handler);
  state->server->Delete("/.*", handler);
  state->port = port == 0
      ? state->server->bind_to_any_port(host_text)
      : (state->server->bind_to_port(host_text, port) ? port : -1);
  if (state->port <= 0) {
    state->error = "bind HTTPS server failed";
    return handle;
  }
  state->listener = std::thread([state]() {
    const bool listened = state->server->listen_after_bind();
    std::lock_guard<std::mutex> lock(state->mutex);
    if (!listened && !state->closing) {
      state->error = "HTTPS listener failed";
    }
    state->closed = true;
    state->ready = false;
    state->condition.notify_all();
  });
  state->server->wait_until_ready();
  {
    std::lock_guard<std::mutex> lock(state->mutex);
    state->ready = state->server->is_running();
    if (!state->ready) state->error = "start HTTPS listener failed";
  }
  return handle;
}

int32_t actql_native_https_server_ready(ServerHandle *handle) {
  if (handle == nullptr || handle->state == nullptr) return false;
  std::lock_guard<std::mutex> lock(handle->state->mutex);
  return handle->state->ready && !handle->state->closing;
}

moonbit_bytes_t actql_native_https_server_error(ServerHandle *handle) {
  if (handle == nullptr || handle->state == nullptr) {
    return bytes("invalid HTTPS server");
  }
  std::lock_guard<std::mutex> lock(handle->state->mutex);
  return bytes(handle->state->error);
}

int32_t actql_native_https_server_port(ServerHandle *handle) {
  return handle == nullptr || handle->state == nullptr ? 0
                                                       : handle->state->port;
}

int32_t actql_native_https_server_closed(ServerHandle *handle) {
  if (handle == nullptr || handle->state == nullptr) return true;
  std::lock_guard<std::mutex> lock(handle->state->mutex);
  return handle->state->closed;
}

void *actql_native_https_server_poll(ServerHandle *handle,
                                     int32_t timeout_milliseconds) {
  auto *request_handle = static_cast<RequestHandle *>(
      moonbit_make_external_object(finalize_request, sizeof(RequestHandle)));
  request_handle->state = nullptr;
  if (handle == nullptr || handle->state == nullptr ||
      timeout_milliseconds < 0) {
    return request_handle;
  }
  auto *state = handle->state;
  std::unique_lock<std::mutex> lock(state->mutex);
  state->condition.wait_for(
      lock, std::chrono::milliseconds(timeout_milliseconds), [&]() {
        return !state->pending.empty() || state->closing || state->closed;
      });
  if (!state->pending.empty()) {
    request_handle->state = state->pending.front();
    state->pending.pop_front();
  }
  return request_handle;
}

int32_t actql_native_https_request_available(RequestHandle *handle) {
  return handle != nullptr && handle->state != nullptr;
}

moonbit_bytes_t actql_native_https_request_method(RequestHandle *handle) {
  return bytes(handle == nullptr || handle->state == nullptr
                   ? std::string()
                   : handle->state->method);
}

moonbit_bytes_t actql_native_https_request_path(RequestHandle *handle) {
  return bytes(handle == nullptr || handle->state == nullptr
                   ? std::string()
                   : handle->state->path);
}

moonbit_bytes_t actql_native_https_request_body(RequestHandle *handle) {
  return bytes(handle == nullptr || handle->state == nullptr
                   ? std::string()
                   : handle->state->body);
}

moonbit_bytes_t actql_native_https_request_peer_fingerprint(
    RequestHandle *handle) {
  return bytes(handle == nullptr || handle->state == nullptr
                   ? std::string()
                   : handle->state->peer_fingerprint);
}

moonbit_bytes_t actql_native_https_request_header(
    RequestHandle *handle, moonbit_bytes_t name, int32_t name_length) {
  if (handle == nullptr || handle->state == nullptr) {
    return bytes(std::string());
  }
  const auto key = text(name, name_length);
  const auto found = handle->state->headers.find(key);
  handle->state->header_present = found != handle->state->headers.end();
  return bytes(handle->state->header_present ? found->second : std::string());
}

int32_t actql_native_https_request_header_present(RequestHandle *handle) {
  return handle != nullptr && handle->state != nullptr &&
         handle->state->header_present;
}

int32_t actql_native_https_request_respond(
    RequestHandle *handle, int32_t status, moonbit_bytes_t content_type,
    int32_t content_type_length, moonbit_bytes_t body, int32_t body_length) {
  if (handle == nullptr || handle->state == nullptr || status < 100 ||
      status > 599 || content_type_length <= 0 || body_length < 0) {
    return false;
  }
  auto *state = handle->state;
  {
    std::lock_guard<std::mutex> lock(state->mutex);
    if (state->responded) return false;
    state->response_status = status;
    state->response_type = text(content_type, content_type_length);
    state->response_body = text(body, body_length);
    state->responded = true;
    state->condition.notify_all();
  }
  return true;
}

int32_t actql_native_https_server_close(ServerHandle *handle) {
  if (handle == nullptr || handle->state == nullptr) return false;
  close_state(handle->state);
  std::lock_guard<std::mutex> lock(handle->state->mutex);
  return handle->state->closed;
}

} // extern "C"
