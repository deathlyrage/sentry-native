#ifndef SENTRY_SYNC_H_INCLUDED
#define SENTRY_SYNC_H_INCLUDED

#include "sentry_boot.h"

#include <assert.h>
#include <stdio.h>

// define a recursive mutex for all platforms
#ifdef SENTRY_PLATFORM_WINDOWS
#    include <synchapi.h>
#    include <winnt.h>
struct sentry__winmutex_s {
    INIT_ONCE init_once;
    CRITICAL_SECTION critical_section;
};

static inline BOOL CALLBACK
sentry__winmutex_init(PINIT_ONCE InitOnce, PVOID cs, PVOID *lpContext)
{
    InitializeCriticalSection(cs);
    return TRUE;
}

static inline void
sentry__winmutex_lock(struct sentry__winmutex_s *mutex)
{
    InitOnceExecuteOnce(&mutex->init_once, sentry__winmutex_init,
        &mutex->critical_section, NULL);
    EnterCriticalSection(&mutex->critical_section);
}

typedef HANDLE sentry_threadid_t;
typedef struct sentry__winmutex_s sentry_mutex_t;
typedef CONDITION_VARIABLE sentry_cond_t;
#    define SENTRY__MUTEX_INIT                                                 \
        {                                                                      \
            INIT_ONCE_STATIC_INIT, { 0 }                                       \
        }
#    define sentry__mutex_lock(Lock) sentry__winmutex_lock(Lock)
#    define sentry__mutex_unlock(Lock)                                         \
        LeaveCriticalSection(&(Lock)->critical_section)
#    define SENTRY__COND_INIT                                                  \
        {                                                                      \
            0                                                                  \
        }
#    define sentry__cond_wait_timeout(CondVar, Lock, Timeout)                  \
        SleepConditionVariableCS(CondVar, &(Lock)->critical_section, Timeout)
#    define sentry__cond_wait(CondVar, Lock)                                   \
        sentry__cond_wait_timeout(CondVar, Lock, INFINITE)
#    define sentry__cond_wake WakeConditionVariable
#    define sentry__thread_spawn(ThreadId, Func, Data)                         \
        (*ThreadId = CreateThread(NULL, 0, Func, Data, 0, NULL),               \
            *ThreadId == INVALID_HANDLE_VALUE ? 1 : 0)
#    define sentry__thread_join(ThreadId)                                      \
        WaitForSingleObject(ThreadId, INFINITE)
#else
#    include <errno.h>
#    include <pthread.h>
#    include <sys/time.h>

/* on unix systems signal handlers can interrupt anything which means that
   we're restricted in what we can do.  In particular it's possible that
   we would end up dead locking outselves.  While we cannot fully prevent
   races we have a logic here that while the signal handler is active we're
   disabling our mutexes so that our signal handler can access what otherwise
   would be protected by the mutex but everyone else needs to wait for the
   signal handler to finish.  This is not without risk because another thread
   might still access what the mutex protects.

   We are thus taking care that whatever such mutexes protect will not make
   us crash under concurrent modifications.  The mutexes we're likely going
   to hit are the options and scope lock. */
bool sentry__block_for_signal_handler(void);
void sentry__enter_signal_handler(void);
void sentry__leave_signal_handler(void);

typedef pthread_t sentry_threadid_t;
typedef pthread_mutex_t sentry_mutex_t;
typedef pthread_cond_t sentry_cond_t;
#    ifdef SENTRY_PLATFORM_LINUX
#        define SENTRY__MUTEX_INIT PTHREAD_RECURSIVE_MUTEX_INITIALIZER_NP
#    else
#        define SENTRY__MUTEX_INIT PTHREAD_RECURSIVE_MUTEX_INITIALIZER
#    endif
#    define sentry__mutex_lock(Mutex)                                          \
        do {                                                                   \
            if (sentry__block_for_signal_handler()) {                          \
                int _rv = pthread_mutex_lock(Mutex);                           \
                assert(_rv == 0);                                              \
            }                                                                  \
        } while (0)
#    define sentry__mutex_unlock(Mutex)                                        \
        do {                                                                   \
            if (sentry__block_for_signal_handler()) {                          \
                pthread_mutex_unlock(Mutex);                                   \
            }                                                                  \
        } while (0)
#    define SENTRY__COND_INIT PTHREAD_COND_INITIALIZER
#    define sentry__cond_wait(Cond, Mutex)                                     \
        do {                                                                   \
            if (sentry__block_for_signal_handler()) {                          \
                pthread_cond_wait(Cond, Mutex);                                \
            }                                                                  \
        } while (0)
#    define sentry__cond_wake pthread_cond_signal
#    define sentry__thread_spawn(ThreadId, Func, Data)                         \
        (pthread_create(ThreadId, NULL, (void *(*)(void *))Func, Data) == 0    \
                ? 0                                                            \
                : 1)
#    define sentry__thread_join(ThreadId) pthread_join(ThreadId, NULL)
#    define sentry__threadid_equal pthread_equal
#    define sentry__current_thread pthread_self

static inline int
sentry__cond_wait_timeout(
    sentry_cond_t *cv, sentry_mutex_t *mutex, uint64_t msecs)
{
    if (!sentry__block_for_signal_handler()) {
        return 0;
    }
    struct timeval now;
    struct timespec lock_time;
    gettimeofday(&now, NULL);
    lock_time.tv_sec = now.tv_sec + msecs / 1000ULL;
    lock_time.tv_nsec = (now.tv_usec + 1000ULL * (msecs % 1000)) * 1000ULL;
    return pthread_cond_timedwait(cv, mutex, &lock_time);
}
#endif
#define sentry__mutex_init(Mutex)                                              \
    do {                                                                       \
        sentry_mutex_t tmp = SENTRY__MUTEX_INIT;                               \
        *(Mutex) = tmp;                                                        \
    } while (0)
#define sentry__cond_init(CondVar)                                             \
    do {                                                                       \
        sentry_cond_t tmp = SENTRY__COND_INIT;                                 \
        *(CondVar) = tmp;                                                      \
    } while (0)

static inline int
sentry__atomic_fetch_and_add(volatile int *val, int diff)
{
#ifdef SENTRY_PLATFORM_WINDOWS
    return InterlockedExchangeAdd(val, diff);
#else
    return __sync_fetch_and_add(val, diff);
#endif
}

static inline int
sentry__atomic_fetch(volatile int *val)
{
    return sentry__atomic_fetch_and_add(val, 0);
}

struct sentry_bgworker_s;
typedef struct sentry_bgworker_s sentry_bgworker_t;

typedef void (*sentry_task_function_t)(void *data);

sentry_bgworker_t *sentry__bgworker_new(void);
void sentry__bgworker_free(sentry_bgworker_t *bgw);
void sentry__bgworker_start(sentry_bgworker_t *bgw);
int sentry__bgworker_shutdown(sentry_bgworker_t *bgw, uint64_t timeout);
int sentry__bgworker_submit(sentry_bgworker_t *bgw,
    sentry_task_function_t exec_func, sentry_task_function_t cleanup_func,
    void *data);

#endif