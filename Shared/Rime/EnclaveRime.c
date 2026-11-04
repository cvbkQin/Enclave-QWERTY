#include "EnclaveRime.h"

#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <rime_api.h>
#include <CoreFoundation/CoreFoundation.h>

static bool did_setup = false;
static bool did_initialize = false;

/// App 的版本号（MARKETING_VERSION），读不到时用 "1.0"。
static const char *app_version(void) {
  static char version[32] = "";
  if (version[0] != '\0') return version;
  CFTypeRef value = CFBundleGetValueForInfoDictionaryKey(CFBundleGetMainBundle(), CFSTR("CFBundleShortVersionString"));
  if (value == NULL || CFGetTypeID(value) != CFStringGetTypeID() ||
      !CFStringGetCString((CFStringRef)value, version, sizeof(version), kCFStringEncodingUTF8)) {
    strcpy(version, "1.0");
  }
  return version;
}

static void fill_traits(RimeTraits *traits, const char *shared_dir, const char *user_dir, const char *log_dir) {
  RIME_STRUCT_INIT(RimeTraits, *traits);
  traits->shared_data_dir = shared_dir;
  traits->user_data_dir = user_dir;
  traits->log_dir = log_dir;
  traits->distribution_name = "Enclave";
  traits->distribution_code_name = "enclave";
  traits->distribution_version = app_version();
  traits->app_name = "rime.enclave";
  traits->min_log_level = 2;
}

static char *copy_string(const char *text) {
  if (text == NULL || text[0] == '\0') return NULL;
  return strdup(text);
}

bool enclave_rime_start(const char *shared_dir, const char *user_dir, const char *log_dir) {
  RimeApi *api = rime_get_api();
  if (did_initialize) return true;
  RIME_STRUCT(RimeTraits, traits);
  fill_traits(&traits, shared_dir, user_dir, log_dir);
  if (!did_setup) {
    api->setup(&traits);
    did_setup = true;
  }
  api->initialize(&traits);
  did_initialize = true;
  return true;
}

void enclave_rime_finalize(void) {
  if (!did_initialize) return;
  rime_get_api()->finalize();
  did_initialize = false;
}

bool enclave_rime_deploy(const char *shared_dir, const char *user_dir, const char *log_dir) {
  RimeApi *api = rime_get_api();
  enclave_rime_finalize();
  enclave_rime_start(shared_dir, user_dir, log_dir);
  // full_check 为真：不看时间戳，全部重新编译。
  if (api->start_maintenance(1)) {
    api->join_maintenance_thread();
  }
  bool ok = !api->is_maintenance_mode();
  enclave_rime_finalize();
  return ok;
}

bool enclave_rime_sync_user_data(const char *shared_dir, const char *user_dir, const char *log_dir, const char *ensure_schema) {
  RimeApi *api = rime_get_api();
  enclave_rime_finalize();
  enclave_rime_start(shared_dir, user_dir, log_dir);
  // 同步用的几个任务（installation_update、user_dict_sync 等）在部署模块组里注册：
  // start_maintenance 会自己加载这组模块，sync_user_data 不会，不先加载就排不上任务、直接返回失败。
  RIME_STRUCT(RimeTraits, traits);
  fill_traits(&traits, shared_dir, user_dir, log_dir);
  api->deployer_initialize(&traits);
  if (ensure_schema) {
    RimeSessionId session = api->create_session();
    if (session) {
      api->select_schema(session, ensure_schema);
      api->destroy_session(session);
    }
  }
  bool ok = api->sync_user_data();
  api->join_maintenance_thread();
  enclave_rime_finalize();
  return ok;
}

bool enclave_userdb_locked(const char *lock_path) {
  int fd = open(lock_path, O_RDWR);
  if (fd < 0) return false;
  struct flock info;
  memset(&info, 0, sizeof(info));
  info.l_type = F_WRLCK;
  info.l_whence = SEEK_SET;
  bool locked = false;
  if (fcntl(fd, F_SETLK, &info) == -1) {
    locked = (errno == EACCES || errno == EAGAIN);
  } else {
    info.l_type = F_UNLCK;
    fcntl(fd, F_SETLK, &info);
  }
  close(fd);
  return locked;
}

uint64_t enclave_rime_create_session(const char *schema_id) {
  RimeApi *api = rime_get_api();
  RimeSessionId session = api->create_session();
  if (session && schema_id) api->select_schema(session, schema_id);
  return session;
}

void enclave_rime_destroy_session(uint64_t session) {
  if (session) rime_get_api()->destroy_session(session);
}

bool enclave_rime_select_schema(uint64_t session, const char *schema_id) {
  return rime_get_api()->select_schema(session, schema_id);
}

bool enclave_rime_session_alive(uint64_t session) {
  return session && rime_get_api()->find_session(session);
}

bool enclave_rime_process_key(uint64_t session, int keycode, int mask) {
  return rime_get_api()->process_key(session, keycode, mask);
}

void enclave_rime_clear(uint64_t session) {
  rime_get_api()->clear_composition(session);
}

void enclave_rime_set_option(uint64_t session, const char *option, bool value) {
  rime_get_api()->set_option(session, option, value);
}

char *enclave_rime_get_commit(uint64_t session) {
  RimeApi *api = rime_get_api();
  RIME_STRUCT(RimeCommit, commit);
  char *result = NULL;
  if (api->get_commit(session, &commit)) {
    result = copy_string(commit.text);
    api->free_commit(&commit);
  }
  return result;
}

char *enclave_rime_get_preedit(uint64_t session) {
  RimeApi *api = rime_get_api();
  RIME_STRUCT(RimeContext, context);
  char *result = NULL;
  if (api->get_context(session, &context)) {
    result = copy_string(context.composition.preedit);
    api->free_context(&context);
  }
  return result;
}

char *enclave_rime_get_input(uint64_t session) {
  return copy_string(rime_get_api()->get_input(session));
}

size_t enclave_rime_get_candidates(uint64_t session, char **out, size_t limit) {
  return enclave_rime_get_candidates_from(session, out, 0, limit);
}

size_t enclave_rime_get_candidates_from(uint64_t session, char **out, size_t start, size_t limit) {
  RimeApi *api = rime_get_api();
  RimeCandidateListIterator iterator = {0};
  size_t count = 0;
  if (!api->candidate_list_from_index(session, &iterator, (int)start)) return 0;
  while (count < limit && api->candidate_list_next(&iterator)) {
    out[count++] = strdup(iterator.candidate.text ? iterator.candidate.text : "");
  }
  api->candidate_list_end(&iterator);
  return count;
}

bool enclave_rime_select_candidate(uint64_t session, size_t index) {
  return rime_get_api()->select_candidate(session, index);
}

bool enclave_rime_delete_candidate(uint64_t session, size_t index) {
  RimeApi *api = rime_get_api();
  if (!RIME_API_AVAILABLE(api, delete_candidate)) return false;
  return api->delete_candidate(session, index);
}

char *enclave_rime_get_property(uint64_t session, const char *name) {
  char value[1024] = "";
  if (!rime_get_api()->get_property(session, name, value, sizeof(value))) return NULL;
  return copy_string(value);
}
