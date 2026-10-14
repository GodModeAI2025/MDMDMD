/* Independent compatibility layer for the pinned Graal 22.1 / JDK 17 ABI.
 * No generated application delegate or Gluon bootstrap is linked here.
 * Copyright (c) 2026 Mark Zimmermann. See IOSRuntimeCompatibility-LICENSE.txt.
 */
#include <jni.h>
#include <stddef.h>
#include <string.h>
#include "aarch64cpufeatures.h"

_Static_assert(sizeof(CPUFeatures) == 17, "Review the pinned Graal CPU feature ABI");
_Static_assert(offsetof(CPUFeatures, fFP) == 0 && offsetof(CPUFeatures, fASIMD) == 1,
               "Review the pinned Graal AArch64 baseline fields");

void determineCPUFeatures(CPUFeatures *features) {
    if (features == NULL) { return; }
    // These two capabilities are the mandatory AArch64 baseline used by this
    // image. Do not advertise optional instructions without runtime detection.
    memset(features, 0, sizeof(*features));
    features->fFP = 1;
    features->fASIMD = 1;
}

JNIEXPORT jboolean JNICALL Java_java_net_AbstractPlainDatagramSocketImpl_isReusePortAvailable0(JNIEnv *env, jclass type) {
    (void)env; (void)type;
    return JNI_FALSE;
}

JNIEXPORT jboolean JNICALL Java_java_net_AbstractPlainSocketImpl_isReusePortAvailable0(JNIEnv *env, jclass type) {
    (void)env; (void)type;
    return JNI_FALSE;
}

JNIEXPORT void JNICALL Java_java_net_DatagramPacket_init(JNIEnv *env, jclass type) {
    (void)type;
    // Grammar checks have no datagram transport. Unexpected legacy networking
    // must fail explicitly instead of entering an unimplemented native ABI.
    if ((*env)->ExceptionCheck(env)) { return; }
    jclass error = (*env)->FindClass(env, "java/lang/UnsupportedOperationException");
    if (error != NULL) {
        (*env)->ThrowNew(env, error, "Datagram networking is unavailable in the offline grammar engine");
        (*env)->DeleteLocalRef(env, error);
    }
}
