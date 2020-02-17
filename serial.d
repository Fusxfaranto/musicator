import std.algorithm.iteration : map;
import std.array : array;
import std.conv : to;
import std.exception : enforce;
import std.json : JSONValue, JSONType, JSONException;
import std.traits : isAggregateType, isDynamicArray,
    hasUDA, FieldNameTuple, isUnsigned;
import std.stdio : writeln;

import util;

enum NoSerial;

JSONValue serialize(T)(auto ref in T t) {
    static if (__traits(compiles, JSONValue(t))) {
        return JSONValue(t);
    } else static if (isAggregateType!T) {
        JSONValue[string] sObj;
        static foreach (field_name; FieldNameTuple!T) {
            // pragma(msg, typeof(__traits(getMember, t, field_name)), "   ", __traits(identifier, __traits(getMember, t, field_name)));
            // pragma(msg, hasUDA!(__traits(getMember, t, field_name), NoSerial));
            static if (!hasUDA!(__traits(getMember,
                    t, field_name), NoSerial)) {
                sObj[field_name] = serialize(
                        __traits(getMember, t, field_name));
            }
        }
        return JSONValue(sObj);
    } else static if (is(T : U[], U)) {
        return JSONValue(map!serialize(t).array());
    } else {
        pragma(msg, T);
        static assert(0);
    }
}

void deserialize(T)(auto ref in JSONValue json, ref T t) {
    //writeln(json, '\t', json.type);
    static if (is(T == U*, U)) {
        static assert(0);
    } else static if (is(T == JSONValue)) {
        t = json;
    } else static if (isAggregateType!T) {
        enforce(json.type() == JSONType.object);
        static foreach (field_name; FieldNameTuple!T) {
            static if (!hasUDA!(__traits(getMember,
                    t, field_name), NoSerial)) {
                if (auto p = field_name in json.object) {
                    deserialize(*p, __traits(getMember,
                            t, field_name));
                }
                else {
                    writeln("member " ~ field_name ~ " of "
                            ~ T.stringof
                            ~ " not deserialized");
                }
            }
        }
    } else static if (is(T == bool)) {
        enforce(json.type() == JSONType.true_
                || json.type() == JSONType.false_);
        t = json.type() == JSONType.true_;
    } else static if (__traits(isIntegral, T)) {
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
    } else static if (__traits(isFloating, T)) {
        // if (json.type() == JSONType.integer) {
        //     t = to!T(json.integer());
        // }
        t = to!T(json.floating());
    } else static if (is(T == string)) {
        t = json.str();
    } else static if (is(T : U[], U)) {
        static if (isDynamicArray!T) {
            t.length = json.array().length;
        }
        foreach (int i, JSONValue v; json.array()) {
            deserialize(v, t[i]);
        }
    } else static if (is(T : V[string], V)) {
        foreach (string k, JSONValue v; json.object()) {
            deserialize(v, t[k]);
        }
    } else {
        static assert(0);
    }
}
