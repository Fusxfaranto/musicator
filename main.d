import std.datetime : dur;
import std.exception : enforce;
import std.stdio : writeln, writefln;

import core.thread : Thread;

import c_bindings;

void main() {
    AudioContext* ctx;
    enforce(start_audio(&ctx) == 0);

    static double[] asdf_ots = [
        1.0,
        /* 0.5, */
        /* 0.2, */
        /* 0.2, */
        /* 0.2, */
        /* 0.2, */
        /* 0.1, */
        /* 0.1, */
        /* 0.1, */
    ];
    // TODO lol
    static Instrument asdf;
    asdf.ot_amps = asdf_ots.ptr;
    asdf.ot_num = asdf_ots.length;

    auto sample_rate = get_sample_rate(ctx);

    // TODO
    uint l = 128;
    double pitch = 440;
    for (uint i = 0; i < l; i++) {
        pitch *= SEMITONE;
        Note n = Note(0, NoteState.NOTE_STATE_ON,
                pitch, &asdf);
        add_event(ctx, &n, sample_rate * (2 * i) / 32);
        n.state = NoteState.NOTE_STATE_OFF;
        add_event(ctx, &n, sample_rate * (2 * i + 1) / 32);
    }

    Thread.sleep(dur!"msecs"(30 * 1000));

    enforce(stop_audio(ctx) == 0);
}
