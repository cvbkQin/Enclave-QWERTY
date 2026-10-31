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

/// 同步用户词库（librime 的 sync_user_data），会阻塞到完成，只在主 App 里调用（备份与恢复 B3）：
/// 先把同步目录（用户目录下 sync/）里所有快照合并进用户词库（两边都有的词取权重大的），再把当前词库导出成快照
/// sync/<installation_id>/<词库>.userdb.txt。调用前键盘不能开着会话（LevelDB 的锁）。
/// librime 只同步已经存在的用户词库：ensure_schema 不为空时先用这个方案开一次会话再关掉，没打过字的新手机上也先建好空词库。
bool enclave_rime_sync_user_data(const char *shared_dir, const char *user_dir, const char *log_dir, const char *ensure_schema);

/// 用户词库（LevelDB）的 LOCK 文件是不是被别的进程锁着（键盘正开着会话）。LevelDB 用 fcntl 写锁，
/// 这里试着加同样的锁，加不上就是别人拿着；加上了马上放开。只在主 App 里、librime 没开着这个库时调用。
bool enclave_userdb_locked(const char *lock_path);

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
/// 从第 start 个候选词开始取，最多 limit 个；用来在候选栏滑到头、展开整页时再往后取。
size_t enclave_rime_get_candidates_from(uint64_t session, char **out, size_t start, size_t limit);
bool enclave_rime_select_candidate(uint64_t session, size_t index);
// 删掉用户词库里学到的这个候选（librime 的 delete_candidate）。词库自带的词删不掉，只会降回原来的位置。
bool enclave_rime_delete_candidate(uint64_t session, size_t index);
/// 读 context 的属性（方案里的 lua 写的），返回值用 free() 释放；没有或为空时返回 NULL。
char *enclave_rime_get_property(uint64_t session, const char *name);

#endif
