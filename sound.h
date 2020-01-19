#ifndef SOUND_H_IDG
#define SOUND_H_IDG

#include "cubeb/cubeb.h"

typedef uint64_t uint;
typedef _Bool bool;

#define PI 3.14159265358979323846

typedef struct {
    uint t;
    uint sample_rate;

    double* values;
} ValueInput;

typedef double (*ValueFn)(
        const ValueInput* input,
        const int* local_idxs,
        bool* expire);

typedef struct {
    ValueFn fn;
    int* local_idxs;

    int target_idx;
    int id;
} ValueSetter;

#define EMPTY_SETTER \
    (ValueSetter) { .id = -1, .target_idx = -1, }

typedef enum {
    EVENT_SETTER,
    EVENT_WRITE,
    EVENT_WRITE_TIME,
} EventType;

typedef struct {
    EventType type;
    union {
        ValueSetter setter;
        struct {
            int target_idx;
            double value;
        };
    };

    uint at_count;
} Event;

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

void add_event(AudioContext* ctx, uint stream_id, const Event* event);

int start_audio(AudioContext** ctx);
int stop_audio(AudioContext* ctx);

double low_pass_filter(
        double last_sample,
        double current_sample,
        double rc,
        uint sample_rate);

#endif
