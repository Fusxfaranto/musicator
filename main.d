import std.datetime : dur;
import std.exception : enforce;
import std.math : pow;
import std.process : executeShell;
import std.stdio : writeln, writefln;

import core.stdc.string : strlen;
import core.thread : Thread;

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
            writefln("%s", message);
            break;
        }
    }
    else {
        Thread.sleep(dur!"msecs"(10));
    }
}

void main() {
    enforce(start_audio(&ctx) == 0);
    scope (exit)
        enforce(stop_audio(ctx) == 0);

    static double[] asdf_ots = [
        1.0, 1.0, 0.5, 0.5, 0.4, 0.3,
        0.2, 0.2, 0.1, 0.1, 0.1,
    ];
    // TODO lol
    static Instrument asdf;
    asdf.ot_amps = asdf_ots.ptr;
    asdf.ot_num = asdf_ots.length;

    auto sample_rate = get_sample_rate(ctx);

    for (int i = 0; i < 128; i++) {
        double pitch = 440 * pow(2, (i - 69) / 12.0);
        key_notes[i] = Note(0,
                NoteState.NOTE_STATE_OFF, pitch, &asdf);
    }

    if (false) {
        // TODO
        uint l = 12;
        double pitch = 440;
        for (uint i = 0; i < l; i++) {
            pitch *= SEMITONE;
            Note n = Note(0, NoteState.NOTE_STATE_ON,
                    pitch, &asdf);
            add_event(ctx, &n, sample_rate * (2 * i) / 32);
            n.state = NoteState.NOTE_STATE_OFF;
            add_event(ctx, &n,
                    sample_rate * (2 * i + 1) / 32);
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
