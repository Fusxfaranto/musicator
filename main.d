import std.algorithm : max;
import std.conv : to;
import std.datetime : dur;
import std.exception : enforce;
import std.math : exp2, log2, PI, pow,
    round, fmod, _sin = sin;
import std.process : executeShell;
import std.stdio : writeln, writefln;

import core.stdc.string : strlen;
import core.thread : Thread;

import util;

import c_bindings;

import rtmidi_c;

alias fast_float_type = float;
fast_float_type sin(fast_float_type f) {
    return _sin(f);
}

// extern (C) void midi_callback(double deltatime,
//         const(ubyte)* message,
//         size_t message_size, void* priv) {
//     writefln("%s\t%s", deltatime,
//             message[0 .. message_size]);
// }

enum Tuning {
    ET12,
    ET19,
    JUST,
}

enum TestNoteLocalIdxs {
    pitch,
    volume,
    pitch_offset_19,
    started_at,
    released_at,
}

enum TestGlobals : int {
    VIB_AMT = 1,
    VIB_FREQ,
    VIB_F,
}

__gshared {
    AudioContext* ctx;
    int[128 * (TestNoteLocalIdxs.max + 1)] key_local_idxs;

    bool[128] key_held = false;
    bool[128] key_held_soft = false;
    int last_key_held;
    bool midi_suspend = false;
    Tuning tuning = Tuning.ET19;

    uint sample_rate;
}

int get_key_idx(int keycode) {
    // TODO ???
    return keycode + 100;
}

int get_local_idx(int keycode, TestNoteLocalIdxs local) {
    // TODO ??
    return TestGlobals.max + 1 + keycode * (
            TestNoteLocalIdxs.max + 1) + local;
}

void set_tuning() {
    enum double C = 440 * exp2((72 - 69) / 12.0);

    for (int key_code = 0; key_code < 128;
            key_code++) {
        Event e;
        e.type = EventType.EVENT_WRITE;
        e.target_idx = get_local_idx(key_code,
                TestNoteLocalIdxs.pitch);

        int rel_note = (key_code + (128 * 12) - 72) % 12;
        int octave = (key_code - rel_note) / 12;
        double octave_scale = exp2(octave - 6.0);

        final switch (tuning) {
        case Tuning.ET12: {
                enum cents = 100;
                e.value = 440 * exp2(
                        (key_code - 69) * (cents / 1200.));
                add_event(ctx, 0, &e);
                break;
            }

        case Tuning.ET19: {
                int alt_rel_key;
                switch (rel_note) {
                case 0:
                    alt_rel_key = 0;
                    break;
                case 1:
                    alt_rel_key = 1;
                    break;
                case 2:
                    alt_rel_key = 3;
                    break;
                case 3:
                    alt_rel_key = 5;
                    break;
                case 4:
                    alt_rel_key = 6;
                    break;
                case 5:
                    alt_rel_key = 8;
                    break;
                case 6:
                    alt_rel_key = 9;
                    break;
                case 7:
                    alt_rel_key = 11;
                    break;
                case 8:
                    alt_rel_key = 13;
                    break;
                case 9:
                    alt_rel_key = 14;
                    break;
                case 10:
                    alt_rel_key = 16;
                    break;
                case 11:
                    alt_rel_key = 17;
                    break;

                default:
                    assert(0);
                }

                e.value = octave_scale * C * exp2(
                        alt_rel_key / 19.);
                add_event(ctx, 0, &e);
                break;
            }

        case Tuning.JUST: {
                double[12] intervals;
                if (true) {
                    intervals[0] = 1.0;
                    intervals[1] = 16.0 / 15.0;
                    intervals[2] = 9.0 / 8.0;
                    intervals[3] = 6.0 / 5.0;
                    intervals[4] = 5.0 / 4.0;
                    intervals[5] = 4.0 / 3.0;
                    intervals[6] = 25.0 / 18.0;
                    intervals[7] = 3.0 / 2.0;
                    intervals[8] = 8.0 / 5.0;
                    intervals[9] = 5.0 / 3.0;
                    intervals[10] = 9.0 / 5.0;
                    intervals[11] = 15.0 / 8.0;
                }
                else {
                    intervals[0] = 1.0;
                    intervals[1] = 14.0 / 13.0;
                    intervals[2] = 8.0 / 7.0;
                    intervals[3] = 6.0 / 5.0;
                    intervals[4] = 5.0 / 4.0;
                    intervals[5] = 4.0 / 3.0;
                    intervals[6] = 7.0 / 5.0;
                    intervals[7] = 3.0 / 2.0;
                    intervals[8] = 8.0 / 5.0;
                    intervals[9] = 5.0 / 3.0;
                    intervals[10] = 7.0 / 4.0;
                    intervals[11] = 13.0 / 7.0;

                }
                e.value = octave_scale * C
                    * intervals[rel_note];
                add_event(ctx, 0, &e);

                break;
            }
        }

    }
}

