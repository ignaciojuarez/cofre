// Thread QoS for the game's background Java threads (plan/ideal-engine.md,
// phase 1.6). iOS schedules by QoS: world workers, IO and downloads at utility
// leave the performance cores to the render and server threads. QoS is a hint,
// so this stays an engine experiment (EngineOptions.threadQoS) until a device
// bench shows it helps.
//
// A JVMTI ThreadStart callback runs on each new Java thread before its first
// Java code, so it can set that thread's own QoS. The iOS runtime ships no
// jvmti.h; the few entries used here are declared by their numbers in the JVMTI
// specification (function N sits at index N - 1 of the table). Header-only so
// the glue needs no new build entry and tests/engine/thread-qos.sh can run it
// against a desktop JDK.
#pragma once
#include "jni.h"
#include <dlfcn.h>
#include <pthread.h>
#include <pthread/qos.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>

typedef void *const *CofreJvmtiEnv;
enum {
  CofreJvmtiVersion = 0x30010200,
  CofreJvmtiEnable = 1,
  CofreJvmtiEventThreadStart = 52
};
enum {
  CofreJvmtiSetEventNotificationMode = 2,
  CofreJvmtiGetThreadInfo = 9,
  CofreJvmtiDeallocate = 47,
  CofreJvmtiSetEventCallbacks = 122,
};

typedef struct {
  char *name;
  jint priority;
  jboolean isDaemon;
  jobject threadGroup;
  jobject contextClassLoader;
} CofreJvmtiThreadInfo;

typedef void(JNICALL *CofreJvmtiThreadStart)(CofreJvmtiEnv *, JNIEnv *,
                                             jobject);
typedef struct {
  void *vmInit;
  void *vmDeath;
  CofreJvmtiThreadStart threadStart;
} CofreJvmtiCallbacks;

/// Called on the thread that changed QoS, so `qos_class_self()` reports the
/// result.
static void (*CofreThreadQoSLog)(const char *name, qos_class_t qos);
static atomic_bool CofreThreadQoSInstalled;

static inline void *CofreJvmtiFunction(CofreJvmtiEnv *env, int number) {
  return (void *)(*env)[number - 1];
}

/// Minecraft names its pools before starting them: Worker-Main-N, IO-Worker-N,
/// Download-N; Sodium's builders are "Chunk Render Task Executor #N". Unknown
/// threads keep the QoS they inherit.
static qos_class_t CofreQoSForThreadName(const char *name) {
  static const char *const utility[] = {"Worker-", "IO-Worker-", "Download-",
                                        "Chunk Render Task Executor", "c2me"};
  for (size_t i = 0; i < sizeof utility / sizeof *utility; i++) {
    if (strncmp(name, utility[i], strlen(utility[i])) == 0)
      return QOS_CLASS_UTILITY;
  }
  if (strcmp(name, "Server thread") == 0)
    return QOS_CLASS_USER_INITIATED;
  if (strcmp(name, "Render thread") == 0)
    return QOS_CLASS_USER_INTERACTIVE;
  return QOS_CLASS_UNSPECIFIED;
}

static void JNICALL CofreThreadQoSThreadStart(CofreJvmtiEnv *jvmti, JNIEnv *jni,
                                              jobject thread) {
  (void)jni;
  jint(JNICALL * getInfo)(CofreJvmtiEnv *, jobject, CofreJvmtiThreadInfo *) =
      CofreJvmtiFunction(jvmti, CofreJvmtiGetThreadInfo);
  jint(JNICALL * deallocate)(CofreJvmtiEnv *, unsigned char *) =
      CofreJvmtiFunction(jvmti, CofreJvmtiDeallocate);
  CofreJvmtiThreadInfo info = {0};
  if (getInfo(jvmti, thread, &info) != 0 || !info.name)
    return;
  qos_class_t qos = CofreQoSForThreadName(info.name);
  if (qos != QOS_CLASS_UNSPECIFIED &&
      pthread_set_qos_class_self_np(qos, 0) == 0 && CofreThreadQoSLog) {
    CofreThreadQoSLog(info.name, qos);
  }
  deallocate(jvmti, (unsigned char *)info.name);
}

/// Registers the ThreadStart callback on a running VM from a native thread.
static bool CofreThreadQoSInstall(JavaVM *vm) {
  JNIEnv *jni = NULL;
  if ((*vm)->AttachCurrentThreadAsDaemon(vm, (void *)&jni, NULL) != JNI_OK)
    return false;
  CofreJvmtiEnv *jvmti = NULL;
  bool ok =
      (*vm)->GetEnv(vm, (void **)&jvmti, CofreJvmtiVersion) == JNI_OK && jvmti;
  if (ok) {
    jint(JNICALL * setCallbacks)(CofreJvmtiEnv *, const CofreJvmtiCallbacks *,
                                 jint) =
        CofreJvmtiFunction(jvmti, CofreJvmtiSetEventCallbacks);
    jint(JNICALL * setMode)(CofreJvmtiEnv *, int, int, jobject, ...) =
        CofreJvmtiFunction(jvmti, CofreJvmtiSetEventNotificationMode);
    CofreJvmtiCallbacks callbacks = {.threadStart = CofreThreadQoSThreadStart};
    ok =
        setCallbacks(jvmti, &callbacks, (jint)sizeof callbacks) == 0 &&
        setMode(jvmti, CofreJvmtiEnable, CofreJvmtiEventThreadStart, NULL) == 0;
  }
  (*vm)->DetachCurrentThread(vm);
  return ok;
}

/// Waits up to two minutes for Air to create the JVM, then installs the
/// callback.
static void *CofreThreadQoSWatch(void *unused) {
  (void)unused;
  typedef jint (*GetCreatedVMs)(JavaVM **, jsize, jsize *);
  for (int attempt = 0; attempt < 6000; attempt++) {
    GetCreatedVMs created =
        (GetCreatedVMs)dlsym(RTLD_DEFAULT, "JNI_GetCreatedJavaVMs");
    JavaVM *vm = NULL;
    jsize count = 0;
    if (created && created(&vm, 1, &count) == JNI_OK && count > 0 && vm) {
      atomic_store(&CofreThreadQoSInstalled, CofreThreadQoSInstall(vm));
      return NULL;
    }
    usleep(20000);
  }
  return NULL;
}
