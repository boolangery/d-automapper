/**
    Meta utils.
*/
module automapper.meta;


package:

import std.traits;
public import std.meta;

/** Get an alias on the member type (work with nested member like "foo.bar").
Params:
    T = the type where the member is
    member = the member to alias */
template MemberType(T, string members)
{
    import std.string : split, join;
    enum string[] memberSplited = members.split(".");

    static if (is(T t == T)) {
        static if (memberSplited.length > 1)
            alias MemberType = MemberType!(MemberType!(T, memberSplited[0]), memberSplited[1..$].join("."));
        else
            alias MemberType = typeof(__traits(getMember, t, members));
    }
}

///
unittest
{
    static class A {
        int bar;
        string baz;
    }

    static class B {
        A foo = new A();
    }

    static assert(is(MemberType!(A, "bar") == int));
    static assert(is(MemberType!(A, "baz") == string));
    static assert(is(MemberType!(B, "foo.bar") == int));
}

/** Test existance of the nested member (or not nested).
Params:
    T = The type where member are nested
    members = the member to test (e.g. "foo.bar.baz") */
template hasNestedMember(T, string members)
{
    import std.string : split, join;
    enum string[] memberSplited = members.split(".");

    static if (is(T t == T)) {
        static if (memberSplited.length > 1)
            static if (__traits(hasMember, T, memberSplited[0]))
                enum bool hasNestedMember = hasNestedMember!(MemberType!(T, memberSplited[0]), memberSplited[1..$].join("."));
            else
                enum bool hasNestedMember = false;
        else
            enum bool hasNestedMember = __traits(hasMember, t, members);
    }
}

///
unittest
{
    static class A {
        int bar;
    }

    static class B {
        A foo = new A();
    }

    static class C {
        B bar = new B();
    }

    static assert(hasNestedMember!(B, "foo.bar"));
    static assert(!hasNestedMember!(B, "data.bar"));
    static assert(!hasNestedMember!(B, "foo.baz"));
    static assert(hasNestedMember!(B, "foo"));
    static assert(!hasNestedMember!(B, "fooz"));
    static assert(!hasNestedMember!(C, "bar.foo.baz"));
    static assert(hasNestedMember!(C, "bar.foo.bar"));
}

template isPublicMember(T, string M)
{
	import std.algorithm, std.typetuple : TypeTuple;

	static if (!__traits(compiles, TypeTuple!(__traits(getMember, T, M)))) enum isPublicMember = false;
	else {
		alias MEM = TypeTuple!(__traits(getMember, T, M));
		static if (__traits(compiles, __traits(getProtection, MEM)))
			enum isPublicMember = __traits(getProtection, MEM).among("public", "export");
		else
			enum isPublicMember = true;
	}
}
///
unittest
{
    static class A {
        public int bar;
        protected string foo;
        private int baz;
    }

    static assert(isPublicMember!(A, "bar"));
    static assert(!isPublicMember!(A, "foo"));
    static assert(!isPublicMember!(A, "baz"));
}

string GetMember(alias T, string member)()
{
    import std.format;
    return (q{%s.%s}.format(T.stringof, member));
}

///
unittest
{
    static class A {
        int bar;
    }

    static class B {
        A foo = new A();
    }

    auto b = new B();

    mixin(GetMember!(b, "foo.bar")) = 42;
}

/** Get a list of all public class member.
Params:
    T = The class where to list member */
template ClassMembers(T) if (is(T == class))
{
    import std.algorithm : canFind;

    enum MembersToIgnore = [__traits(allMembers, Object)];

    private template ClassMembersImpl(size_t idx)
    {
        static if (idx < [__traits(allMembers, T)].length) {
            enum M = __traits(allMembers, T)[idx];
            static if (!isCallable!M && !MembersToIgnore.canFind(M) && isPublicMember!(T, M))
                enum string[] ClassMembersImpl = M ~ ClassMembersImpl!(idx + 1);
            else
                enum string[] ClassMembersImpl = ClassMembersImpl!(idx + 1); // skip
        }
        else {
            enum string[] ClassMembersImpl = [];
        }
    }

    enum string[] ClassMembers = ClassMembersImpl!0;
}


///
unittest
{
    static class Base {
        int baz;
    }

    static class A : Base {
        int bar;
        string foo;
        private int priv;
    }

    static assert(ClassMembers!A == ["bar", "foo", "baz"]);
    static assert(ClassMembers!(A) != ["bar", "foo"]);
}

/** Get a list of flatenned class member. */
template FlattenedClassMembers(T, string[] IgnoreList = null) if (is(T == class))
{
    import std.string : join;

    private template FlattenedClassMembersImpl(U, size_t idx, string Prefix)
    {
        static if (idx < ClassMembers!U.length) {
            enum M = ClassMembers!U[idx];
            enum P = (Prefix == "" ? "" : Prefix ~ "."); // prefix

            // it's a class: recurse
            static if (is(MemberType!(U, M) == class))
                //static if (Prefix == "")
                    enum string[] FlattenedClassMembersImpl = (P ~ M) ~ FlattenedClassMembersImpl!(MemberType!(U, M), 0, P ~ M) ~ FlattenedClassMembersImpl!(U, idx + 1, Prefix);
                //else
                //    enum string[] FlattenedClassMembersImpl = Prefix ~ FlattenedClassMembersImpl!(MemberType!(U, M), 0, P ~ M) ~ FlattenedClassMembersImpl!(U, idx + 1, Prefix);
            else
                enum string[] FlattenedClassMembersImpl = P ~ M ~ FlattenedClassMembersImpl!(U, idx + 1, Prefix);
        }
        else {
            enum string[] FlattenedClassMembersImpl = [];
        }
    }

    enum string[] FlattenedClassMembers = FlattenedClassMembersImpl!(T, 0, "");
}

///
unittest
{
    static class A {
        int bar;
        string str;
        private int dum;
    }

    static class B {
        A foo;
        int mid;
    }

    static class C {
        B baz;
        int top;
    }

    static class Address {
        int zipcode;
    }

    static class D {
        Address address;
    }

    static assert(FlattenedClassMembers!C == ["baz", "baz.foo", "baz.foo.bar", "baz.foo.str", "baz.mid", "top"]);
    static assert(FlattenedClassMembers!D == ["address", "address.zipcode"]);
}

template Alias(alias T)
{
    alias Alias = T;
}

template isClass(T)
{
    enum bool isClass = (is(T == class));
}

string flattenedToCamelCase(string str)
{
    import std.string : split, join, capitalize;
    import std.algorithm : map;

    auto sp = str.split(".");

    if (sp.length > 1)
        return sp[0] ~ sp[1..$].map!capitalize.join();
    else
        return sp.join();
}

unittest
{
    static assert("foo.bar".flattenedToCamelCase() == "fooBar");
    static assert("foo.bar.baz".flattenedToCamelCase() == "fooBarBaz");
    static assert("foo".flattenedToCamelCase() == "foo");
}

string[] splitCamelCase(string str)
{
    import std.ascii : isUpper;
    import std.uni : toLower;

    string[] res;
    string tmp;
    int k = 0;
    foreach(c; str) {
        if (c.isUpper) {
            res ~= tmp;
            tmp = "";
        }
        tmp ~= c.toLower;
        k++;
    }

    foreach(c; str[k..$])
        tmp ~= c.toLower;
    res ~= tmp;

    return res;
}

/// unittest
unittest
{
    static assert("fooBarBaz".splitCamelCase() == ["foo", "bar", "baz"]);
}
