
#include "sound.h"

#include <assert.h>
#include <math.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#define false ((bool)0)
#define true ((bool)1)

#define CHECK(x, v)                                  \
    {                                                \
        int __res;                                   \
        if ((__res = (x)) != v) {                    \
            printf("cond " #x " == " #v " false\n"); \
            return __res;                            \
        }                                            \
    }
#define CHECK_CUBEB(x) CHECK(x, CUBEB_OK)
#define ARRAY_LEN(a) (sizeof(a) / sizeof(a[0]))

#define ATOMIC_INC_MOD_FUNC(T)                    \
    T atomic_inc_mod_##T(_Atomic(T) * p, T m) {   \
        for (;;) {                                \
            T expected = atomic_load(p);          \
            T next = (expected + 1) % m;          \
            bool cas_succeed =                    \
                    atomic_compare_exchange_weak( \
                            p, &expected, next);  \
            if (cas_succeed) {                    \
                return expected;                  \
            }                                     \
        }                                         \
    }                                             \
    struct __swallow_semicolon_
ATOMIC_INC_MOD_FUNC(uint_fast32_t);
// TODO _Generic?
#define atomic_inc_mod atomic_inc_mod_uint_fast32_t

typedef enum {
    VALUE_KEEP,
    VALUE_RESET,
} ValueState;

typedef struct {
    uint64_t c;
    uint sample_rate;
    double volume;

    ValueSetter* setter_buf;
    uint setter_buf_size;

    double* value_buf;
    ValueState* value_state_buf;
    uint value_buf_size;

    Event* event_buf;
    atomic_bool* event_ready;
    uint event_buf_size;
    uint event_pos;
    atomic_uint_fast32_t event_reserved_pos;
} StreamPriv;

typedef struct AudioContext {
    StreamPriv priv;
    cubeb_stream* stream;
    cubeb* ctx;
} AudioContext;

// TODO is this unstable?
double low_pass_filter(
        double last_sample,
        double current_sample,
        double rc,
        uint sample_rate) {
    double alpha = 1 / (rc * (double)sample_rate + 1);
    return last_sample +
           alpha * (current_sample - last_sample);
}

uint get_sample_rate(AudioContext* ctx) {
    return ctx->priv.sample_rate;
}

void add_event(AudioContext* ctx, const Event* e) {
    StreamPriv* p = &ctx->priv;

    uint event_idx = atomic_inc_mod(
            &p->event_reserved_pos, p->event_buf_size);
    p->event_buf[event_idx] = *e;

    assert(!atomic_load(&p->event_ready[event_idx]));
    atomic_store(&p->event_ready[event_idx], true);
}

static uint process_events(StreamPriv* p, uint64_t n) {
    uint next_n;
    uint64_t end = p->c + n;

    for (;;) {
        if (!atomic_load(&p->event_ready[p->event_pos])) {
            return n;
        }

        Event* e = &p->event_buf[p->event_pos];
        if (e->at_count < p->c) {
            // event "in the past" (process it now)
            e->at_count = p->c;
        }
        if (e->at_count < end) {
            // event will need processing
            next_n = e->at_count - p->c;
        } else {
            // event not needed this call
            next_n = end - p->c;
        }

        if (next_n != 0) {
            // event doesn't need processing yet
            return next_n;
        }

        printf("processing event %lu\n", p->event_pos);

        switch (e->type) {
        case EVENT_SETTER: {
            uint setter_buf_idx = (uint)-1;
            // TODO something faster if we're not updating
            // an existing note?
            for (uint i = 0; i < p->setter_buf_size; i++) {
                if (p->setter_buf[i].id == e->setter.id) {
                    setter_buf_idx = i;
                    break;
                }
            }
            if (setter_buf_idx == (uint)-1) {
                for (uint i = 0; i < p->setter_buf_size;
                     i++) {
                    if (p->setter_buf[i].fn == NULL) {
                        setter_buf_idx = i;
                        break;
                    }
                }
            }
            // TODO handle out-of-space
            assert(setter_buf_idx != (uint)-1);

            p->setter_buf[setter_buf_idx] = e->setter;
            assert(e->setter.target_idx >= 0 &&
                   (uint)(e->setter.target_idx) <
                           p->value_buf_size);
            p->value_state_buf[e->setter.target_idx] =
                    VALUE_RESET;
            break;
        }

        case EVENT_WRITE: {
            assert(e->target_idx >= 0 &&
                   (uint)(e->target_idx) <
                           p->value_buf_size);
            p->value_state_buf[e->target_idx] = VALUE_KEEP;
            p->value_buf[e->target_idx] = e->value;
            break;
        }

        case EVENT_WRITE_TIME: {
            assert(e->target_idx >= 0 &&
                   (uint)(e->target_idx) <
                           p->value_buf_size);
            p->value_state_buf[e->target_idx] = VALUE_KEEP;
            // TODO bad
            *(uint*)(&p->value_buf[e->target_idx]) = p->c;
            break;
        }
        }
        atomic_store(&p->event_ready[p->event_pos], false);

        p->event_pos =
                (p->event_pos + 1) % p->event_buf_size;
    }
}

