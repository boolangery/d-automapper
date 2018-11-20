/**
    Automapper.
*/
module automapper;

import automapper.meta;

/// Base class for creating a custom member mapping.
/// Template Params:
///     BM = The member to map in the destination object
class CustomMemberMapping(string BM)
{
    import std.string : split;

    enum string BMember = BM;
}

/// Compile time
template isCustomMemberMapping(T)
{
    enum bool isCustomMemberMapping = (is(T: CustomMemberMapping!BM, string BM));
}

/// Define ForMember type based an template arguements.
enum ForMemberType
{
    mapMember,  // map a member to another member
    mapDelegate // map a member to a delegate
}

/// Map a member from A to B.
class ForMember(string BM, alias AC) : CustomMemberMapping!(BM)
{
    private alias AT = typeof(AC);

    static assert(is(AT == string) || isCallable!AT, ForMember.stringof ~
        " Action must be a string to map a member to another member or a delegate.");

    static if (is(AT == string))
        enum ForMemberType Type = ForMemberType.mapMember;
    else
        enum ForMemberType Type = ForMemberType.mapDelegate;

    alias Action = AC;
}

template isForMember(T, ForMemberType Type)
{
    static if (is(T == ForMember!(BMember, Action), string BMember, alias Action))
        static if (T.Type == Type)
            enum bool isForMember = true;
        else
            enum bool isForMember = false;
    else
        enum bool isForMember = false;
}

class IgnoreMember(string BM) : CustomMemberMapping!(BM)
{
}

/// A base interface to store templated mapper in a list.
interface IMapper
{

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

    abstract B map(A a);
}

/** Automappler help you create mapper.
Mapper are generated at compile-time.
*/
class AutoMapper
{
    import std.meta : allSatisfy;

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
        import std.conv : castFrom, to;

        if (typeid(A) !in _mappers || typeid(B) !in _mappers[typeid(A)])
            throw new Exception("no mapper found for mapping from " ~ A.stringof ~ " to " ~ B.stringof ~ ". " ~
                "Please setup a mapper using am.createMapper!(" ~ A.stringof ~ ", " ~ B.stringof ~ ", ...);");

