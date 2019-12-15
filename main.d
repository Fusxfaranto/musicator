import std.datetime : dur;
import std.exception : enforce;
import std.math : exp2, log2, PI, pow, round;
import std.process : executeShell;
import std.stdio : writeln, writefln;

import core.stdc.string : strlen;
import core.thread : Thread;

import util;

import c_bindings;

import rtmidi_c;

// extern (C) void midi_callback(double deltatime,
//         const(ubyte)* message,
//         size_t message_size, void* priv) {
//     writefln("%s\t%s", deltatime,
//             message[0 .. message_size]);
// }

AudioContext* ctx;
Note[128] key_notes;
BCItem[][128] key_progs;
bool[128] key_held = false;
bool midi_suspend = false;

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
                        // TODO awful, also probably super racy
                        key_progs[midi_note][1] = make_e!BCItem(
                                midi_velocity / 128.);
                        key_notes[midi_note].state
                            = NoteState.NOTE_STATE_ON;
                    }
                    else {
                        key_notes[midi_note].state
                            = NoteState.NOTE_STATE_OFF;
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
                                    && key_notes[i].state
                                    == NoteState
                                    .NOTE_STATE_ON) {
                                key_notes[i].state
                                    = NoteState
                                    .NOTE_STATE_OFF;
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

    enforce(start_audio(&ctx) == 0);
    scope (exit)
        enforce(stop_audio(ctx) == 0);

    auto sample_rate = get_sample_rate(ctx);

    auto silent_prog = reinterpret!BCProg(
            [
            make_e!BCItem(BCOp.BCOP_PUSH_FLT),
            make_e!BCItem(1.0),
            make_e!BCItem(BCOp.BCOP_PUSH_FLT),
            make_e!BCItem(0.0),
            make_e!BCItem(BCOp.BCOP_MUL),
            ]);

    auto note_prog = reinterpret!BCProg(
            [
            make_e!BCItem(BCOp.BCOP_PUSH_FLT),
            make_e!BCItem(2 * PI),
            make_e!BCItem(BCOp.BCOP_PUSH_T),
            make_e!BCItem(BCOp.BCOP_MUL),
            make_e!BCItem(BCOp.BCOP_MUL),
            make_e!BCItem(BCOp.BCOP_SIN),
            ]);

    BCProg ot_prog = void;
    {
        static double[] asdf_ots = [
            1.0, 1.0, 0.5, 0.5, 0.4, 0.3,
            0.2, 0.2, 0.1, 0.1, 0.1,
        ];

        BCItem[] ot_prog_a;

        double tot = 0;
        foreach (i, a; asdf_ots) {
            tot += a;
            ot_prog_a ~= [
                make_e!BCItem(BCOp.BCOP_COPY),
                make_e!BCItem(BCOp.BCOP_PUSH_FLT),
                make_e!BCItem(i + 1.0),
                make_e!BCItem(BCOp.BCOP_MUL),
                make_e!BCItem(BCOp.BCOP_CALL),
                make_e!BCItem(&note_prog),
                make_e!BCItem(BCOp.BCOP_PUSH_FLT),
                make_e!BCItem(a),
                make_e!BCItem(BCOp.BCOP_MUL),
                make_e!BCItem(BCOp.BCOP_SWAP),
            ];
        }

        ot_prog_a ~= make_e!BCItem(BCOp.BCOP_POP);

        for (int i = 0; i < asdf_ots.length - 1;
                i++) {
            ot_prog_a ~= make_e!BCItem(BCOp.BCOP_ADD);
        }

        ot_prog_a ~= [
            make_e!BCItem(BCOp.BCOP_PUSH_FLT),
            make_e!BCItem(1 / tot),
            make_e!BCItem(BCOp.BCOP_MUL),
        ];

        ot_prog = reinterpret!BCProg(ot_prog_a);
    }

    for (int i = 0; i < 128; i++) {
        static if (false) {
            enum cents = 100;
            double pitch = 440 * pow(2,
                    (i - 69) * (cents / 1200.));
        }
        else static if (false) {
            //enum cents = 77.965;
            enum cents = 63.16;
            double pitch = white_keys_map[i] == -1 ? 0
                : 440 * pow(2,
                        (white_keys_map[i] - 50) * (
                            cents / 1200));
        }
        else static if (true) {
            enum cents = 63.16;
            //enum cents = 77.965;
            //enum cents = 12.5;

            double base_pitch = 440 * exp2((i - 69) / 12.);
            int closest_key = 69 + cast(int)(
                    round(log2(base_pitch / 440) * 1200. / cents));

            double pitch = 440 * exp2(
                    (closest_key - 69) * (cents / 1200.));
        }
        else {
            enum double C = 440 * pow(2, (72 - 69) / 12.0);
            int rel_note = (i + (128 * 12) - 72) % 12;
            int octave = (i - rel_note) / 12;
            double octave_scale = pow(2, octave - 6.0);
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
            double pitch = octave_scale
                * C * intervals[rel_note];
        }

        key_progs[i] = [
            make_e!BCItem(BCOp.BCOP_PUSH_FLT),
            make_e!BCItem(1.0),
            make_e!BCItem(BCOp.BCOP_PUSH_FLT),
            make_e!BCItem(pitch),
            make_e!BCItem(BCOp.BCOP_CALL),
            make_e!BCItem(&ot_prog),
            make_e!BCItem(BCOp.BCOP_MUL),
        ];

        if (pitch != 0) {
            key_notes[i] = Note(0,
                    NoteState.NOTE_STATE_OFF,
                    reinterpret!BCProg(key_progs[i]));
        }
        else {
            key_notes[i] = Note(0,
                    NoteState.NOTE_STATE_OFF, silent_prog);
        }
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
