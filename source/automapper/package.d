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
    enum string BMember = BM;
}

/// Compile time
template isCustomMemberMapping(T)
{
    enum bool isCustomMemberMapping = (is(T: CustomMemberMapping!BM, string BM));
}

/// Map a member from A to B.
class ForMember(string BM, string AM) : CustomMemberMapping!(BM)
{
    enum string AMember = AM;
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

/** Get an alias on the member type.
Params:
    T = the type where the member is
    member = the member to alias */
template MemberType(T, string member)
{
    static if (is(T t == T))
        alias MemberType = typeof(__traits(getMember, t, member));
}

///
unittest
{
    static class A {
        int bar;
        string baz;
    }

    static assert(is(MemberType!(A, "bar") == int));
    static assert(is(MemberType!(A, "baz") == string));
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
            enum bool hasNestedMember = hasNestedMember!(MemberType!(T, memberSplited[0]), memberSplited[1..$].join("."));
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
        A foo;
    }

    static class C {
        B bar;
    }

    static assert(hasNestedMember!(B, "foo.bar"));
    static assert(!hasNestedMember!(B, "foo.baz"));
    static assert(hasNestedMember!(B, "foo"));
    static assert(!hasNestedMember!(B, "fooz"));
    static assert(!hasNestedMember!(C, "bar.foo.baz"));
    static assert(hasNestedMember!(C, "bar.foo.bar"));
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
    template Mapper(A, B, Mappings...) if (allSatisfy!(isCustomMemberMapping, Mappings))
    {
        import std.algorithm : canFind;
        import std.typecons;

        static immutable string[] MembersToIgnore = [
            "toString",     "toHash",   "opCmp",
            "opEquals",     "Monitor",  "factory"
        ];

        template buildMappedMemberList(Mappings...)
        {
            static if (Mappings.length > 1) {
                enum string[] buildMappedMemberList = Mappings[0].BMember ~ buildMappedMemberList!(Mappings[1..$]);
            }
            else static if (Mappings.length == 1)
                enum string[] buildMappedMemberList = Mappings[0].BMember ~ buildMappedMemberList!();
            else
                enum string[] buildMappedMemberList = [];
        }

        // Compile time created mapper
        alias class Mapper : BaseMapper!(A, B) {
            this(AutoMapper context)
            {
                super(context);
            }

            override B map(A a)
            {
                B b = new B();

                static foreach(Mapping; Mappings) {
                    static assert(hasMember!(B, Mapping.BMember), Mapping.BMember ~ " is not a member of " ~ A.stringof);

                    // ForMember
                    static if (isForMember!Mapping) {
                        static assert(hasMember!(A, Mapping.AMember), Mapping.AMember ~ " is not a member of " ~ B.stringof);

                        static if (is(MemberType!(B, Mapping.BMember) == MemberType!(A, Mapping.AMember)))
                            __traits(getMember, b, Mapping.BMember) = __traits(getMember, a, Mapping.AMember);
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

                return b;
            }
        }

        enum string[] mappedMembers = buildMappedMemberList!(Mappings);

        // warn about non mapped members in B
        static foreach(member; [__traits(allMembers, B)]) {
            static if (!isCallable!member && !MembersToIgnore.canFind(member)) {
                static if (!mappedMembers.canFind(member)) {
                    static assert(false, "non mapped member in destination object '" ~ B.stringof ~"." ~ member ~ "'");
                }
            }
        }
    }
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

    /*am.createMapper!(A, B,
        ForMember!("addressZipcode", "address.zipcode"));

    A a = new A();
    B b = am.map!B(a);
    assert(b.addressZipcode == a.address.zipcode);*/
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
