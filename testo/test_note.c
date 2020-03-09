#include "math.h"
#include "sound.h"

enum Bindings {
    LOC_pitch,
    LOC_volume,
    LOC_started_at,
    LOC_released_at,

    GLOB_fm_mod,
    GLOB_fm_freq,
};

double
tone(uint64_t sample_rate, double pitch, uint64_t t) {
    // TODO does this run into precision issues?
    double t_f = (double)(t);
    double period = sample_rate / pitch;
    double half_period = period / 2;
    double t_m = fmod(t_f, period);

#if 0
    return t_m >= half_period ? 1.0 : -1.0;
#elif 1
    double p_t_2_frac = 2 * fmod(t_m, half_period) / half_period - 1;

    return (t_m < half_period ? 1.0 : -1.0) * p_t_2_frac;
#else
    return sin(
            2 * PI * pitch * (t) / (double)(sample_rate));
#endif
}

double note(
        const ValueInput* input,
        const int* local_idxs,
        bool* expire) {
    double pitch = input->values[local_idxs[LOC_pitch]].d;
    double volume = input->values[local_idxs[LOC_volume]].d;
    uint64_t started_at =
            input->values[local_idxs[LOC_started_at]].u;
    uint64_t released_at =
            input->values[local_idxs[LOC_released_at]].u;

    double fm_mod =
            input->values[local_idxs[GLOB_fm_mod]].d;
    double fm_freq =
            input->values[local_idxs[GLOB_fm_freq]].d;

    uint64_t rel_t = input->t - started_at;
    double r = 0;
#if 1
    r += 0.6 * tone(input->sample_rate, pitch, rel_t);
    r += 0.4 * tone(input->sample_rate, 2 * pitch, rel_t);
    r += 0.2 * tone(input->sample_rate, 3 * pitch, rel_t);
    r += 0.1 * tone(input->sample_rate, 4 * pitch, rel_t);
    r += 0.07 * tone(input->sample_rate, 5 * pitch, rel_t);
    r += 0.02 * tone(input->sample_rate, 5 * pitch, rel_t);
#else
    double p_mod = (2 * fm_freq - 1) * 80000. / pitch;
    double p_shift = (2 * fm_mod - 1) * 400000. / pitch;
    double t_mod = p_mod * tone(input->sample_rate, pitch, rel_t);
    r += 0.5 * tone(input->sample_rate, pitch, rel_t + t_mod + p_shift);
#endif

    // TODO try a fancier envelope

    // TODO make params
    const double A = 0.01;
    const double D = 0.08;
    const double S = 0.35;
    const double R = 0.3;

    double t = (input->t - started_at) /
               (double)input->sample_rate;
    if (t <= A) {
        r *= t / A;
    } else if (t <= D + A) {
        r *= ((S - 1) / D) * (t - A) + 1;
    } else {
        if (false) {
            r *= S;
        } else {
            double p = (t - D - A + 1);
            r *= S / (p * p);
        }
    }
    // TODO is this condition bad?
    if (released_at >= started_at) {
        double expire_t = (input->t - released_at) /
                          (double)input->sample_rate;
        double s = -(1 / R) * expire_t + 1;
        if (s <= 0) {
            *expire = true;
            return 0;
        }
        r *= s;
    }

    r *= volume;

    return r;
}
