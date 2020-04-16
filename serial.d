import std.algorithm.iteration : map;
import std.array : array;
import std.conv : to;
import std.exception : enforce;
import std.json : JSONValue, JSONType, JSONException;
import std.traits : EnumMembers, isAggregateType,
    isDynamicArray, hasUDA, FieldNameTuple, isUnsigned;
import std.stdio : writeln;

import util;

enum NoSerial;

JSONValue serialize(T)(auto ref in T t) {
    static if (is(T == enum)) {
        return JSONValue(to!string(t));
    }
    else static if (__traits(compiles, JSONValue(t))) {
        return JSONValue(t);
    }
    else static if (isAggregateType!T) {
        JSONValue[string] sObj;
        static foreach (field_name; FieldNameTuple!T) {
            // pragma(msg, typeof(__traits(getMember, t, field_name)), "   ", __traits(identifier, __traits(getMember, t, field_name)));
            // pragma(msg, hasUDA!(__traits(getMember, t, field_name), NoSerial));
            static if (!hasUDA!(__traits(getMember, t, field_name), NoSerial)) {
                sObj[field_name] = serialize(__traits(getMember, t, field_name));
            }
        }
        return JSONValue(sObj);
    }
    else static if (is(T : U[], U)) {
        return JSONValue(map!serialize(t).array());
    }
    else {
        pragma(msg, T);
        static assert(0);
    }
}

void deserialize(T)(auto ref in JSONValue json, ref T t) {
    //writeln(json, '\t', json.type);
    static if (is(T == U*, U)) {
        static assert(0);
    }
    else static if (is(T == JSONValue)) {
        t = json;
    }
    else static if (is(T == enum)) {
        enforce(json.type() == JSONType.string);
        delegate void() {
            static foreach (e; EnumMembers!T) {
                if (json.str() == e.to!string()) {
                    t = e;
                    return;
                }
            }
            enforce(0);
        }();
    }
    else static if (isAggregateType!T) {
        enforce(json.type() == JSONType.object);
        static foreach (field_name; FieldNameTuple!T) {
            static if (!hasUDA!(__traits(getMember, t, field_name), NoSerial)) {
                if (auto p = field_name in json.object) {
                    deserialize(*p, __traits(getMember, t, field_name));
                }
                else {
                    writeln("member " ~ field_name ~ " of "
                            ~ T.stringof ~ " not deserialized");
                }
            }
        }
    }
    else static if (is(T == bool)) {
        enforce(json.type() == JSONType.true_ || json.type() == JSONType
                .false_);
        t = json.type() == JSONType.true_;
    }
    else static if (__traits(isIntegral, T)) {
        static if (isUnsigned!T) {
            if (json.type() == JSONType.integer) {
                t = to!T(json.integer());
            }
            else {
                t = to!T(json.uinteger());
            }
        }
        else {
            t = to!T(json.integer());
        }
    }
    else static if (__traits(isFloating, T)) {
        if (json.type() == JSONType.integer) {
            t = to!T(json.integer());
        }
        else {
            t = to!T(json.floating());
        }
    }
    else static if (is(T == string)) {
        t = json.str();
    }
    else static if (is(T : U[], U)) {
        static if (isDynamicArray!T) {
            t.length = json.array().length;
        }
        foreach (int i, JSONValue v; json.array()) {
            deserialize(v, t[i]);
        }
    }
    else static if (is(T : V[string], V)) {
        foreach (string k, JSONValue v; json.object()) {
            deserialize(v, t[k]);
        }
    }
    else {
        static assert(0);
    }
}

unittest {
    struct Foo {
        enum Bar {
            A,
            B,
            C,
        }

        string x;
        Bar y1;
        Bar y2;
        int z;
    }

    Foo foo;
    foo.x = "asdf";
    foo.y1 = Foo.Bar.B;
    foo.y2 = Foo.Bar.C;
    foo.z = 42;

    JSONValue j = serialize(foo);
    assert(j.type == JSONType.object);
    assert(j["x"].type == JSONType.string);
    assert(j["x"].str() == "asdf");
    assert(j["y1"].type == JSONType.string);
    assert(j["y1"].str() == "B");
    assert(j["y2"].type == JSONType.string);
    assert(j["y2"].str() == "C");
    assert(j["z"].type == JSONType.integer);
    assert(j["z"].integer() == 42);

    Foo new_foo;
    deserialize(j, new_foo);
    assert(foo == new_foo);
}
