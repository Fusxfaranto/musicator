import std.base64 : Base64;
import std.bitmanip : bitfields, bigEndianToNative, nativeToBigEndian;
import std.digest.sha : sha1Of;
import std.regex : matchFirst;
import std.socket : InternetAddress, Socket,
    SocketAcceptException, SocketOption,
    SocketOptionLevel, TcpSocket, wouldHaveBlocked;
import std.stdio : writeln, writefln;

import util;

/+
+-+-+-+-+-------+-+-------------+-------------------------------+
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-------+-+-------------+-------------------------------+
|F|R|R|R| opcode|M| Payload len |    Extended payload length    |
|I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
|N|V|V|V|       |S|             |   (if payload len==126/127)   |
| |1|2|3|       |K|             |                               |
+-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
|     Extended payload length continued, if payload len == 127  |
+ - - - - - - - - - - - - - - - +-------------------------------+
|                               | Masking-key, if MASK set to 1 |
+-------------------------------+-------------------------------+
| Masking-key (continued)       |          Payload Data         |
+-------------------------------- - - - - - - - - - - - - - - - +
:                     Payload Data continued ...                :
+ - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
|                     Payload Data continued ...                |
+---------------------------------------------------------------+
+/

private struct Header {
align(1):
    // dfmt off
    mixin(bitfields!(
              ubyte, "opcode", 4,
              ubyte, "reserved", 3,
              bool, "fin", 1,
              ));
    mixin(bitfields!(
              ubyte, "payload_len_low", 7,
              bool, "mask_on", 1,
              ));
    // dfmt on

    ubyte* len_fields() const pure {
        return cast(ubyte*)(&this) + 2;
    }

    ulong length() const pure {
        switch (payload_len_low) {
        default:
            return payload_len_low;
        case 126:
            return bigEndianToNative!ushort(len_fields[0..2]);
        case 127:
            // TODO
            assert(0);
        }
    }

    ubyte[4] mask() const pure {
        assert(mask_on);
        ubyte* p = cast(ubyte*)(&this) + 2;
        switch (payload_len_low) {
        default:
            return p[0 .. 4];
        case 126:
            return p[2 .. 6];
        case 127:
            // TODO
            assert(0);
        }
    }

    private uint payload_start() const pure {
        uint p = 2;
        if (mask_on) {
            p += 4;
        }
        switch (payload_len_low) {
        default:
            return p;
        case 126:
            return p + 2;
        case 127:
            // TODO
            assert(0);
        }
    }

    ubyte[] header_contents() const pure {
        ubyte* p = cast(ubyte*)(&this);
        return p[0 .. payload_start()];
    }

    ubyte[] payload() const pure {
        ubyte* p = cast(ubyte*)(&this) + payload_start();
        return p[0 .. length()];
    }

    void set_length(ulong l) {
        if (l < 126) {
            payload_len_low = cast(ubyte)(l);
        }
        else if (l <= 0xffff) {
            payload_len_low = 126;
            len_fields[0..2] = nativeToBigEndian(cast(ushort)(l));
        }
        else {
            // TODO
            assert(0);
        }
    }
}

struct WebSocket {
    private Socket server;
    private Socket connection;
    private char[4096] buf;

    this(ushort port) {
        connection = null;
        server = new TcpSocket();
        server.setOption(SocketOptionLevel.SOCKET,
                SocketOption.REUSEADDR, true);
        server.blocking = false;
        server.bind(new InternetAddress(port));
        server.listen(10);
    }

    ~this() {
        server.close();
    }

    private const(char[]) rawRecv() {
        auto n = connection.receive(buf);
        if (n == Socket.ERROR) {
            if (!wouldHaveBlocked()) {
                writeln("websocket error");
            }
            return [];
        }
        return buf[0 .. n];
    }

    const(char[]) recv() {
        if (connection is null) {
            try {
                connection = server.accept();
            }
            catch (SocketAcceptException) {
                return [];
            }

            writeln("websocket connected");

            auto s = rawRecv();
            auto key = Base64.encode(sha1Of(s.matchFirst(
                    r"Sec-WebSocket-Key: (.*)")[1]
                    ~ "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"));

            auto response = "HTTP/1.1 101 Switching Protocols\r\n" ~ "Connection: Upgrade\r\n" ~ "Upgrade: websocket\r\n" ~ "Sec-WebSocket-Accept: " ~ key ~ "\r\n\r\n";

            connection.send(response);

            connection.blocking = false;
        }

        assert(connection.isAlive);
        assert(connection.blocking == false);

        auto s = rawRecv();
        if (s.length == 0) {
            return [];
        }
        else {
            //writeln(dump_mem!(4, "%08b")(cast(ubyte[])(s)));

            assert(s.length >= Header.sizeof);
            Header* h = cast(Header*)(s.ptr);
            assert(cast(void*)(h) == cast(void*)(s.ptr));

            // writeln(h.fin);
            // writeln(h.reserved);
            // writeln(h.opcode);
            // writeln(h.mask_on);
            // writeln(h.payload_len_low);

            // TODO this definitely fires sometimes
            assert(h.fin);

            assert(h.mask_on);
            //ulong len = h.length();
            ubyte[4] mask = h.mask();
            //writeln(dump_mem(mask));
            ubyte[] payload = h.payload();
            //writeln(dump_mem(payload));

            for (uint i; i < payload.length;
                    i++) {
                payload[i] ^= mask[i % 4];
            }

            switch (h.opcode) {
            case 0x01:
                return cast(char[])(payload);

            case 0x08:
                connection.close();
                connection = null;
                writeln("websocket closed");
                return [];

            default:
                writefln("unknown opcode %02X", h.opcode);
                assert(0);
            }
        }
    }

    private void rawSend(const(char[]) s) {
        auto n = connection.send(s);
        if (n == Socket.ERROR) {
            assert(0);
        } else if (n < s.length) {
            assert(0);
        }
    }

    void send(const(char[]) s) {
        Header* h = cast(Header*)(buf.ptr);
        h.fin = true;
        h.reserved = 0;
        h.opcode = 0x01;
        h.mask_on = false;
        h.set_length(s.length);

        // writefln("sending %s", s);

        // writeln(dump_mem(h.header_contents()));
        // writefln("%s %s", h.length(), s.length);

        rawSend(cast(char[])(h.header_contents()));
        rawSend(s);
    }
}
