/**
    Automapper.
*/
module automapper;

public import std.variant;
import std.traits;
import std.meta;
import std.format;
import std.variant;

/// Base class for creating a custom member mapping.
/// Template Params:
///     BM = The member to map in the destination object
class CustomMemberMapping(string BM)
{
    import std.string : split;

    enum string BMember = BM;
    enum string[] BMemberSplit = BM.split(".");
}

/// Compile time
template isCustomMemberMapping(T)
{
    enum bool isCustomMemberMapping = (is(T: CustomMemberMapping!BM, string BM));
}

/// Map a member from A to B.
class ForMember(string BM, string AM) : CustomMemberMapping!(BM)
{
    import std.string : split;

    enum string AMember = AM;
    enum string[] AMemberSplit = AM.split(".");
}

template isForMember(T)
{
    enum bool isForMember = (is(T == ForMember!(BMember, AMember), string BMember, string AMember));
}

class ForMemberFunc(string BM, alias F) : CustomMemberMapping!(BM)
{
    alias Func = F;
}

template isForMemberFunc(T)
{
    enum bool isForMemberFunc = (is(T == ForMemberFunc!(BMember, Func), string BMember, alias Func));
}

class IgnoreMember(string BM) : CustomMemberMapping!(BM)
{
}

interface IMapper
{
    Variant map(Variant value);
}

abstract class BaseMapper(A, B) : IMapper
{
protected:
    AutoMapper context;

public:
    this(AutoMapper ctx)
    {
        context = ctx;
    }

    final override Variant map(Variant value)
    {
        Variant bvar = map(*(value.peek!(A)));
        return bvar;
    }

    abstract B map(A a);
}

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
    T = The class where to list member
    IgnoreList = a list of field to ignore. Default is ["toString",     "toHash",   "opCmp",
        "opEquals",     "Monitor",  "factory"]. */
