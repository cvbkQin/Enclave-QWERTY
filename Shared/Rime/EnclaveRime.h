// 对 librime C 接口的一层薄封装，方便 Swift 调用。
#ifndef ENCLAVE_RIME_H
#define ENCLAVE_RIME_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/// 初始化 librime。同一进程只会 setup 一次，可以 finalize 后再次 start。
bool enclave_rime_start(const char *shared_dir, const char *user_dir, const char *log_dir);
void enclave_rime_finalize(void);

/// 部署（编译词库），会阻塞到完成，只在主 App 里调用。
bool enclave_rime_deploy(const char *shared_dir, const char *user_dir, const char *log_dir);

uint64_t enclave_rime_create_session(const char *schema_id);
void enclave_rime_destroy_session(uint64_t session);
bool enclave_rime_select_schema(uint64_t session, const char *schema_id);
bool enclave_rime_session_alive(uint64_t session);
bool enclave_rime_process_key(uint64_t session, int keycode, int mask);
void enclave_rime_clear(uint64_t session);
void enclave_rime_set_option(uint64_t session, const char *option, bool value);

/// 返回值需要用 free() 释放；没有内容时返回 NULL。
char *enclave_rime_get_commit(uint64_t session);
char *enclave_rime_get_preedit(uint64_t session);
char *enclave_rime_get_input(uint64_t session);

/// 取最多 limit 个候选词，每个用 free() 释放，返回实际数量。
size_t enclave_rime_get_candidates(uint64_t session, char **out, size_t limit);
bool enclave_rime_select_candidate(uint64_t session, size_t index);

#endif
