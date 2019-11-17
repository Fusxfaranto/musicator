#ifndef SOUND_H_IDG
#define SOUND_H_IDG

#include "cubeb/cubeb.h"

typedef uint_fast32_t uint;
typedef _Bool bool;

#define PI 3.14159265358979323846
#define SEMITONE 1.0594630943592952646

typedef struct {
    // TODO very temporary
    double* ot_amps;
    uint ot_num;
} Instrument;

typedef enum {
    NOTE_STATE_OFF,
    NOTE_STATE_ON,
} NoteState;

// TODO some part of this needs to be atomic, otherwise this
// is thread unsafe
typedef struct {
    uint id;
    NoteState state;

    // TODO generic params
    double pitch;

    // TODO use an index instead?
    Instrument* instr;
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
