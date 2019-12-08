
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
