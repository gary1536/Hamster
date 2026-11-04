//
//  irime_maintenance.mm
//  RimeKit
//
//  Gary fork：librime 的 maintenance 在背景執行緒執行，執行緒中拋出的 C++ 例外會在
//  RimeJoinMaintenanceThread() 的 future::get() 重新拋出。irime_api.m 是純 Objective-C，
//  接不住 C++ 例外，App 會直接 abort（例如 build/ 裡有 0 byte 的 *.prism.bin 時，
//  boost::interprocess 做 mmap 會丟 interprocess_exception）。這裡用 ObjC++ 包起來。
//

#import <Foundation/Foundation.h>

#include <exception>

#import "../C/rime_api.h"

/// 等待 maintenance 結束並部署 squirrel.yaml。成功回傳 nil，失敗回傳錯誤訊息。
extern "C" NSString *_Nullable IRimeFinishMaintenanceSafely(void) {
  try {
    RimeJoinMaintenanceThread();
    RimeDeployConfigFile("squirrel.yaml", "config_version");
    return nil;
  } catch (const std::exception &e) {
    NSString *what = [NSString stringWithUTF8String:e.what()];
    return what.length > 0 ? what : @"std::exception";
  } catch (...) {
    return @"unknown exception";
  }
}
