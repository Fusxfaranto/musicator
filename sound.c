
#include "cubeb/cubeb.h"

#include <assert.h>
#include <math.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "sound.h"

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

#define ATOMIC_OP_MOD_FUNC(T, NAME, VAL)             \
    T atomic_##NAME##_mod_##T(_Atomic(T) * p, T m) { \
        for (;;) {                                   \
            T expected = atomic_load(p);             \
            T next = (expected + (VAL)) % m;         \
            bool cas_succeed =                       \
                    atomic_compare_exchange_weak(    \
                            p, &expected, next);     \
            if (cas_succeed) {                       \
                return expected;                     \
            }                                        \
        }                                            \
    }                                                \
    struct __swallow_semicolon_

#define ATOMIC_INC_MOD_FUNC(T) ATOMIC_OP_MOD_FUNC(T, inc, 1)
#define ATOMIC_DEC_MOD_FUNC(T) \
    ATOMIC_OP_MOD_FUNC(T, dec, m - 1)
ATOMIC_INC_MOD_FUNC(uint_fast32_t);
ATOMIC_DEC_MOD_FUNC(uint_fast32_t);
// TODO _Generic?
#define atomic_inc_mod atomic_inc_mod_uint_fast32_t
#define atomic_dec_mod atomic_dec_mod_uint_fast32_t

// TODO replace this with a refcount of # of fns actively
// modifying?
typedef enum {
    VALUE_KEEP,
    VALUE_RESET,
} ValueState;

typedef enum {
    EVENT_STATE_UNINITIALIZED,
    EVENT_STATE_READY,
    EVENT_STATE_PROCESSED,
} EventState;

typedef struct {
    uint64_t c;
    // TODO remove?
    double volume;

    ValueSetter* setter_buf;
    uint setter_buf_size;

    double* value_buf;
    ValueState* value_state_buf;
    uint value_buf_size;

    Event* event_buf;
    _Atomic(EventState) * event_state_buf;
    uint event_buf_size;
    uint event_pos;
    atomic_uint_fast32_t event_reserved_pos;
} StreamData;

typedef struct AudioContext {
    StreamData* stream_data_buf;
    uint stream_data_buf_size;

    uint sample_rate;

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
    return ctx->sample_rate;
}

// TODO control lock to make these thread safe?
void add_event(
        AudioContext* ctx,
        uint stream_id,
        const Event* e) {
    StreamData* p = &(ctx->stream_data_buf[stream_id]);

    // TODO in pathological scenarios, this can start
    // clobbering unprocessed events
    uint event_idx = atomic_inc_mod(
            &p->event_reserved_pos, p->event_buf_size);
    // TODO figure out what to actually do here, for
    // scrubbing purposes wrapping isn't really what we want
    // assert(event_idx != p->event_buf_size - 1);
    p->event_buf[event_idx] = *e;

    EventState old_state = atomic_exchange(
            &p->event_state_buf[event_idx],
            EVENT_STATE_READY);
    assert(old_state != EVENT_STATE_READY);
}

static void jump_stream(StreamData* p, uint to_count) {
    p->c = to_count;
    for (;;) {
        uint prev_event_pos =
                (p->event_pos + (p->event_buf_size - 1)) %
                p->event_buf_size;
        EventState event_state = atomic_load(
                &p->event_state_buf[prev_event_pos]);
        if (event_state == EVENT_STATE_UNINITIALIZED) {
            return;
        }

        // TODO this can probably happen?  figure it out
        // later
        assert(event_state == EVENT_STATE_PROCESSED);

        Event* e = &p->event_buf[prev_event_pos];

        if (e->at_count < to_count) {
            return;
        }

        bool cas_succeed = atomic_compare_exchange_strong(
                &p->event_state_buf[prev_event_pos],
                &event_state,
                EVENT_STATE_READY);
        if (!cas_succeed) {
            // TODO ???
            assert(0);
            continue;
        }

        p->event_pos = prev_event_pos;
    }
}

