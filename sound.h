#ifndef SOUND_H_IDG
#define SOUND_H_IDG

#include "cubeb/cubeb.h"

typedef uint_fast32_t uint;
typedef _Bool bool;

#define PI 3.14159265358979323846

typedef struct {
    uint64_t t;
    uint sample_rate;
} NoteInput;

// TODO i should probably provide some synchronization
// around priv
typedef double (
        *NoteFn)(const NoteInput*, void* /* priv */);

typedef enum {
    NOTE_STATE_OFF,
    NOTE_STATE_ON,
} NoteState;

typedef struct {
    uint id;
    NoteState state;

    NoteFn fn;
    void* priv;
} Note;

typedef struct AudioContext AudioContext;

uint get_sample_rate(AudioContext* ctx);

void add_event(
        AudioContext* ctx,
        Note* note,
        uint64_t at_count);

int start_audio(AudioContext** ctx);
int stop_audio(AudioContext* ctx);

#endif
