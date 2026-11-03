//
//  opencc_bridge.h
//
//  最小 OpenCC C API 宣告（對應 libopencc.xcframework 內已匯出的符號）。
//  上游標頭：https://github.com/BYVoid/OpenCC/blob/master/src/opencc.h
//

#ifndef OPENCC_BRIDGE_H
#define OPENCC_BRIDGE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void *opencc_t;
#define OPENCC_INVALID ((opencc_t)-1)

/// 以 .json 設定檔路徑開啟轉換器（如 s2t.json），失敗回傳 OPENCC_INVALID
opencc_t opencc_open(const char *config_file);
int opencc_close(opencc_t opencc_descriptor);
/// 回傳 malloc 的 UTF-8 字串，須用 opencc_convert_utf8_free 釋放
char *opencc_convert_utf8(opencc_t opencc_descriptor, const char *in, size_t length);
int opencc_convert_utf8_free(char *str);
const char *opencc_error(void);

#ifdef __cplusplus
}
#endif

#endif /* OPENCC_BRIDGE_H */