static uint process_events(StreamData* p, uint64_t n) {
    uint next_n;
    uint64_t end = p->c + n;

    for (;;) {
        if (atomic_load(
                    &p->event_state_buf[p->event_pos]) !=
            EVENT_STATE_READY) {
            return n;
        }

        Event* e = &p->event_buf[p->event_pos];
        if (e->at_count < p->c) {
            // event "in the past" (process it now, and
            // retroactively update its timestamp)
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

        case EVENT_RESET_STREAM: {
            // TODO add some sort of conditional
            // functionality here, to prevent every scrub
            // from being an infinite loop?
            // (but that might be bad from a reproducibility
            // standpoint)
            jump_stream(p, e->to_count);

            // since this modifies p->event_pos, need to
            // just return here
            return 0;
        }

        default:
            assert(0);
        }
        atomic_store(
                &p->event_state_buf[p->event_pos],
                EVENT_STATE_PROCESSED);

        p->event_pos =
                (p->event_pos + 1) % p->event_buf_size;
    }
}

static void generate_samples(
        StreamData* p,
        float* out,
        uint64_t n,
        uint sample_rate) {
    uint n_generated = 0;

    ValueInput value_input = (ValueInput){
            .t = p->c,
            .sample_rate = sample_rate,
            .values = p->value_buf,
    };

    for (;;) {
        // num samples to calculate until processing next
        // event
        uint64_t next_n = process_events(p, n - n_generated);

        // TODO it'd probably be faster to invert these
        // loops
        for (uint i = 0; i < next_n; i++) {
            // TODO if i want to support a large number of
            // values, this needs to be done differently
            for (uint j = 0; j < p->value_buf_size; j++) {
                if (p->value_state_buf[j] == VALUE_RESET) {
                    p->value_buf[j] = 0;
                }
            }

            bool expire = false;

            // TODO have a more explicit ordering scheme
            // than this?
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

            // TODO don't hardcode "special" value_buf idxs,
            // throw them in an enum or something
            double r = p->value_buf[0];
            r *= p->volume;

            // TODO stereo
            // TODO use integer samples instead of float?
            for (uint c = 0; c < 2; c++) {
                out[2 * i + c] += (float)r;
            }

            value_input.t++;
        }

        n_generated += next_n;
        p->c += next_n;
        out += 2 * next_n;

        if (n_generated == n) {
            break;
        }
        assert(n_generated < n);
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

    AudioContext* ctx = user;

    float* out = out_s;
    uint64_t n = (uint64_t)n_signed;

    for (uint i = 0; i < n; i++) {
        for (uint c = 0; c < 2; c++) {
            out[2 * i + c] = 0;
        }
    }

    for (uint i = 0; i < ctx->stream_data_buf_size; i++) {
        // TODO per-stream pause state
        generate_samples(
                &(ctx->stream_data_buf[i]),
                out,
                n,
                ctx->sample_rate);
    }

    return n_signed;
}

static void
state_cb(cubeb_stream* stm, void* user, cubeb_state state) {
    (void)stm;
    (void)user;
    (void)state;
}

static void init_stream_data(StreamData* p) {
    // TODO
    uint ebl = 1024 * 64;
    uint nbl = 64;
    uint value_num = 1024;

    *p = (StreamData){
            .c = 1,
            .volume = 1.0,

            .setter_buf = malloc(sizeof(ValueSetter) * nbl),
            .setter_buf_size = nbl,

            .value_buf = malloc(sizeof(double) * value_num),
            .value_state_buf =
                    malloc(sizeof(ValueState) * value_num),
            .value_buf_size = value_num,

            .event_buf = malloc(sizeof(Event) * ebl),
            .event_state_buf = malloc(
                    sizeof(_Atomic(EventState)) * ebl),
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
        atomic_store(
                &p->event_state_buf[i],
                EVENT_STATE_UNINITIALIZED);
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
    (*ctx)->sample_rate = sample_rate;
    printf("sample rate %u\n", sample_rate);

    output_params.format = CUBEB_SAMPLE_FLOAT32NE;
    output_params.rate = sample_rate;
    output_params.channels = 2;
    output_params.layout = CUBEB_LAYOUT_STEREO;
    output_params.prefs = CUBEB_STREAM_PREF_NONE;

    CHECK_CUBEB(cubeb_get_min_latency(
            (*ctx)->ctx, &output_params, &latency_frames));
    printf("latency frames %u\n", latency_frames);

    uint n_stream_data = 2;
    (*ctx)->stream_data_buf =
            malloc(sizeof(StreamData) * n_stream_data);
    (*ctx)->stream_data_buf_size = n_stream_data;
    for (uint i = 0; i < n_stream_data; i++) {
        init_stream_data(&((*ctx)->stream_data_buf[i]));
    }

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
            *ctx));
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
