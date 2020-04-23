#ifndef SOUND_H_IDG
#define SOUND_H_IDG

#include <stdint.h>

typedef uint64_t uint;
typedef _Bool bool;

const bool false = 0;
const bool true = 1;

#define PI 3.14159265358979323846

typedef union {
    double d;
    uint64_t u;
} Value;

typedef struct {
    uint t;
    uint sample_rate;

    Value* values;
} ValueInput;

typedef double (*ValueFn)(
        const ValueInput* input,
        const int* local_idxs,
        bool* expire);

typedef struct {
    // TODO replace with index into jump table, to make
    // modifying instruments simpler?
    ValueFn fn;
    const int* local_idxs;

    int target_idx;
    int id;
} ValueSetter;

#define EMPTY_SETTER \
    (ValueSetter) { .id = -1, .target_idx = -1, }

typedef enum {
    EVENT_SETTER,
    EVENT_WRITE,
    EVENT_WRITE_TIME,
    EVENT_RESET_STREAM,
} EventType;

typedef struct {
    EventType type;
    union {
        ValueSetter setter;
        struct {
            int target_idx;
            Value value;
        };
        uint to_count;
    };

    uint at_count;
} Event;

typedef struct AudioContext AudioContext;

uint get_sample_rate(AudioContext* ctx);

// TODO at some point going to need some sort of toposort to
// figure out dependencies between different values (which
// also means the runtime needs to be aware of input
// dependencies)

int get_name_idx(
        AudioContext* ctx,
        uint stream_id,
        const char* name);
void add_event(
        AudioContext* ctx,
        uint stream_id,
        const Event* event);
void clear_events(AudioContext* ctx, uint stream_id);

void stream_play(AudioContext* ctx, uint stream_id);
void stream_pause(AudioContext* ctx, uint stream_id);
void stream_scrub(
        AudioContext* ctx,
        uint stream_id,
        uint to_count);

int start_audio(AudioContext** ctx);
int stop_audio(AudioContext* ctx);

double low_pass_filter(
        double last_sample,
        double current_sample,
        double rc,
        uint sample_rate);

#endif
