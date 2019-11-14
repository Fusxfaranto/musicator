
#include "sound.h"

#include <assert.h>
#include <math.h>
#include <stdatomic.h>
#include <stdio.h>
#include <unistd.h>

typedef uint_fast32_t uint;
typedef _Bool bool;

#define false ((bool)0)
#define true ((bool)1)

#define PI 3.14159265358979323846
#define SEMITONE 1.0594630943592952646

#define CHECK(x, v)             \
    {                           \
        int __res;              \
        if ((__res = (x)) != v) \
            return __res;       \
    }
#define CHECK_CUBEB(x) CHECK(x, CUBEB_OK)
#define ARRAY_LEN(a) (sizeof(a) / sizeof(a[0]))

#define ATOMIC_INC_MOD_FUNC(T)                               \
    T atomic_inc_mod_##T(_Atomic(T) * p, T m) {              \
        for (;;) {                                           \
            T expected = atomic_load(p);                     \
            T next = (expected + 1) % m;                     \
            bool cas_succeed = atomic_compare_exchange_weak( \
                    p, &expected, next);                     \
            if (cas_succeed) {                               \
                return expected;                             \
            }                                                \
        }                                                    \
    }                                                        \
    struct __swallow_semicolon_
ATOMIC_INC_MOD_FUNC(uint_fast32_t);
// TODO _Generic?
#define atomic_inc_mod atomic_inc_mod_uint_fast32_t

typedef struct {
    // TODO very temporary
    float* ot_amps;
    uint ot_num;
} Instrument;

typedef enum {
    NOTE_STATE_OFF,
    NOTE_STATE_ON,
} NoteState;

// TODO some part of this needs to be atomic, otherwise this is thread
// unsafe
typedef struct {
    uint id;
    NoteState state;

    // TODO generic params
    float pitch;

    // TODO use an index instead?
    Instrument* instr;
} Note;

typedef struct {
    uint64_t at_count;
    Note note;
} Event;

typedef struct {
    uint64_t c;
    uint sample_rate;
    float volume;

    Note* note_buf;
    uint note_buf_size;
    // TODO if we're only touching this from data_cb, does it need to
    // be atomic?
    atomic_uint_fast32_t note_next_id;

    Event* event_buf;
    atomic_bool* event_ready;
    uint event_buf_size;
    atomic_uint_fast32_t event_pos;
    atomic_uint_fast32_t event_reserved_pos;
} StreamPriv;

// TODO this has no way yet to get the note id back to the caller
void add_event(StreamPriv* p, Event e) {
    uint event_idx =
            atomic_inc_mod(&p->event_reserved_pos, p->event_buf_size);
    p->event_buf[event_idx] = e;

    assert(!atomic_load(&p->event_ready[event_idx]));
    atomic_store(&p->event_ready[event_idx], true);
}

static inline float tone(int t, float freq, uint sample_rate) {
    return sin(2 * PI * t * freq / sample_rate);
}

static inline float overtones(
        int t,
        float freq,
        const float* as,
        int len,
        uint sample_rate) {
    float r = 0;
    for (int i = 0; i < len; i++) {
        r += as[i] * tone(t, freq * (i + 1), sample_rate);
    }
    return r;
}