        auto m = castFrom!IMapper.to!(BaseMapper!(A, B))(_mappers[typeid(A)][typeid(B)]);
        return m.map(a);
    }

    /// Create a mapper at compile time.
    private template Mapper(A, B, UserMappings...) if (allSatisfy!(isCustomMemberMapping, UserMappings))
    {
        import std.algorithm : canFind;
        import std.typecons;
        import std.typetuple : TypeTuple;

        // get a list of member mapped by user using Mappings...
        private template buildMappedMemberList(Mappings...) {
            static if (Mappings.length > 1) {
                enum string[] buildMappedMemberList = Mappings[0].BMember ~ buildMappedMemberList!(Mappings[1..$]);
            }
            else static if (Mappings.length == 1)
                enum string[] buildMappedMemberList = Mappings[0].BMember ~ buildMappedMemberList!();
            else
                enum string[] buildMappedMemberList = [];
        }

        private template MapperImpl(A, B, Mappings...) {
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

                        // ForMember - mapMember
                        static if (isForMember!(Mapping, ForMemberType.mapMember)) {
                            static assert(hasNestedMember!(A, Mapping.Action), Mapping.Action ~ " is not a member of " ~ A.stringof);

                            static if (is(MemberType!(B, Mapping.BMember) == MemberType!(A, Mapping.Action))) {
                                __traits(getMember, b, Mapping.BMember) = mixin(GetMember!(a, Mapping.Action));
                            }
                            else {
                                __traits(getMember, b, Mapping.BMember) = context.map!(
                                    MemberType!(B, Mapping.BMember),
                                    MemberType!(A, Mapping.Action))(__traits(getMember, a, Mapping.Action));
                            }
                        }
                        // ForMember - mapDelegate
                        else static if (isForMember!(Mapping, ForMemberType.mapDelegate)) {
                            // static assert return type
                            static assert(is(ReturnType!(Mapping.Action) == MemberType!(B, Mapping.BMember)),
                                "the func in " ~ ForMember.stringof ~ " must return a '" ~
                                MemberType!(B, Mapping.BMember).stringof ~ "' like " ~ B.stringof ~
                                "." ~ Mapping.BMember);
                            // static assert parameters
                            static assert(isSame!(Parameters!(Mapping.Action), A),
                                "the func in " ~ ForMember.stringof ~ " must take a value of type '" ~ A.stringof ~"'");

                            __traits(getMember, b, Mapping.BMember) = Mapping.Action(a);
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

        // transform a string like "foo.bar" to "fooBar"
        template flattenedMemberToCamelCase(string M)
        {
            import std.string : split, join, capitalize;

            enum Split = M.split(".");
            private template flattenedMemberToCamelCaseImpl(size_t idx) {
                static if (idx < Split.length) {
                    static if (idx is 0)
                        enum string flattenedMemberToCamelCaseImpl = join([Split[idx], flattenedMemberToCamelCaseImpl!(idx + 1)]); // do not capitalize
                    else
                        enum string flattenedMemberToCamelCaseImpl = join([Split[idx].capitalize, flattenedMemberToCamelCaseImpl!(idx + 1)]);
                }
                else
                    enum string flattenedMemberToCamelCaseImpl = "";
            }

            enum flattenedMemberToCamelCase = flattenedMemberToCamelCaseImpl!0;
        }

        // get un-mapper flattened member present in B (recursive template)
        private template completeUserMapping(Mappings...) {
            template completeUserMappingImpl(size_t idx) {
                static if (idx < FlattenedClassMembers!A.length) {
                    enum M = FlattenedClassMembers!A[idx];

                    // un-mapped by user
                    static if (!userMappedMembers.canFind(M)) {
                        // B has this member ?
                        static if (hasMember!(B, M)) {
                            alias completeUserMappingImpl = TypeTuple!(ForMember!(M, M), completeUserMappingImpl!(idx+1));
                        }
                        // B has this flatenned class member ?
                        else static if (hasMember!(B, flattenedMemberToCamelCase!M)) {
                            alias completeUserMappingImpl = TypeTuple!(ForMember!(flattenedMemberToCamelCase!M, M), completeUserMappingImpl!(idx+1));
                        }
                        else
                            alias completeUserMappingImpl = completeUserMappingImpl!(idx+1);
                    }
                    else
                        alias completeUserMappingImpl = completeUserMappingImpl!(idx+1);
                }
                else
                    alias completeUserMappingImpl = TypeTuple!();

            }

            alias completeUserMapping = TypeTuple!(completeUserMappingImpl!0, Mappings);
        }

        alias Mapper = MapperImpl!(A, B, completeUserMapping!(UserMappings));
    }
}

// auto
unittest
{
    static class Address {
        long zipcode = 74000;
        string city = "unknown";
    }

    static class User {
        Address address = new Address();
        string name = "Eliott";
        string lastName = "Dumeix";
    }

    static class UserDTO {
        string fullName;
        string addressCity;
        long   addressZipcode;
    }

    auto am = new AutoMapper();

    am.createMapper!(User, UserDTO,
        ForMember!("fullName", (User a) => a.name ~ " " ~ a.lastName ));

    auto user = new User();
    UserDTO dto = am.map!UserDTO(user);

    assert(dto.fullName == user.name ~ " " ~ user.lastName);
    assert(dto.addressCity == user.address.city);
    assert(dto.addressZipcode == user.address.zipcode);

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
        ForMember!("mod", (A a) {
            return "modified";
        })
    );


    A a = new A();
    B b = m.map(a);
    assert(b.str == a.str);
    assert(a.foo == a.foo);
    assert(b.mod == "modified");
}
