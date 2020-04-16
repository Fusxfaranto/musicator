import std.array : appender;
import std.conv : to;
import std.format : formattedWrite;
import std.meta : AliasSeq;
import std.traits : FieldNameTuple,
    OriginalType, isIntegral;

T make_e(T, S)(S val) {
    T t;
    static foreach (f; FieldNameTuple!T) {
        static if (is(S : typeof(__traits(getMember, t, f)))) {
            __traits(getMember, t, f) = val;
            return t;
        }
    }
}

T reinterpret(T, U)(auto ref U u)
        if (T.sizeof == U.sizeof) {
    return *cast(T*)(&u);
}

T inc_enum(T)(T x)
        if (is(T == enum)
            && is(typeof(cast(OriginalType!T)x + 1) : int)) {
    auto v = cast(OriginalType!T)x + 1;
    if (v > T.max) {
        v = T.min;
    }
    return v.to!T;
}

T combine_shorts(T)(const(ushort[]) a)
        if (is(T == uint)) {
    assert(a.length * 2 == T.sizeof);
    return (a[1] << 16) + a[0];
}

string format_s(A...)(string fmt, A args) {
    auto writer = appender!string();
    writer.formattedWrite(fmt, args);

    return writer.data;
}

string format(A...)(string fmt, A args) {
    auto writer = appender!string();
    writer.formattedWrite(fmt, args);

    if (writer.data.length == 0 || writer.data[$ - 1] != '\0') {
        writer ~= '\0';
    }

    return writer.data;
}

string dump_mem(alias W = 4, alias fmt = "%02X")(ubyte[] mem) {
    auto writer = appender!string();

    foreach (i, m; mem) {
        if (i != 0) {
            auto c = i % W;
            if (c == 0) {
                writer ~= '\n';
            }
            else {
                writer ~= ' ';
                if (c == W / 2) {
                    writer ~= ' ';
                }
            }
        }
        writer.formattedWrite(fmt, m);
    }

    return writer.data;
}

void unsafe_set_length(T)(ref T[] a, size_t n) {
    auto c = a.capacity;
    a.length = n;
    a.assumeSafeAppend();
    if (c >= n) {
        assert(a.capacity == c, c.to!string() ~ " " ~ a.capacity.to!string());
    }
}

void unsafe_reset(T)(ref T[] a) {
    unsafe_set_length(a, 0);
}

void unsafe_popback(T)(ref T[] a) {
    unsafe_set_length(a, a.length - 1);
}

void unsafe_assign(alias init, T)(ref T[] a) {
    a.unsafe_reset();
    static foreach (i, e; init) {
        a[i] = init[i];
    }
}
