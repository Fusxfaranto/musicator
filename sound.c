
#include "sound.h"

#include <assert.h>
#include <math.h>
#include <stdatomic.h>
#include <stdio.h>
#include <unistd.h>

typedef uint_fast32_t uint;

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

typedef struct {
    float pitch;
    uint64_t at_count;

} Event;

typedef struct {
    uint64_t c;
    uint sample_rate;
    float volume;

    Event* event_buf;
    uint event_buf_size;
    atomic_uint_fast32_t event_pos;
    atomic_uint_fast32_t event_ready_pos;
} StreamPriv;

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
    static float instr[] = {
            1.0,
            0.5,
            0.2,
            0.2,
            0.2,
            0.2,
            0.1,
            0.1,
            0.1,
    };

    StreamPriv* p = user;

    float* out = out_s;
    uint64_t end = p->c + n;

    // TODO check that events are actually ready instead of just
    // blasting off into uninitialized memory?
    for (;;) {
        // TODO is atomic_load necessary here?
        uint event_idx = atomic_load(&p->event_pos);
        uint next_event_idx = (event_idx + 1) % p->event_buf_size;

        uint64_t next_c = p->event_buf[next_event_idx].at_count;
        uint64_t next_n = next_c < end ? next_c - p->c : end - p->c;
        float pitch = p->event_buf[event_idx].pitch;

        for (int i = 0; i < next_n; i++) {
            float r = p->volume * overtones(
                                          i + p->c,
                                          pitch,
                                          instr,
                                          ARRAY_LEN(instr),
                                          p->sample_rate);
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
    uint ebl = 4096;
    *p = (StreamPriv){
            .c = 0,
            .sample_rate = sample_rate,
            .volume = 0.5,
            .event_buf = malloc(sizeof(Event) * ebl),
            .event_buf_size = ebl,
    };

    atomic_store(&p->event_pos, 0);

    // TODO
    uint l = 32;
    float pitch = 440;
    for (uint i = 0; i < l; i++) {
        pitch *= SEMITONE;
        p->event_buf[i] = (Event){pitch, (uint64_t)(sample_rate * i)};
    }
    atomic_store(&p->event_ready_pos, l);
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
