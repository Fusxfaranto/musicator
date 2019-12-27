
#include "sound.h"

#include <assert.h>
#include <math.h>
#include <stdatomic.h>
#include <stdio.h>
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

typedef struct {
    uint64_t at_count;
    Note note;
} Event;

typedef struct {
    uint64_t c;
    uint sample_rate;
    double volume;

    Note* note_buf;
    uint note_buf_size;
    atomic_uint_fast32_t note_next_id;

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

uint get_sample_rate(AudioContext* ctx) {
    return ctx->priv.sample_rate;
}

void add_event(
        AudioContext* ctx,
        Note* note,
        uint64_t at_count) {
    StreamPriv* p = &ctx->priv;

    if (note->id == 0) {
        note->id = atomic_fetch_add(&p->note_next_id, 1);
        assert(atomic_load(&p->note_next_id) != 0);
    }

    uint event_idx = atomic_inc_mod(
            &p->event_reserved_pos, p->event_buf_size);
    p->event_buf[event_idx] = (Event){
            .at_count = at_count,
            .note = *note,
    };

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
        uint64_t next_c = e->at_count;
        if (next_c < p->c) {
            // event "in the past" (process it now)
            next_c = p->c;
        }
        if (next_c < end) {
            // event will need processing
            next_n = next_c - p->c;
        } else {
            // event not needed this call
            next_n = end - p->c;
        }

        if (next_n != 0) {
            // event doesn't need processing yet
            return next_n;
        }

        printf("processing event %lu\n", p->event_pos);

        uint note_buf_idx = (uint)-1;
        // TODO something faster if we're not updating
        // an existing note?
        for (uint i = 0; i < p->note_buf_size; i++) {
            if (p->note_buf[i].id == e->note.id) {
                note_buf_idx = i;
                break;
            }
        }
        if (note_buf_idx == (uint)-1) {
            for (uint i = 0; i < p->note_buf_size; i++) {
                if (p->note_buf[i].state ==
                    NOTE_STATE_OFF) {
                    note_buf_idx = i;
                    break;
                }
            }
        }
        // TODO handle out-of-space
        assert(note_buf_idx != (uint)-1);

        p->note_buf[note_buf_idx] = e->note;

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

    // TODO make this per note?
    NoteInput note_input = (NoteInput){
            .t = p->c,
            .sample_rate = p->sample_rate,
    };

    for (;;) {
        // num samples to calculate until processing next
        // event
        uint64_t next_n = process_events(p, n);

        for (uint i = 0; i < next_n; i++) {
            double r = 0;

            for (uint note_idx = 0;
                 note_idx < p->note_buf_size;
                 note_idx++) {
                switch (p->note_buf[note_idx].state) {
                case NOTE_STATE_OFF:
                    break;

                case NOTE_STATE_ON:
                    r += p->note_buf[note_idx].fn(
                            &note_input,
                            p->note_buf[note_idx].priv);
                    break;
                }
            }

            r *= p->volume;
            for (uint c = 0; c < 2; c++) {
                out[2 * i + c] = (float)r;
            }
            note_input.t++;
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
    uint ebl = 4096;
    uint nbl = 64;
    *p = (StreamPriv){
            .c = 0,
            .sample_rate = sample_rate,
            .volume = 0.1,

            .note_buf = malloc(sizeof(Note) * nbl),
            .note_buf_size = nbl,

            .event_buf = malloc(sizeof(Event) * ebl),
            .event_ready = malloc(sizeof(bool) * ebl),
            .event_buf_size = ebl,
    };

    for (uint i = 0; i < nbl; i++) {
        p->note_buf[i] = (Note){
                .id = 0,
                .state = NOTE_STATE_OFF,
        };
    }

    atomic_store(&p->note_next_id, 1);
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
