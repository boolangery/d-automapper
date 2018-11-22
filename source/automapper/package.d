/**
    Automapper.
*/
module automapper;

import automapper.meta;

class CustomMapping
{

}

/// Compile time
template isCustomMapping(T)
{
    enum bool isCustomMapping = (is(T: CustomMapping));
}

class Reverse : CustomMapping
{

}

/// Base class for creating a custom member mapping.
/// Template Params:
///     BM = The member to map in the destination object
class CustomMemberMapping(string BM) : CustomMapping
{
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

abstract class BaseMapper(A, B, AM)
{
protected:
    AM context;

public:
    this(AM ctx)
    {
        context = ctx;
    }

    abstract B map(A a);
}

// get a list of member mapped by user using Mappings...
private template buildMappedMemberList(Mappings...) if (allSatisfy!(isCustomMapping, Mappings))
{
    import std.string : split;

    private template buildMappedMemberListImpl(size_t idx) {
        static if (idx < Mappings.length)
            static if (isCustomMemberMapping!(Mappings[idx]))
                enum string[] buildMappedMemberListImpl = Mappings[idx].BMember ~ Mappings[idx].BMember.split(".") ~ buildMappedMemberListImpl!(idx + 1);
            else
                enum string[] buildMappedMemberListImpl = buildMappedMemberListImpl!(idx + 1); // skip
        else
            enum string[] buildMappedMemberListImpl = [];
    }

    enum string[] buildMappedMemberList = buildMappedMemberListImpl!0;
}

// Returns true if the mapper needs to be reversed (Mappings containts Reverse).
private template reverseNeeded(Mapper) if (isMapperDefinition!Mapper)
{
    private template reverseNeededImpl(size_t idx) {
        static if (idx < Mapper.Mappings.length) {
            static if (is(Mapper.Mappings[idx] : Reverse))
                enum bool reverseNeededImpl = true;
            else
                enum bool reverseNeededImpl = reverseNeededImpl!(idx + 1);
        }
        else
            enum bool reverseNeededImpl = false;
    }

    enum bool reverseNeeded = reverseNeededImpl!0;
}

enum MapperType
{
    classStruct,
    typeConverter
}

/// A mapper definition for class and struct.
class Mapper(F, T, M...) if (isClassOrStruct!F && isClassOrStruct!T && allSatisfy!(isCustomMapping, M))
{
    alias A = F;
    alias B = T;
    alias Mappings = AliasSeq!M;
    enum Type = MapperType.classStruct;
}

/// Type mapper.
class Mapper(F, T, alias M) if (isDelegateWithRtParam!(M, F, T))
{
    alias A = F;
    alias B = T;
    alias Mappings = M;
    enum Type = MapperType.typeConverter;
}

/// Is the provided template a Mapper ?
template isMapperDefinition(T)
{
    enum bool isMapperDefinition = (is(T: Mapper!(A, B), A, B) || is(T: Mapper!(AB, BB, MB), AB, BB, MB) ||
        is(T: Mapper!(A, B, M), A, B, alias M));
}

unittest
{
    class A {}
    class B {}
    struct C {}

    static assert(isMapperDefinition!(Mapper!(A, B)));
    static assert(isMapperDefinition!(Mapper!(long, int, (long l) => 42)));
    static assert(isMapperDefinition!(Mapper!(long, C, (long l) => C())));
}

/** Complete user mappings.
    * map member with the same name
    * map flattened member to destination object
      e.g: A.foo.bar is mapped to B.fooBar */
private template completeUserMapping(A, B, Mappings...) if (allSatisfy!(isCustomMapping, Mappings))
{
    import std.algorithm : canFind;
    import std.string : join;

    enum MappedMembers = buildMappedMemberList!(Mappings);

    private template completeUserMappingImpl(size_t idx) {
        static if (idx < FlattenedMembers!A.length) {
            enum M = FlattenedMembers!A[idx];

            // un-mapped by user
            static if (!MappedMembers.canFind(M)) {
                // B has this member: B.foo = A.foo
                static if (hasMember!(B, M)) {
                    alias completeUserMappingImpl = AliasSeq!(ForMember!(M, M),
                        completeUserMappingImpl!(idx+1));
                }
                // B has this flatenned class member: B.fooBar = A.foo.bar
                else static if (hasMember!(B, M.flattenedToCamelCase())) {
                    alias completeUserMappingImpl = AliasSeq!(ForMember!(M.flattenedToCamelCase, M),
                        completeUserMappingImpl!(idx+1));
                }
                else
                    alias completeUserMappingImpl = completeUserMappingImpl!(idx+1);
            }
            else
                alias completeUserMappingImpl = completeUserMappingImpl!(idx+1);
        }
        else
            alias completeUserMappingImpl = AliasSeq!();
    }

    alias completeUserMapping = AliasSeq!(completeUserMappingImpl!0, Mappings);
}

/** It take a list of Mapper, and return a new list of reversed mapper if needed.
e.g. for Mapper!(A, B, ForMember("foo", "bar")), it create Mapper!(B, A, ForMember("bar", "foo") */
private template generateReversedMapper(Mappers...) if (allSatisfy!(isMapperDefinition, Mappers))
{
    private template generateReversedMapperImpl(size_t idx) {
        static if (idx < Mappers.length) {
            alias M = Mappers[idx];

            private template reverseMapping(size_t midx) {
                static if (midx < M.Mappings.length) {
                    alias MP = M.Mappings[midx];

                    static if (isForMember!(MP, ForMemberType.mapMember)) {
                        alias reverseMapping = AliasSeq!(ForMember!(MP.Action, MP.BMember), reverseMapping!(midx + 1));
                    }
                    else static if (isForMember!(MP, ForMemberType.mapDelegate)) {
                        static assert(false, "Cannot reverse mapping '" ~ M.A.stringof ~ " -> " ~ M.B.stringof ~
                            "' because it use a custom user delegate: " ~ MP.stringof);
                    }
                    else
                        alias reverseMapping = reverseMapping!(midx + 1); // continue
                }
                else
                    alias reverseMapping = AliasSeq!();
            }

            static if (reverseNeeded!M) // reverse it if needed
                alias generateReversedMapperImpl = AliasSeq!(Mapper!(M.B, M.A, completeUserMapping!(M.B, M.A, reverseMapping!0)),
                    generateReversedMapperImpl!(idx + 1));
            else
                alias generateReversedMapperImpl = generateReversedMapperImpl!(idx + 1); // continue
        }
        else
            alias generateReversedMapperImpl = AliasSeq!();
    }

    alias generateReversedMapper = generateReversedMapperImpl!0;
}

/** Complete user defined Mappers with automatic member mapping.
    Params:
        Mappers = list of Mapper */
private template completeMappers(Mappers...) if (allSatisfy!(isMapperDefinition, Mappers))
{
    private template completeMappersImpl(size_t idx) {
        static if (idx < Mappers.length) {
            alias M = Mappers[idx];
            alias completeMappersImpl = AliasSeq!(Mapper!(M.A, M.B, completeUserMapping!(M.A, M.B, M.Mappings)),
                completeMappersImpl!(idx + 1));
        }
        else
            alias completeMappersImpl = AliasSeq!();
    }

    alias completeMappers = completeMappersImpl!0;
}

/// From a list of Mapper, get a new list of Mapper.Type matching provided Type.
private template getMappersByType(MapperType Type, Mappers...) if (allSatisfy!(isMapperDefinition, Mappers))
{
    private template getMappersByTypeImpl(size_t idx) {
        static if (idx < Mappers.length) {
            static if (Mappers[idx].Type is Type)
                alias getMappersByTypeImpl = AliasSeq!(Mappers[idx], getMappersByTypeImpl!(idx + 1));
            else
                alias getMappersByTypeImpl = getMappersByTypeImpl!(idx + 1);
        }
        else
            alias getMappersByTypeImpl = AliasSeq!();
    }

    alias getMappersByType = getMappersByTypeImpl!0;
}

/** Compile time class mapping. */
class AutoMapper(Mappers...)
{
    import std.algorithm : canFind;