double tone(ulong t, double freq, ulong sample_rate) {
    return sin(2 * PI * cast(double)(
            t) * freq / cast(double)sample_rate);
}

extern (C) double test_note(const ValueInput* input,
        const int* local_idxs, bool* expire) {
    double pitch = input
        .values[local_idxs[TestNoteLocalIdxs.pitch]];
    double pitch_offset_19 = input.values[local_idxs[TestNoteLocalIdxs
            .pitch_offset_19]];
    double volume = input
        .values[local_idxs[TestNoteLocalIdxs.volume]];
    ulong started_at = reinterpret!ulong(input
            .values[local_idxs[TestNoteLocalIdxs.started_at]]);
    ulong released_at = reinterpret!ulong(input
            .values[local_idxs[TestNoteLocalIdxs
                    .released_at]]);

    if (tuning == Tuning.ET19) {
        pitch *= pitch_offset_19;
    }

    static if (true) {
        static __gshared double[] ots = [
            1.0, 1.0, 0.5, 0.6, 0.4, 0.3,
            0.2, 0.2, 0.1, 0.1, 0.1,
        ];
        // static __gshared double[] ots = [
        //     1.0, 0.5, 0.3
        // ];
        double r = 0;
        {
            double s = 0;
            for (uint i = 0; i < ots.length;
                    i++) {
                s += ots[i];
                // TODO figure out a good way to do this that doesn't have issues with float precision
                r += ots[i] * tone(input.t - started_at,
                        pitch * cast(double)(i + 1),
                        input.sample_rate);
            }
            r /= s;
        }
    }
    else static if (true) {
        long period = cast(long)round(
                input.sample_rate / pitch);
        double r = (input.t - started_at) % period >= period / 2 ? 1.0 : -1.0;
    }
    else static if (true) {
        double r = 2 * fmod(pitch * cast(double)(
                note_input_shared.t - d.started_at)
                / note_input_shared.sample_rate, 1.0) - 1.0;

        if (false) {
            r *= tone(note_input_shared.t - d.started_at,
                    pitch, note_input_shared.sample_rate);
        }
    }
    else {
        double r = tone(note_input_shared.t, pitch,
                note_input_shared.sample_rate);
    }

    if (true) {
        double vib = input.values[TestGlobals.VIB_F];
        r *= vib;
    }

    // TODO try a fancier envelope
    enum A = 0.01;
    enum D = 0.08;
    enum S = 0.35;
    enum R = 0.3;

    double t = (input.t - started_at) / cast(double)input
        .sample_rate;
    if (t <= A) {
        r *= t / A;
    }
    else if (t <= D + A) {
        r *= ((S - 1) / D) * (t - A) + 1;
    }
    else {
        if (false) {
            r *= S;
        }
        else {
            r *= S / ((t - D - A + 1) ^^ 2);
        }
    }
    // TODO is this condition bad?
    if (released_at >= started_at) {
        double expire_t = (input.t - released_at) / cast(
                double)input.sample_rate;
        double s = -(1 / R) * expire_t + 1;
        if (s <= 0) {
            *expire = true;
            return 0;
        }
        r *= s;
    }

    // TODO provide built-in sample cache for filters
    static if (false) {
        enum rc = 0.0005;
        r = low_pass_filter(d.last_sample, r, rc,
                note_input_shared.sample_rate);
    }

    r *= volume;

    return r;
}

