#ifndef SOUND_H_IDG
#define SOUND_H_IDG

#include "cubeb/cubeb.h"

typedef uint_fast32_t uint;
typedef _Bool bool;

#define PI 3.14159265358979323846

// TODO do we want to provide this?
typedef struct {
    uint t;
} NoteInput;

typedef struct {
    uint t;
    uint sample_rate;
} NoteInputShared;

typedef double (*NoteFn)(
        const NoteInput*,
        const NoteInputShared*,
        int expire,
        void* /* priv */);

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

void event_note(
        AudioContext* ctx,
        uint64_t at_count,
        Note* note);

void event_write(
        AudioContext* ctx,
        uint64_t at_count,
        const void* source,
        size_t len,
        void* target);

int start_audio(AudioContext** ctx);
int stop_audio(AudioContext* ctx);

double low_pass_filter(
        double last_sample,
        double current_sample,
        double rc,
        uint sample_rate);

#endif