    static assert(allSatisfy!(isMapperDefinition, Mappers), "Invalid template arguements.");

    // sort mapper by type
    alias ClassStructMappers = getMappersByType!(MapperType.classStruct, Mappers);
    alias TypesConverters    = getMappersByType!(MapperType.typeConverter, Mappers);

    alias CompletedMappers = completeMappers!(ClassStructMappers); // complete user mapping
    // Generate reversed mapper and complete them too
    alias FullMappers = AliasSeq!(CompletedMappers, completeMappers!(generateReversedMapper!CompletedMappers));

    // debug pragma(msg, "FullMappers: " ~ FullMappers.stringof);

    /// Find the right mapper in the FullMappers.
    private template getMapperDefinition(A, B)
    {
        private template getMapperDefinitionImpl(size_t idx) {
            static if (idx < FullMappers.length) {
                alias M = FullMappers[idx];
                static if (is(M : Mapper!(A, B))) // Mapper without mapping
                    alias getMapperDefinitionImpl = M;
                else static if (is(M : Mapper!(A, B, T), T)) // Mapper with mapping
                    alias getMapperDefinitionImpl = M;
                else
                    alias getMapperDefinitionImpl = getMapperDefinitionImpl!(idx + 1); // continue searching
            }
            else
                alias getMapperDefinitionImpl = void; // not found
        }

        alias getMapperDefinition = getMapperDefinitionImpl!0;
    }