static long data_cb(
        cubeb_stream* stm,
        void* user,
        const void* in_s,
        void* out_s,
        long n_signed) {
    (void)stm;
    (void)in_s;

    StreamPriv* p = user;

    float* out = out_s;
    uint64_t n = (uint64_t)n_signed;
    uint64_t end = p->c + n;

    ValueInput value_input = (ValueInput){
            .t = p->c,
            .sample_rate = p->sample_rate,
            .values = p->value_buf,
    };

    for (;;) {
        // num samples to calculate until processing next
        // event
        uint64_t next_n = process_events(p, n);

        // TODO don't clear every value?
        // (have some extra per-value state?)
        for (uint i = 0; i < p->value_buf_size; i++) {
            if (p->value_state_buf[i] == VALUE_RESET) {
                p->value_buf[i] = 0;
            }
        }

        // TODO it'd probably be faster to invert these
        // loops
        for (uint i = 0; i < next_n; i++) {
            bool expire = false;

            for (uint setter_idx = 0;
                 setter_idx < p->setter_buf_size;
                 setter_idx++) {
                if (p->setter_buf[setter_idx].fn) {
                    double* target =
                            &p->value_buf
                                     [p->setter_buf[setter_idx]
                                              .target_idx];
                    *target += p->setter_buf[setter_idx].fn(
                            &value_input,
                            p->setter_buf[setter_idx]
                                    .local_idxs,
                            &expire);

                    if (expire) {
                        p->setter_buf[setter_idx] =
                                EMPTY_SETTER;
                        expire = false;
                    }
                }
            }

            double r = p->value_buf[0];
            r *= p->volume;

            // TODO stereo
            // TODO use integer samples instead of float?
            for (uint c = 0; c < 2; c++) {
                out[2 * i + c] = (float)r;
            }

            value_input.t++;
        }

        p->c += next_n;
        out += 2 * next_n;

        if (p->c == end) {
            break;
        }
        assert(p->c < end);
    }

    p->c = end;
    return n_signed;
}

static void
state_cb(cubeb_stream* stm, void* user, cubeb_state state) {
    (void)stm;
    (void)user;
    (void)state;
}

static void init_stream_priv(
        StreamPriv* p,
        uint sample_rate) {
    // TODO
    uint ebl = 4096;
    uint nbl = 64;
    uint value_num = 4096;

    *p = (StreamPriv){
            .c = 0,
            .sample_rate = sample_rate,
            .volume = 1.0,

            .setter_buf = malloc(sizeof(ValueSetter) * nbl),
            .setter_buf_size = nbl,

            .value_buf = malloc(sizeof(double) * value_num),
            .value_state_buf =
                    malloc(sizeof(ValueState) * value_num),
            .value_buf_size = value_num,

            .event_buf = malloc(sizeof(Event) * ebl),
            .event_ready = malloc(sizeof(bool) * ebl),
            .event_buf_size = ebl,
    };

    for (uint i = 0; i < value_num; i++) {
        p->value_buf[i] = NAN;
        p->value_state_buf[i] = VALUE_KEEP;
    }
    p->value_state_buf[0] = VALUE_RESET;

    for (uint i = 0; i < nbl; i++) {
        p->setter_buf[i] = EMPTY_SETTER;
    }

    for (uint i = 0; i < ebl; i++) {
        atomic_store(&p->event_ready[i], false);
    }
    atomic_store(&p->event_pos, 0);
    atomic_store(&p->event_reserved_pos, 0);
}

int start_audio(AudioContext** ctx) {
    *ctx = malloc(sizeof(AudioContext));
    cubeb_init(&((*ctx)->ctx), "musicator", NULL);
    uint32_t sample_rate;
    uint32_t latency_frames;

    cubeb_stream_params output_params = {0};

    CHECK_CUBEB(cubeb_get_preferred_sample_rate(
            (*ctx)->ctx, &sample_rate));
    printf("sample rate %u\n", sample_rate);

    output_params.format = CUBEB_SAMPLE_FLOAT32NE;
    output_params.rate = sample_rate;
    output_params.channels = 2;
    output_params.layout = CUBEB_LAYOUT_STEREO;
    output_params.prefs = CUBEB_STREAM_PREF_NONE;

    CHECK_CUBEB(cubeb_get_min_latency(
            (*ctx)->ctx, &output_params, &latency_frames));
    printf("latency frames %u\n", latency_frames);

    init_stream_priv(&((*ctx)->priv), sample_rate);

    CHECK_CUBEB(cubeb_stream_init(
            (*ctx)->ctx,
            &((*ctx)->stream),
            "sound",
            NULL,
            NULL,
            NULL,
            &output_params,
            latency_frames,
            data_cb,
            state_cb,
            &((*ctx)->priv)));
    CHECK_CUBEB(cubeb_stream_start((*ctx)->stream));

    return 0;
}

int stop_audio(AudioContext* ctx) {
    CHECK_CUBEB(cubeb_stream_stop(ctx->stream));
    cubeb_stream_destroy(ctx->stream);
    cubeb_destroy(ctx->ctx);
    free(ctx);

    return 0;
}
