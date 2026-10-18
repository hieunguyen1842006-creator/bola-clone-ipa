//
//  AntiDetection.m
//  BolaClone
//
//  Lấy từ 3105 2.0-beta5 (YangJiiii, GPL-3.0):
//  ThreeOneOSFive/helpers/AntiDetection.m
//
//  Chặn kiểm tra jailbreak kiểu "fork() có chạy được không" trong CHÍNH process này.
//  Các process khác không bị ảnh hưởng. Đây là toàn bộ phần "ẩn mình" mà 3105 có.
//

#import <unistd.h>
#import <errno.h>

pid_t fork(void) {
    errno = EAGAIN;
    return -1;
}
