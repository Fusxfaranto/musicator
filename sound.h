#ifndef SOUND_H_IDG
#define SOUND_H_IDG

#include "cubeb/cubeb.h"

typedef uint64_t uint;
typedef _Bool bool;

#define PI 3.14159265358979323846

// TODO provide start/release times here?
typedef struct {
    // TODO do we want to provide this?
    uint t;
} NoteInput;

typedef struct {
    uint t;
    uint sample_rate;
} NoteInputShared;

typedef double (*NoteFn)(
        const NoteInput*,
        const NoteInputShared*,
        bool* expire,
        const void* /* priv */);

typedef struct {
    uint id;

    NoteFn fn;
    void* priv;
} Note;

#define EMPTY_NOTE \
    (Note) { .id = 0, .fn = NULL }

typedef struct AudioContext AudioContext;

uint get_sample_rate(AudioContext* ctx);

// TODO add event to set value to function
// TODO consider:
// - make "set value to function" identical to "note with
// function"
// - add "consolidation function" to genericize summation of
// multiple assignments?

// TODO at some point going to need some sort of toposort to
// figure out dependencies between different values (which
// also means the runtime needs to be aware of input
// dependencies)

// TODO consolidate these by exposing Event
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

void event_write_time(
        AudioContext* ctx,
        uint64_t at_count,
        uint* target);

int start_audio(AudioContext** ctx);
int stop_audio(AudioContext* ctx);

double low_pass_filter(
        double last_sample,
        double current_sample,
        double rc,
        uint sample_rate);

#endif