extern (C) double test_vib_func(const ValueInput* input,
        const int* local_idxs, bool* expire) {
    double amt = input.values[TestGlobals.VIB_AMT];
    double freq = input.values[TestGlobals.VIB_FREQ];
    double v = tone(input.t, freq, input.sample_rate) ^^ 2;
    return amt * v + (1 - amt);
}

void handle_midi_message(const ubyte[] message) {
    if (message.length > 0) {
        ubyte upper = message[0] & 0b11110000;
        //assert(upper != 0b10000000);
        switch (upper) {
        case 0b10010000: {
                assert(message.length == 3);
                ubyte midi_note = message[1];
                assert(midi_note < 128);
                ubyte midi_velocity = message[2];
                assert(midi_velocity < 128);

                key_held[midi_note] = midi_velocity > 0;
                if (!midi_suspend || key_held[midi_note]) {
                    Event e;
                    if (key_held[midi_note]) {
                        e.type = EventType.EVENT_WRITE;
                        e.target_idx = get_local_idx(
                                midi_note,
                                TestNoteLocalIdxs.volume);
                        e.value = midi_velocity / 128.;
                        add_event(ctx, 0, &e);

                        e = Event.init;
                        e.type = EventType.EVENT_WRITE_TIME;
                        e.target_idx = get_local_idx(
                                midi_note,
                                TestNoteLocalIdxs
                                .started_at);
                        add_event(ctx, 0, &e);

                        e = Event.init;
                        e.type = EventType.EVENT_SETTER;
                        e.setter = ValueSetter(&test_note,
                                &key_local_idxs[midi_note * (
                                        TestNoteLocalIdxs.max + 1)],
                                0, get_key_idx(midi_note));
                        add_event(ctx, 0, &e);

                        last_key_held = midi_note;
                    }
                    else {
                        e.type = EventType.EVENT_WRITE_TIME;
                        e.target_idx = get_local_idx(
                                midi_note,
                                TestNoteLocalIdxs
                                .released_at);
                        add_event(ctx, 0, &e);
                    }
                    key_held_soft[midi_note] = key_held[midi_note];
                }
                break;
            }

        case 0b10110000: {
                assert(message.length == 3);
                ubyte controller = message[1];
                assert(controller < 128);
                ubyte value = message[2];
                assert(value < 128);
                double fraction = value / 127.;
                switch (controller) {
                case 1:
                    if (tuning == Tuning.ET19) {
                        int p;
                        if (fraction < 1 / 3.) {
                            p = -1;
                        }
                        else if (fraction < 2 / 3.) {
                            p = 0;
                        }
                        else {
                            p = 1;
                        }
                        Event e;
                        e.type = EventType.EVENT_WRITE;
                        e.value = exp2(p / 19.);
                        for (int k = last_key_held % 12;
                                k < 128; k += 12) {
                            e.target_idx = get_local_idx(k,
                                    TestNoteLocalIdxs
                                    .pitch_offset_19);
                            add_event(ctx, 0, &e);
                        }
                    }
                    break;

                case 20:
                    if (value > 63) {
                        tuning = inc_enum(tuning);
                        set_tuning();
                        writefln("switching to %s", tuning);
                    }
                    break;

                case 21: {
                        Event e;
                        e.type = EventType.EVENT_WRITE;
                        e.value = 1;
                        for (int i = 0; i < 128;
                                i++) {
                            e.target_idx = get_local_idx(i,
                                    TestNoteLocalIdxs
                                    .pitch_offset_19);
                            add_event(ctx, 0, &e);
                        }
                        break;
                    }

                case 24:
                    if (value > 63) {
                        writeln("scrubbing to 1");
                        Event e;
                        e.type = EventType.EVENT_RESET_STREAM;
                        e.to_count = 1;
                        add_event(ctx, 0, &e);
                    }
                    break;

                case 64:
                    midi_suspend = value > 63;
                    writefln("suspend %s", midi_suspend);
                    if (!midi_suspend) {
                        Event e;
                        e.type = EventType.EVENT_WRITE_TIME;
                        for (int i = 0; i < 128;
                                i++) {
                            if (!key_held[i]
                                    && key_held_soft[i]) {
                                e.target_idx = get_local_idx(
                                        i, TestNoteLocalIdxs
                                        .released_at);
                                add_event(ctx, 0, &e);
                                key_held_soft[i] = false;
                            }
                        }
                    }
                    break;

                default:
                    writefln(
                            "unknown controller %s, value %s",
                            controller, value);
                    break;
                }
                break;
            }

        case 0b11100000:
            if (true) {
                ushort value = (message[2] << 7)
                    + message[1];
                double fraction = value / cast(double)(
                        1 << 14);

                writeln(fraction);

                Event e;
                e.type = EventType.EVENT_WRITE;
                e.value = fraction;
                e.target_idx = TestGlobals.VIB_AMT;
                add_event(ctx, 0, &e);
            }
            break;

        default:
            writefln("%b: %s", upper, message);
            break;
        }
        //writefln("%b: %s", upper, message);
    }
    else {
        Thread.sleep(dur!"msecs"(10));
    }
}

