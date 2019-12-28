#ifndef SOUND_H_IDG
#define SOUND_H_IDG

#include "cubeb/cubeb.h"

typedef uint_fast32_t uint;
typedef _Bool bool;

#define PI 3.14159265358979323846

typedef struct {
    uint t;
} NoteInput;

typedef struct {
    uint t;
    uint sample_rate;
} NoteInputShared;

// TODO i should probably provide some synchronization
// around priv
typedef double (*NoteFn)(
        const NoteInput*,
        const NoteInputShared*,
        int expire,
        const void* /* priv */);

typedef struct {
    uint id;
    int expire;

    NoteFn fn;
    void* priv;
} Note;

// if expire is <= this, note does not expire
const int EXPIRE_INDEFINITE = -268435455;

#define EMPTY_NOTE \
    (Note) { .id = 0, .fn = NULL }

typedef struct AudioContext AudioContext;

uint get_sample_rate(AudioContext* ctx);

void add_event(
        AudioContext* ctx,
        Note* note,
        uint64_t at_count);

int start_audio(AudioContext** ctx);
int stop_audio(AudioContext* ctx);

#endif
