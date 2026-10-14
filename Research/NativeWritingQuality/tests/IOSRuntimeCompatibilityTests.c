#include <assert.h>
#include <jni.h>
#include <stdio.h>
#include <string.h>
#include "aarch64cpufeatures.h"

void determineCPUFeatures(CPUFeatures *);
jboolean Java_java_net_AbstractPlainDatagramSocketImpl_isReusePortAvailable0(JNIEnv *, jclass);
jboolean Java_java_net_AbstractPlainSocketImpl_isReusePortAvailable0(JNIEnv *, jclass);
void Java_java_net_DatagramPacket_init(JNIEnv *, jclass);

static int throws, deletes, finds;
static jboolean pending;
static jboolean check_exception(JNIEnv *env) { (void)env; return pending; }
static jclass find_class(JNIEnv *env, const char *name) {
    (void)env; finds++;
    assert(strcmp(name, "java/lang/UnsupportedOperationException") == 0);
    return (jclass)(void *)&finds;
}
static jint throw_error(JNIEnv *env, jclass type, const char *message) {
    (void)env; assert(type != NULL); assert(strstr(message, "offline grammar engine") != NULL);
    throws++; return 0;
}
static void delete_ref(JNIEnv *env, jobject value) { (void)env; assert(value != NULL); deletes++; }

int main(void) {
    struct { unsigned char prefix; CPUFeatures flags; unsigned char suffix; } guarded;
    memset(&guarded, 0x7f, sizeof(guarded));
    determineCPUFeatures(&guarded.flags);
    assert(guarded.prefix == 0x7f && guarded.suffix == 0x7f);
    assert(guarded.flags.fFP == 1 && guarded.flags.fASIMD == 1);
    for (size_t i = 2; i < sizeof(CPUFeatures); ++i) { assert(((unsigned char *)&guarded.flags)[i] == 0); }
    assert(Java_java_net_AbstractPlainDatagramSocketImpl_isReusePortAvailable0(NULL, NULL) == JNI_FALSE);
    assert(Java_java_net_AbstractPlainSocketImpl_isReusePortAvailable0(NULL, NULL) == JNI_FALSE);

    const struct JNINativeInterface_ table = { .ExceptionCheck = check_exception, .FindClass = find_class,
        .ThrowNew = throw_error, .DeleteLocalRef = delete_ref };
    JNIEnv env = &table;
    Java_java_net_DatagramPacket_init(&env, NULL);
    assert(finds == 1 && throws == 1 && deletes == 1);
    pending = JNI_TRUE;
    Java_java_net_DatagramPacket_init(&env, NULL);
    assert(finds == 1 && throws == 1 && deletes == 1);
    puts("{\"passed\":true,\"checks\":4,\"scope\":\"Host C ABI and JNI mock; not iOS execution\"}");
    return 0;
}