static long data_cb(
        cubeb_stream* stm,
        void* user,
        const void* in_s,
        void* out_s,
        long n) {
    StreamPriv* p = user;

    float* out = out_s;
    uint64_t end = p->c + n;

    // TODO check that events are actually ready instead of just
    // blasting off into uninitialized memory?
    for (;;) {
        // TODO is atomic_load necessary here?
        uint event_idx = atomic_load(&p->event_pos);
        assert(atomic_load(&p->event_ready[event_idx]));
        uint next_event_idx = (event_idx + 1) % p->event_buf_size;

        Event* e = &p->event_buf[next_event_idx];
        uint64_t next_c = e->at_count;
        uint64_t next_n = next_c < end ? next_c - p->c : end - p->c;

        uint note_buf_idx = (uint)-1;
        if (e->note.id == 0) {
            e->note.id = atomic_fetch_add(&p->note_next_id, 1);
            // TODO handle overflow
            assert(atomic_load(&p->note_next_id) < p->note_buf_size);

            for (uint i = 0; i < p->note_buf_size; i++) {
                if (p->note_buf[i].id == 0) {
                    note_buf_idx = i;
                    break;
                }
            }
            // TODO handle empty buf
            assert(note_buf_idx != (uint)-1);
        } else {
            for (uint i = 0; i < p->note_buf_size; i++) {
                if (p->note_buf[i].id == e->note.id) {
                    note_buf_idx = i;
                    break;
                }
            }
            // TODO error handling
            assert(note_buf_idx != (uint)-1);
        }
        p->note_buf[note_buf_idx] = e->note;

        for (int i = 0; i < next_n; i++) {
            float r = 0;

            for (uint note_idx = 0; note_idx < p->note_buf_size;
                 note_idx++) {
                switch (p->note_buf[note_idx].state) {
                case NOTE_STATE_OFF:
                    break;

                case NOTE_STATE_ON:
                    r += overtones(
                            i + p->c,
                            p->note_buf[note_idx].pitch,
                            p->note_buf[note_idx].instr->ot_amps,
                            p->note_buf[note_idx].instr->ot_num,
                            p->sample_rate);
                    break;
                }
            }

            r *= p->volume;
            for (int c = 0; c < 2; ++c) {
                out[2 * i + c] = r;
            }
        }

        p->c += next_n;
        out += 2 * next_n;

        if (p->c == end) {
            break;
        }
        assert(p->c < end);

        atomic_store(&p->event_ready[event_idx], false);

        // event_pos should only be modified here and nowhere else
        // TODO use an explicit memory order in that case?
        atomic_store(&p->event_pos, next_event_idx);
    }

    p->c = end;
    return n;
}

static void
state_cb(cubeb_stream* stm, void* user, cubeb_state state) {}

static void init_stream_priv(StreamPriv* p, uint sample_rate) {
    static float asdf_ots[] = {
            1.0,
            /* 0.5, */
            /* 0.2, */
            /* 0.2, */
            /* 0.2, */
            /* 0.2, */
            /* 0.1, */
            /* 0.1, */
            /* 0.1, */
    };
    // TODO lol
    static Instrument asdf;
    asdf.ot_amps = asdf_ots;
    asdf.ot_num = ARRAY_LEN(asdf_ots);

    uint ebl = 4096;
    uint nbl = 32;
    *p = (StreamPriv){
            .c = 0,
            .sample_rate = sample_rate,
            .volume = 0.5,

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

    // TODO
    uint l = 16;
    float pitch = 440;
    for (uint i = 0; i < l; i++) {
        pitch *= SEMITONE;
        add_event(
                p,
                (Event){.at_count = (uint64_t)(sample_rate * i),
                        (Note){
                                .id = 0,
                                .state = NOTE_STATE_ON,
                                .pitch = pitch,
                                .instr = &asdf,
                        }});
    }
}

int testo() {
    cubeb* app_ctx;
    cubeb_init(&app_ctx, "musicator", NULL);
    uint32_t rate;
    uint32_t latency_frames;

    cubeb_stream_params output_params = {0};

    CHECK_CUBEB(cubeb_get_preferred_sample_rate(app_ctx, &rate));
    printf("sample rate %u\n", rate);

    output_params.format = CUBEB_SAMPLE_FLOAT32NE;
    output_params.rate = rate;
    output_params.channels = 2;
    output_params.layout = CUBEB_LAYOUT_STEREO;
    output_params.prefs = CUBEB_STREAM_PREF_NONE;

    CHECK_CUBEB(cubeb_get_min_latency(
            app_ctx, &output_params, &latency_frames));
    printf("latency frames %u\n", latency_frames);

    StreamPriv priv;
    init_stream_priv(&priv, rate);

    cubeb_stream* stm;
    CHECK_CUBEB(cubeb_stream_init(
            app_ctx,
            &stm,
            "sound",
            NULL,
            NULL,
            NULL,
            &output_params,
            latency_frames,
            data_cb,
            state_cb,
            &priv));
    CHECK_CUBEB(cubeb_stream_start(stm));

    sleep(5);

    CHECK_CUBEB(cubeb_stream_stop(stm));
    cubeb_stream_destroy(stm);
    cubeb_destroy(app_ctx);

    return 0;
}
