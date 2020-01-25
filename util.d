
import std.conv : to;
import std.meta : AliasSeq;
import std.traits : FieldNameTuple, OriginalType, isIntegral;



T make_e(T, S)(S val) {
    T t;
    static foreach (f; FieldNameTuple!T) {
        static if (is(S : typeof(__traits(getMember, t, f)))) {
            __traits(getMember, t, f) = val;
            return t;
        }
    }
}

T reinterpret(T, U)(auto ref U u) if (T.sizeof == U.sizeof) {
    return *cast(T*)(&u);
}


T inc_enum(T)(T x) if (is(T == enum) && is(typeof(cast(OriginalType!T)x + 1) : int))
{
    auto v = cast(OriginalType!T)x + 1;
    if (v > T.max)
    {
        v = T.min;
    }
    return v.to!T;
}


string format(A...)(string fmt, A args)
{
    import std.array : appender;
    import std.format : formattedWrite;

    auto writer = appender!string();
    writer.formattedWrite(fmt, args);

    if (writer.data.length == 0 || writer.data[$ - 1] != '\0') {
        writer ~= '\0';
    }

    return writer.data;
}
