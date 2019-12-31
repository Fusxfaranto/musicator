import std.algorithm : max;
import std.datetime : dur;
import std.exception : enforce;
import std.math : exp2, log2, PI, pow, round, _sin = sin;
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

struct TestNoteDataShared {
    int key_offset;
}

struct TestNoteData {
    int t;
    int expire_t;

    double pitch;
    double volume;
    double pitch_offset_19;
    double last_sample;
    TestNoteDataShared* shared_data;
}

__gshared {
    TestNoteDataShared shared_data;

    AudioContext* ctx;
    Note[128] key_notes;
    TestNoteData[128] key_data;
    bool[128] key_held = false;
    int last_key_held;
    bool midi_suspend = false;
    Tuning tuning = Tuning.ET19;

    uint sample_rate;
}

void set_tuning() {
    enum double C = 440 * exp2((72 - 69) / 12.0);

    for (int key_code = 0; key_code < 128;
            key_code++) {

        int rel_note = (key_code + (128 * 12) - 72) % 12;
        int octave = (key_code - rel_note) / 12;
        double octave_scale = exp2(octave - 6.0);

        final switch (tuning) {
        case Tuning.ET12: {
                enum cents = 100;
                event_write_safe(ctx, 0, 440 * exp2(
                        (key_code - 69) * (cents / 1200.)),
                        &key_data[key_code].pitch);
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

                event_write_safe(ctx, 0,
                        octave_scale * C * exp2(
                            alt_rel_key / 19.),
                        &key_data[key_code].pitch);
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
                event_write_safe(ctx, 0,
                        octave_scale * C * intervals[rel_note],
                        &key_data[key_code].pitch);

                break;
            }
        }

    }
}

double tone(ulong t, double freq, ulong sample_rate) {
    return sin(2 * PI * cast(double)(
            t) * freq / cast(double)sample_rate);
}

extern (C) double test_note(const NoteInput* note_input,
        const NoteInputShared* note_input_shared,
        int expire, void* priv) {
    auto d = cast(TestNoteData*)priv;

    auto pitch = d.pitch;
    if (tuning == Tuning.ET19) {
        pitch *= d.pitch_offset_19;
    }

    static if (true) {
        static __gshared double[] ots = [
            1.0, 1.0, 0.5, 0.6, 0.4, 0.3,
            0.2, 0.2, 0.1, 0.1, 0.1,
        ];
        // static __gshared double[] ots = [
        //     1.0, 0.5, 0.3
        // ];

        double s = 0;
        double r = 0;
        for (uint i = 0; i < ots.length; i++) {
            s += ots[i];
            r += ots[i] * tone(note_input_shared.t,
                    pitch * cast(double)(i + 1),
                    note_input_shared.sample_rate);
        }
        r /= s;
    }
    else {
        double r = tone(note_input_shared.t, pitch,
                note_input_shared.sample_rate);
    }

    // TODO try a fancier envelope
    enum A = 0.01;
    enum D = 0.08;
    enum S = 0.35;
    enum R = 0.3;

    double t = d.t / cast(
            double)note_input_shared.sample_rate;
    if (t <= A) {
        r *= t / A;
    }
    else if (t <= D + A) {
        r *= ((S - 1) / D) * (t - A) + 1;
    }
    else {
        if (false) {
            r *= S;
        } else {
            r *= S / ((t - D - A + 1) ^^ 2);
        }
    }
    if (expire > EXPIRE_INDEFINITE) {
        double expire_t = d.expire_t / cast(
            double)note_input_shared.sample_rate;
        r *= max(-(1 / R) * expire_t + 1, 0);
        d.expire_t++;
    }

    if (true) {
        enum rc = 0.0002;
        r = low_pass_filter(d.last_sample, r, rc,
                note_input_shared.sample_rate);
    }

    d.last_sample = r;
    d.t++;

    return r;
}

void event_write_safe(T, S)(AudioContext* ctx,
        ulong at_count, auto ref S source, T* target)
        if (is(S : T)) {
    T t = source;
    event_write(ctx, at_count, &t, t.sizeof, target);
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
                    if (key_held[midi_note]) {
                        event_write_safe(ctx, 0,
                                midi_velocity / 128.,
                                &key_data[midi_note].volume);
                        event_write_safe(ctx, 0, 0,
                                &key_data[midi_note].t);

                        key_notes[midi_note].expire
                            = EXPIRE_INDEFINITE;

                        last_key_held = midi_note;
                    }
                    else {
                        event_write_safe(ctx, 0, 0,
                                &key_data[midi_note].expire_t);

                        // TODO figure out a way to do this that doesn't require hardcoding an expiry time
                        key_notes[midi_note].expire
                            = sample_rate;
                    }
                    event_note(ctx, 0,
                            &key_notes[midi_note]);
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
                        for (int k = last_key_held % 12;
                                k < 128; k += 12) {
                            event_write_safe(ctx, 0,
                                    exp2(p / 19.), &key_data[k]
                                    .pitch_offset_19);
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

                case 21:
                    for (int i = 0; i < 128;
                            i++) {
                        event_write_safe(ctx, 0, 1,
                                &key_data[i]
                                .pitch_offset_19);
                    }
                    break;

                case 64:
                    midi_suspend = value > 63;
                    writefln("suspend %s", midi_suspend);
                    if (!midi_suspend) {
                        for (int i = 0; i < 128;
                                i++) {
                            if (!key_held[i]
                                    && key_notes[i].expire
                                    <= EXPIRE_INDEFINITE) {
                                key_notes[i].expire
                                    = sample_rate;
                                event_note(ctx, 0,
                                        &key_notes[i]);
                            }
                        }
                    }
                    break;

                default:
                    break;
                }
                break;
            }

        case 0b11100000:
            if (false) {
                ushort value = (message[2] << 7)
                    + message[1];
                double fraction = value / cast(double)(
                        1 << 14);
                if (fraction > 0.55) {
                    shared_data.key_offset = 1;
                }
                else if (fraction > 0.45) {
                    shared_data.key_offset = 0;
                }
                else {
                    shared_data.key_offset = -1;
                }
                writeln(fraction);
            }
            break;

        default:
            //writefln("%s", message);
            break;
        }
        writefln("%b: %s", upper, message);
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

    for (int i = 0; i < 128; i++) {
        key_data[i] = TestNoteData.init;
        key_data[i].pitch_offset_19 = 1;
        key_data[i].last_sample = 0;
        key_data[i].shared_data = &shared_data;
        key_notes[i] = Note(0, 0,
                &test_note, &key_data[i]);
    }

    enforce(start_audio(&ctx) == 0);
    scope (exit)
        enforce(stop_audio(ctx) == 0);

    sample_rate = cast(uint)get_sample_rate(ctx);

    set_tuning();

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
