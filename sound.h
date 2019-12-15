#ifndef SOUND_H_IDG
#define SOUND_H_IDG

#include "cubeb/cubeb.h"

typedef uint_fast32_t uint;
typedef _Bool bool;

#define PI 3.14159265358979323846

typedef enum {
    BCOP_CALL,
    BCOP_COPY,
    BCOP_POP,
    BCOP_SWAP,
    BCOP_PUSH_FLT,
    BCOP_PUSH_T,
    BCOP_ADD,
    BCOP_MUL,
    BCOP_SIN,
} BCOp;

typedef struct BCProg BCProg;

typedef struct {
    union {
        BCOp op;
        double flt;
        BCProg* prog;
    };
} BCItem;

struct BCProg {
    size_t bc_len;
    BCItem* bc;
};

typedef enum {
    NOTE_STATE_OFF,
    NOTE_STATE_ON,
} NoteState;

typedef struct {
    uint id;
    NoteState state;

    BCProg prog;
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