void main() {
    int[128] white_keys_map;
    {
        int c = 0;
        for (int i = 0; i < 128; i++) {
            int rel_note = (i + (128 * 12) - 72) % 12;
            if (rel_note != 1 && rel_note != 3
                    && rel_note != 6
                    && rel_note != 8 && rel_note != 10) {
                white_keys_map[i] = c++;
            }
            else {
                white_keys_map[i] = -1;
            }
        }
    }

    for (int i = 0; i < key_local_idxs.length;
            i++) {
        key_local_idxs[i] = get_local_idx(0,
                TestNoteLocalIdxs.min) + i;
    }

    enforce(start_audio(&ctx) == 0);
    scope (exit)
        enforce(stop_audio(ctx) == 0);

    sample_rate = cast(uint)get_sample_rate(ctx);

    {
        Event e;
        e.type = EventType.EVENT_WRITE;

        for (int key_code = 0; key_code < 128;
                key_code++) {
            e.target_idx = get_local_idx(key_code,
                    TestNoteLocalIdxs.pitch_offset_19);
            e.value = 1;
            add_event(ctx, 0, &e);

            e.target_idx = get_local_idx(key_code,
                    TestNoteLocalIdxs.released_at);
            e.value = reinterpret!double(0uL);
            add_event(ctx, 0, &e);
        }
        set_tuning();
    }

    {
        Event e;
        e.type = EventType.EVENT_WRITE;
        e.value = 0;
        e.target_idx = TestGlobals.VIB_AMT;
        add_event(ctx, 0, &e);

        e = Event.init;
        e.type = EventType.EVENT_WRITE;
        e.value = 2 * PI * 0.7;
        e.target_idx = TestGlobals.VIB_FREQ;
        add_event(ctx, 0, &e);

        e = Event.init;
        e.type = EventType.EVENT_SETTER;
        e.setter = ValueSetter(&test_vib_func, null,
                TestGlobals.VIB_F, TestGlobals.VIB_F);
        add_event(ctx, 0, &e);
    }

    enum midi_queue_size = 4096;
    RtMidiInPtr midi_p = rtmidi_in_create(
            RtMidiApi.RTMIDI_API_UNSPECIFIED,
            "asdf\0", midi_queue_size);
    scope (exit)
        rtmidi_in_free(midi_p);

    //rtmidi_in_set_callback(midi_p, &midi_callback, null);

    rtmidi_open_port(midi_p, 0, "asdfdsa\0");

    // TODO
    executeShell("aconnect 24:0 128:0");
    executeShell("aconnect 28:0 128:0");
    executeShell("aconnect 32:0 128:0");

    ubyte[1024] message_buf = cast(ubyte)(-1);
    for (;;) {
        size_t message_size = message_buf.length;
        double t = rtmidi_in_get_message(midi_p,
                message_buf.ptr, &message_size);

        assert(midi_p.ok,
                midi_p.msg[0 .. strlen(midi_p.msg)]);

        handle_midi_message(message_buf[0 .. message_size]);
    }
}
