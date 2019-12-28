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

struct TestNoteData {
    int key_code;
    double volume;
}

AudioContext* ctx;
Note[128] key_notes;
TestNoteData[128] key_data;
bool[128] key_held = false;
bool midi_suspend = false;

uint sample_rate;

double tone(ulong t, double freq, ulong sample_rate) {
    return sin(2 * PI * cast(double)(
            t) * freq / cast(double)sample_rate);
}

extern (C) double test_note(const NoteInput* note_input,
        const NoteInputShared* note_input_shared,
        int expire, const void* priv) {
    auto d = cast(TestNoteData*)priv;

    static if (true) {
        enum cents = 100;
        double pitch = 440 * exp2(
                (d.key_code - 69) * (cents / 1200.));
    }
    else static if (false) {
        //enum cents = 77.965;
        enum cents = 63.16;
        double pitch = white_keys_map[i] == -1 ? 0 : 440
            * exp2((white_keys_map[i] - 50) * (cents / 1200));
    }
    else static if (false) {
        enum cents = 63.16;
        //enum cents = 77.965;
        //enum cents = 12.5;

        double base_pitch = 440 * exp2(
                (d.key_code - 69) / 12.);
        int closest_key = 69 + cast(int)(
                round(log2(base_pitch / 440) * 1200. / cents));

        double pitch = 440 * exp2(
                (closest_key - 69) * (cents / 1200.));
    }
    else {
        enum double C = 440 * exp2((72 - 69) / 12.0);
        int rel_note = (d.key_code + (128 * 12) - 72) % 12;
        int octave = (d.key_code - rel_note) / 12;
        double octave_scale = exp2(octave - 6.0);
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
        double pitch = octave_scale * C
            * intervals[rel_note];
    }

    if (pitch == 0) {
        return 0;
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
    enum R = 0.2;

    double t = note_input.t / cast(
            double)note_input_shared.sample_rate;
    if (expire <= EXPIRE_INDEFINITE) {
        if (t <= A) {
            r *= t / A;
        }
        else if (t <= D + A) {
            r *= ((S - 1) / D) * (t - A) + 1;
        }
        else {
            r *= S;
        }
    }
    else {
        r *= max(-(S / R) * t + S, 0);
    }

    return r;
}

void handle_midi_message(const ubyte[] message) {
    if (message.length > 0) {
        ubyte upper = message[0] & 0b11110000;
        assert(upper != 0b10000000);
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
                        key_data[midi_note].volume
                            = midi_velocity / 128.;
                        key_notes[midi_note].expire
                            = EXPIRE_INDEFINITE;
                    }
                    else {
                        // TODO
                        key_notes[midi_note].expire
                            = sample_rate / 2;
                    }
                    add_event(ctx,
                            &key_notes[midi_note], 0);
                }
                break;
            }

        case 0b10110000: {
                assert(message.length == 3);
                ubyte controller = message[1];
                assert(controller < 128);
                ubyte value = message[2];
                assert(value < 128);
                switch (controller) {
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
                                    = sample_rate / 2;
                                add_event(ctx,
                                        &key_notes[i], 0);
                            }
                        }
                    }
                    break;

                default:
                    break;
                }
                break;
            }

        default:
            //writefln("%s", message);
            break;
        }
        writefln("%s", message);
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
        key_data[i] = TestNoteData(i, double.nan);
        key_notes[i] = Note(0, 0,
                &test_note, &key_data[i]);
    }

    enforce(start_audio(&ctx) == 0);
    scope (exit)
        enforce(stop_audio(ctx) == 0);

    sample_rate = cast(uint)get_sample_rate(ctx);

    enum midi_queue_size = 4096;
    RtMidiInPtr midi_p = rtmidi_in_create(
            RtMidiApi.RTMIDI_API_UNSPECIFIED,
            "asdf\0", midi_queue_size);
    scope (exit)
        rtmidi_in_free(midi_p);

    //rtmidi_in_set_callback(midi_p, &midi_callback, null);

    rtmidi_open_port(midi_p, 0, "asdfdsa\0");

    // TODO
    executeShell("aconnect 28:0 128:0");

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