    /// Find the type converter in the TypesConverters.
    private template getTypeConverter(A, B)
    {
        private template getTypeConverterImpl(size_t idx) {
            static if (idx < TypesConverters.length) {
                alias M = TypesConverters[idx];
                static if (is(M : Mapper!(A, B, D), alias D))
                    alias getTypeConverterImpl = M;
                else
                    alias getTypeConverterImpl = getTypeConverterImpl!(idx + 1); // continue searching
            }
            else
                alias getTypeConverterImpl = void; // not found
        }

        alias getTypeConverter = getTypeConverterImpl!0;
    }

    /// Class mapper.
    B map(B, A)(A a) if (isClassOrStruct!A && isClassOrStruct!B)
    {
        static if (isClass!B)
            B b = new B();
        else
            B b;

        alias M = getMapperDefinition!(A, B);

        static if (is(M == void))
            static assert(false, "No mapper found for mapping from " ~ A.stringof ~ " to " ~ B.stringof);
        else {
            // auto complete mappping
            alias AutoMapping = M.Mappings;//completeUserMapping!(A, B, M.Mappings);

            // warn about un-mapped members in B
            static foreach(member; ClassMembers!B) {
                static if (!buildMappedMemberList!(AutoMapping).canFind(member)) {
                    static assert(false, "non mapped member in destination object '" ~ B.stringof ~"." ~ member ~ "'");
                }
            }

            // instanciate class member
            static foreach(member; ClassMembers!B) {
                static if (isClass!(MemberType!(B, member))) {
                    __traits(getMember, b, member) = new MemberType!(B, member);
                }
            }

            // generate mapping code
            static foreach(Mapping; AutoMapping) {
                static if (isCustomMemberMapping!Mapping) {
                    static assert(hasNestedMember!(B, Mapping.BMember), Mapping.BMember ~ " is not a member of " ~ B.stringof);

                    // ForMember - mapMember
                    static if (isForMember!(Mapping, ForMemberType.mapMember)) {
                        static assert(hasNestedMember!(A, Mapping.Action), Mapping.Action ~ " is not a member of " ~ A.stringof);

                        // same type
                        static if (is(MemberType!(B, Mapping.BMember) == MemberType!(A, Mapping.Action))) {
                            mixin(GetMember!(b, Mapping.BMember)) = mixin(GetMember!(a, Mapping.Action)); // b.member = a. member;
                        }
                        // different type: map
                        else {
                            __traits(getMember, b, Mapping.BMember) = this.map!(
                                MemberType!(B, Mapping.BMember),
                                MemberType!(A, Mapping.Action))(__traits(getMember, a, Mapping.Action)); // b.member = context.map(a.member);
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
                        static assert(Parameters!(Mapping.Action).length is 1 && is(Parameters!(Mapping.Action)[0] == A),
                            "the func in " ~ ForMember.stringof ~ " must take a value of type '" ~ A.stringof ~"'");
                        __traits(getMember, b, Mapping.BMember) = Mapping.Action(a);
                    }
                }
            }
        }

        return b;
    }

    /// Builtin array mapper.
    B map(B, A)(A a) if (isArray!A && isArray!B)
    {
        B ret = B.init;

        foreach(ForeachType!A elem; a) {
            static if (is(ForeachType!A == ForeachType!B))
                ret ~= elem; // same array type, just copy
            else
                ret ~= this.map!(ForeachType!B)(elem); // else map
        }

        return ret;
    }

    /// Type converter.
    B map(B, A)(A a) if (!isArray!A && !isArray!B && (!isClassOrStruct!A || !isClassOrStruct!B))
    {
        alias M = getTypeConverter!(A, B);

        static if (is(M == void))
            static assert(false, "No type converter found for mapping from " ~ A.stringof ~ " to " ~ B.stringof ~ ". Register it with \"" ~
                Mapper!(A, B, (A a) => B.init).stringof ~ "\" for example.");
        else {
            return M.Mappings(a);
        }
    }

}

// Type converters
unittest
{
    import std.datetime;

    static class A {
        long timestamp = 1542873605;
    }

    static class B {
        SysTime timestamp;
    }

    auto am = new AutoMapper!(
        Mapper!(long, SysTime, (long ts) => SysTime(ts)),
        Mapper!(A, B));


    A a = new A();
    B b = am.map!B(a);

    assert(SysTime(a.timestamp) == b.timestamp);
}


// struct
unittest
{
    static struct A {
        int foo;
    }

    static struct B {
        int foo;
    }

    auto am = new AutoMapper!(
        Mapper!(A, B));

    A a;
    B b = am.map!B(a);
    assert(b.foo == a.foo);
}

// reverse flattening
unittest
{
    static class Address {
        int zipcode;
    }

    static class A {
        Address address;
    }

    static class B {
        int addressZipcode = 74000;
    }

    auto am = new AutoMapper!(
        Mapper!(A, B, Reverse));

    B b = new B();
    A a = am.map!A(b);
    assert(b.addressZipcode == a.address.zipcode);
}

// array
unittest
{
    import std.algorithm.comparison : equal;

    static class Data {
        this() {}
        this(string id) { this.id = id; }
        string id;
    }

    static class DataDTO {
        string id;
    }

    static class A {
        int[] foo = [1, 2, 4, 8];
        Data[] data = [new Data("baz"), new Data("foz")];
    }

    static class B {
        int[] foo;
        DataDTO[] data;
    }

    auto am = new AutoMapper!(
        Mapper!(Data, DataDTO),
        Mapper!(A, B));

    A a = new A();
    B b = am.map!B(a);

    assert(b.foo.equal(a.foo));
    assert(b.data.length == 2);
    assert(b.data[0].id == "baz");
    assert(b.data[1].id == "foz");
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

    auto am = new AutoMapper!(
        Mapper!(User, UserDTO,
            ForMember!("fullName", (User a) => a.name ~ " " ~ a.lastName )));

    auto user = new User();
    UserDTO dto = am.map!UserDTO(user);

    assert(dto.fullName == user.name ~ " " ~ user.lastName);
    assert(dto.addressCity == user.address.city);
    assert(dto.addressZipcode == user.address.zipcode);

}

// flattening
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

    auto am = new AutoMapper!(
        Mapper!(A, B,
            ForMember!("addressZipcode", "address.zipcode")));

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

    auto am = new AutoMapper!(
        Mapper!(Address, AddressDTO,
            ForMember!("zipcode", "zipcode"),
            Reverse),
        Mapper!(A, B,
            ForMember!("address", "address"),
            Reverse));

    A a = new A();
    B b = am.map!B(a);
    assert(b.address.zipcode == a.address.zipcode);

    // test reversed mapper
    am.map!Address(new AddressDTO());
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

   auto am = new AutoMapper!(
        Mapper!(A, B,
            ForMember!("str", "str"),
            ForMember!("foo", "foo"),
            IgnoreMember!"bar",
            ForMember!("mod", (A a) {
                return "modified";
            })));


    A a = new A();
    B b = am.map!B(a);
    assert(b.str == a.str);
    assert(a.foo == a.foo);
    assert(b.mod == "modified");
}