template ClassMembers(T, string[] IgnoreList = null) if (is(T == class))
{
    import std.algorithm : canFind;

    static immutable string[] MembersToIgnore = [
        "toString",     "toHash",   "opCmp",
        "opEquals",     "Monitor",  "factory"];

    template ClassMembersImpl(size_t idx)
    {
        static if (idx < [__traits(allMembers, T)].length) {
            enum M = __traits(allMembers, T)[idx];
            static if (!isCallable!M && ((IgnoreList is null) ? !MembersToIgnore.canFind(M) : !IgnoreList.canFind(M))
                    && isPublicMember!(T, M))
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
    static class A {
        int bar;
        string foo;
        private int priv;
    }
    static assert(ClassMembers!A == ["bar", "foo"]);
    static assert(ClassMembers!(A, []) != ["bar", "foo"]);
}

/** Get a list of flatenned class member. */
template FlattenedClassMembers(T, string[] IgnoreList = null) if (is(T == class))
{
    import std.string : join;

    template FlattenedClassMembersImpl(U, size_t idx, string prefix)
    {
        static if (idx < ClassMembers!U.length) {
            enum M = ClassMembers!U[idx];
            enum P = (prefix == "" ? "" : prefix ~ "."); // prefix

            // it's a class: recurse
            static if (is(MemberType!(U, M) == class))
                enum string[] FlattenedClassMembersImpl = FlattenedClassMembersImpl!(MemberType!(U, M), 0, P ~ M) ~ FlattenedClassMembersImpl!(U, idx + 1, prefix);
            else
                enum string[] FlattenedClassMembersImpl = P ~ M ~ FlattenedClassMembersImpl!(U, idx + 1, prefix);
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

    static assert(FlattenedClassMembers!C == ["baz.foo.bar", "baz.foo.str", "baz.mid", "top"]);
}


/** Automappler help you create mapper.
Mapper are generated at compile-time.
*/
class AutoMapper
{
    alias MapperByType = IMapper[TypeInfo];
    MapperByType[TypeInfo] _mappers;

    auto createMapper(A, B, Mappings...)()
    {
        auto mapper = new Mapper!(A, B, Mappings)(this);
        _mappers[typeid(A)][typeid(B)] = mapper;
        return mapper;
    }

    B map(B, A)(A a)
    {
        IMapper mapper = null;

        if (typeid(A) in _mappers) {
            if (typeid(B) in _mappers[typeid(A)]) {
                mapper = _mappers[typeid(A)][typeid(B)];
            }
        }

        if (mapper is null)
            throw new Exception("no mapper found for mapping from " ~ A.stringof ~ " to " ~ B.stringof ~ ". " ~
                "Please setup a mapper using am.createMapper!(" ~ A.stringof ~ ", " ~ B.stringof ~ ", ...);");

        Variant avar = a;
        return *(mapper.map(avar).peek!B);
    }

    /// Create a mapper at compile time.
    template Mapper(A, B, UserMappings...) if (allSatisfy!(isCustomMemberMapping, UserMappings))
    {
        import std.algorithm : canFind;
        import std.typecons;
        import std.typetuple : TypeTuple;

        // get a list of member mapped by user using Mappings...
        template buildMappedMemberList(Mappings...) {
            static if (Mappings.length > 1) {
                enum string[] buildMappedMemberList = Mappings[0].BMember ~ buildMappedMemberList!(Mappings[1..$]);
            }
            else static if (Mappings.length == 1)
                enum string[] buildMappedMemberList = Mappings[0].BMember ~ buildMappedMemberList!();
            else
                enum string[] buildMappedMemberList = [];
        }

        template MapperImpl(A, B, Mappings...) {
            // Compile time created mapper
            alias class MapperImpl : BaseMapper!(A, B) {
                this(AutoMapper context)
                {
                    super(context);
                }

                override B map(A a)
                {
                    B b = new B();

                    static foreach(Mapping; Mappings) {
                        static assert(hasMember!(B, Mapping.BMember), Mapping.BMember ~ " is not a member of " ~ B.stringof);

                        // ForMember (works with nested member)
                        static if (isForMember!Mapping) {
                            static assert(hasNestedMember!(A, Mapping.AMember), Mapping.AMember ~ " is not a member of " ~ A.stringof);

                            static if (is(MemberType!(B, Mapping.BMember) == MemberType!(A, Mapping.AMember))) {
                                __traits(getMember, b, Mapping.BMember) = mixin(GetMember!(a, Mapping.AMember));
                            }
                            else {
                                __traits(getMember, b, Mapping.BMember) = context.map!(
                                    MemberType!(B, Mapping.BMember),
                                    MemberType!(A, Mapping.AMember))(__traits(getMember, a, Mapping.AMember));
                            }
                        }
                        // ForMemberFunc
                        else static if (isForMemberFunc!Mapping) {
                            // static assert return type
                            static assert(is(ReturnType!(Mapping.Func) == MemberType!(B, Mapping.BMember)),
                                "the func in " ~ isForMemberFunc.stringof ~ " must return a '" ~
                                MemberType!(B, Mapping.BMember).stringof ~ "' like " ~ B.stringof ~
                                "." ~ Mapping.BMember);
                            // static assert parameters
                            static assert(isSame!(Parameters!(Mapping.Func), A),
                                "the func in " ~ isForMemberFunc.stringof ~ " must take a value of type '" ~ A.stringof ~"'");

                            __traits(getMember, b, Mapping.BMember) = Mapping.Func(a);
                        }
                    }

                    enum string[] mappedMembers = buildMappedMemberList!(Mappings);

                    // warn about un-mapped members in B
                    static foreach(member; ClassMembers!B)
                        static if (!mappedMembers.canFind(member))
                            static assert(false, "non mapped member in destination object '" ~ B.stringof ~"." ~ member ~ "'");

                    return b;
                }
            }
        }

        enum string[] userMappedMembers = buildMappedMemberList!(UserMappings);

        // get un-mapper flattened member present in B (recursive template)
        template getUnMappedMembers() {
            template getUnMappedMembersImpl(size_t idx) {
                static if (idx < FlattenedClassMembers!A.length) {
                    enum M = FlattenedClassMembers!A[idx];

                    // un-mapped by user and B has this member
                    static if (!userMappedMembers.canFind(M) && hasMember!(B, M))
                        enum string[] getUnMappedMembersImpl = M ~ getUnMappedMembersImpl!(idx + 1);
                    else
                        enum string[] getUnMappedMembersImpl = getUnMappedMembersImpl!(idx + 1);
                }
                else
                    enum string[] getUnMappedMembersImpl = [];

            }

            enum string[] getUnMappedMembers = getUnMappedMembersImpl!0;
        }

        // try to auto-map un-mapped member
        template completeUserMapping(Mappings...) {
            enum UM = getUnMappedMembers!();

            template completeUserMappingImpl(size_t idx) {
                static if (idx < UM.length) {
                    enum M = UM[idx];

                    alias completeUserMappingImpl = TypeTuple!(
                        ForMember!(M, M),
                        completeUserMappingImpl!(idx+1));
                }
                else
                    alias completeUserMappingImpl = TypeTuple!();
            }

            alias completeUserMapping = TypeTuple!(completeUserMappingImpl!0, UserMappings);
        }

        alias Mapper = MapperImpl!(A, B, completeUserMapping!(UserMappings));
    }
}

// auto
unittest
{
    static class D {
        int foo = 56;
    }

    static class A {
        string str = "foo";
        int number = 42;
        D data = new D();
    }

    static class B {
        string str;
        int number;
        //int dataFoo;
    }

    auto am = new AutoMapper();

    am.createMapper!(A, B);

    A a = new A();
    B b = am.map!B(a);
    assert(b.str == a.str);
    assert(b.number == a.number);
    //assert(b.dataFoo == a.data.foo);
}

// flatennig
unittest
{
    static class Address {
        int zipcode = 74000;
    }

    static class A {
        Address address = new Address();
    }

    static class B {
        int addressZipcode;
    }

    auto am = new AutoMapper();

    am.createMapper!(A, B,
        ForMember!("addressZipcode", "address.zipcode"));

    A a = new A();
    B b = am.map!B(a);
    assert(b.addressZipcode == a.address.zipcode);
}

// nest
unittest
{
    static class Address {
        int zipcode = 74000;
    }

    static class AddressDTO {
        int zipcode;
    }

    static class A {
        Address address = new Address();
    }

    static class B {
        AddressDTO address;
    }

    auto am = new AutoMapper();

    am.createMapper!(Address, AddressDTO,
        ForMember!("zipcode", "zipcode"));

    am.createMapper!(A, B,
        ForMember!("address", "address"));

    A a = new A();
    B b = am.map!B(a);
    assert(b.address.zipcode == a.address.zipcode);
}

unittest
{
    static class A {
        string str = "foo";
        int foo = 42;
    }

    static class B {
        string str;
        int foo;
        long bar;
        string mod;
    }

    auto am = new AutoMapper();

    auto m = am.createMapper!(A, B,
        ForMember!("str", "str"),
        ForMember!("foo", "foo"),
        IgnoreMember!"bar",
        ForMemberFunc!("mod", (A a) {
            return "modified";
        })
    );


    A a = new A();
    B b = m.map(a);
    assert(b.str == a.str);
    assert(a.foo == a.foo);
    assert(b.mod == "modified");
}
