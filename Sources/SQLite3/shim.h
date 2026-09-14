// Windows：把系统自带的 SQLite（winsqlite3.dll）暴露成 `SQLite3` 模块。
//
// 不依赖 Windows SDK 的 winsqlite3.h（新 SDK 未必提供，且 SwiftPM C 模块的
// include 路径也找不到它），这里只声明本项目实际用到的那部分稳定 C API。
// SQLite 的 C ABI 长期稳定，声明子集是安全做法。

#ifndef TOKCAT_WINDOWS_SQLITE_SHIM_H
#define TOKCAT_WINDOWS_SQLITE_SHIM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct sqlite3 sqlite3;
typedef struct sqlite3_stmt sqlite3_stmt;
typedef long long sqlite3_int64;
typedef void (*sqlite3_destructor_type)(void *);

#define SQLITE_OK 0
#define SQLITE_ROW 100
#define SQLITE_DONE 101
#define SQLITE_NULL 5
#define SQLITE_OPEN_READONLY 0x00000001

int sqlite3_open(const char *filename, sqlite3 **ppDb);
int sqlite3_open_v2(const char *filename, sqlite3 **ppDb, int flags, const char *zVfs);
int sqlite3_close(sqlite3 *db);
int sqlite3_busy_timeout(sqlite3 *db, int ms);
int sqlite3_exec(sqlite3 *db, const char *sql,
                 int (*callback)(void *, int, char **, char **), void *arg, char **errmsg);
void sqlite3_free(void *p);

int sqlite3_prepare_v2(sqlite3 *db, const char *zSql, int nByte,
                       sqlite3_stmt **ppStmt, const char **pzTail);
int sqlite3_finalize(sqlite3_stmt *pStmt);
int sqlite3_step(sqlite3_stmt *pStmt);
int sqlite3_bind_int64(sqlite3_stmt *pStmt, int i, sqlite3_int64 v);
int sqlite3_bind_double(sqlite3_stmt *pStmt, int i, double v);
int sqlite3_bind_text(sqlite3_stmt *pStmt, int i, const char *v, int n,
                      sqlite3_destructor_type d);
int sqlite3_bind_null(sqlite3_stmt *pStmt, int i);
int sqlite3_column_type(sqlite3_stmt *pStmt, int i);
sqlite3_int64 sqlite3_column_int64(sqlite3_stmt *pStmt, int i);
double sqlite3_column_double(sqlite3_stmt *pStmt, int i);
const unsigned char *sqlite3_column_text(sqlite3_stmt *pStmt, int i);

#ifdef __cplusplus
}
#endif

#endif
