
#include "../sound.h"

#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-parameter"

double foo(
        const ValueInput* input,
        const int* local_idxs,
        bool* expire) {
    double t = (double)(input->t);

    return sin(t / 40) * sin(t / 72);
}

int main() {
    AudioContext* ctx = NULL;
    assert(start_audio(&ctx) == 0);

    //int event_id = 0;
    Event e;
    e = (Event){
            .type = EVENT_SETTER,
            .setter =
                    (ValueSetter){
                            .fn = foo,
                            .local_idxs = NULL,
                            .target_idx = 0,
                            .id = 0,
                    },
            .at_count = 0,
    };
    add_event(ctx, 0, &e);

    stream_play(ctx, 0);
    sleep(100);

    assert(stop_audio(ctx) == 0);
}

#pragma GCC diagnostic pop
