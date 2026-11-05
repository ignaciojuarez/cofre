// Runs app/Glue/AirBridge/CofreThreadQoS.h against a desktop JDK: the hand-declared JVMTI layout must match the
// real jvmti.h, and named Java threads must come up with the QoS the table promises.
#include "CofreThreadQoS.h"
#include <jvmti.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>

#define SLOT(field, number) \
  _Static_assert(offsetof(struct jvmtiInterface_1_, field) == ((number) - 1) * sizeof(void *), #field)
SLOT(SetEventNotificationMode, CofreJvmtiSetEventNotificationMode);
SLOT(GetThreadInfo, CofreJvmtiGetThreadInfo);
SLOT(Deallocate, CofreJvmtiDeallocate);
SLOT(SetEventCallbacks, CofreJvmtiSetEventCallbacks);
_Static_assert(offsetof(jvmtiEventCallbacks, ThreadStart) == offsetof(CofreJvmtiCallbacks, threadStart), "ThreadStart");
_Static_assert(sizeof(jvmtiThreadInfo) == sizeof(CofreJvmtiThreadInfo), "thread info size");
_Static_assert(offsetof(jvmtiThreadInfo, context_class_loader) == offsetof(CofreJvmtiThreadInfo, contextClassLoader),
               "thread info layout");
_Static_assert(JVMTI_VERSION_1_2 == CofreJvmtiVersion && JVMTI_ENABLE == CofreJvmtiEnable &&
                   JVMTI_EVENT_THREAD_START == CofreJvmtiEventThreadStart, "constants");

static void record(const char *name, qos_class_t requested) {
  printf("qos %s requested=%#x now=%#x\n", name, requested, qos_class_self());
  fflush(stdout);
}

int main(void) {
  CofreThreadQoSLog = record;
  JavaVMOption options[] = {{.optionString = "-Xint"}};
  JavaVMInitArgs args = {.version = JNI_VERSION_1_8, .nOptions = 1, .options = options};
  JavaVM *vm;
  JNIEnv *env;
  if (JNI_CreateJavaVM(&vm, (void **)&env, &args) != JNI_OK) return 2;
  pthread_t watcher;
  pthread_create(&watcher, NULL, CofreThreadQoSWatch, NULL);
  pthread_join(watcher, NULL);
  if (!atomic_load(&CofreThreadQoSInstalled)) return 3;
  jclass threadClass = (*env)->FindClass(env, "java/lang/Thread");
  jmethodID init = (*env)->GetMethodID(env, threadClass, "<init>", "(Ljava/lang/String;)V");
  jmethodID start = (*env)->GetMethodID(env, threadClass, "start", "()V");
  jmethodID join = (*env)->GetMethodID(env, threadClass, "join", "()V");
  const char *names[] = {"Worker-Main-1", "IO-Worker-3", "Server thread", "Chunk Render Task Executor #2", "Other"};
  for (size_t i = 0; i < sizeof names / sizeof *names; i++) {
    jobject thread = (*env)->NewObject(env, threadClass, init, (*env)->NewStringUTF(env, names[i]));
    (*env)->CallVoidMethod(env, thread, start);
    (*env)->CallVoidMethod(env, thread, join);
  }
  return (*env)->ExceptionCheck(env) ? 4 : 0;
}
