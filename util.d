
import std.meta : AliasSeq;
import std.traits : FieldNameTuple;



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
