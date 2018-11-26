/**
    Contains mapper.
*/
module automapper.mapper;

import automapper.meta;
import automapper.naming;
import automapper.type.converter;
import automapper.value.transformer;

/**
    Define AutoMapper configuration.
*/
class MapperConfiguration(C...) if (allSatisfy!(isConfigurationObject, C))
{
    // sort configuration object
    private alias ObjectMappers = getMappers!(C);
    alias TypesConverters = getTypeConverters!(C);
    alias ValueTransformers = getValueTransformers!(C);
    // Generate reversed mapper and complete them too
    alias FullObjectMappers = AliasSeq!(ObjectMappers, generateReversedMapper!ObjectMappers);

    static auto createMapper()
    {
        import automapper;
        return new AutoMapper!(typeof(this))();
    }
}

///
unittest
{
    import std.datetime;

    static class Address {
        long zipcode = 42420;
        string city = "London";
    }

    static class User {
        Address address = new Address();
        string name = "Foo";
        string lastName = "Bar";
        string mail = "foo.bar@baz.fr";
        long timestamp;
    }

    static class UserDTO {
        string fullName;
        string email;
        string addressCity;
        long   addressZipcode;
        SysTime timestamp;
        int context;
    }

    alias MyConfig = MapperConfiguration!(
        // create a type converter for a long to SysTime
        CreateMap!(long, SysTime)
            .ConvertUsing!((long ts) => SysTime(ts)),
        // create a mapping for User to UserDTO
        CreateMap!(User, UserDTO)
            // map member using a delegate
            .ForMember!("fullName", (User a) => a.name ~ " " ~ a.lastName )
            // map UserDTO.email to User.mail
            .ForMember!("email", "mail")
            // ignore UserDTO.context
            .Ignore!"context");
            // other member are automatically mapped

    auto am = MyConfig.createMapper();

    auto user = new User();
    UserDTO dto = am.map!UserDTO(user);

    assert(dto.fullName == user.name ~ " " ~ user.lastName);
    assert(dto.addressCity == user.address.city);
    assert(dto.addressZipcode == user.address.zipcode);
}



/**
    It take a list of Mapper, and return a new list of reversed mapper if needed.
    e.g. for CreateMap!(A, B, ForMember("foo", "bar")), it create CreateMap!(B, A, ForMember("bar", "foo")
*/
private template generateReversedMapper(Mappers...) if (allSatisfy!(isObjectMapper, Mappers))
{
    private template generateReversedMapperImpl(size_t idx) {
        static if (idx < Mappers.length) {
            alias M = Mappers[idx];

            private template reverseMapping(size_t midx) {
                static if (midx < M.Mappings.length) {
                    alias MP = M.Mappings[midx];

                    static if (isForMember!(MP, ForMemberType.mapMember)) {
                        alias reverseMapping = AliasSeq!(ForMemberConfig!(MP.Action, MP.MapTo), reverseMapping!(midx + 1));
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

            static if (M.MustBeReversed) // reverse it if needed
                alias generateReversedMapperImpl = AliasSeq!(CreateMap!(M.B, M.A, reverseMapping!0),
                    generateReversedMapperImpl!(idx + 1));
            else
                alias generateReversedMapperImpl = generateReversedMapperImpl!(idx + 1); // continue
        }
        else
            alias generateReversedMapperImpl = AliasSeq!();
    }

    alias generateReversedMapper = generateReversedMapperImpl!0;
}


template CreateMap(A, B, M...) if (!isClassOrStruct!A || !isClassOrStruct!B)
{
    // it's a class or struct mapper
    static if (isClassOrStruct!A && isClassOrStruct!B && allSatisfy!(isObjectMemberMapping, M)) {
        alias static class CreateMap : ObjectMapper!(A, B, CamelCaseNamingConvention, M)
        {
            // alias Mappings = AliasSeq!M;
            enum bool MustBeReversed = false;

            template ReverseMap()
            {
                alias static class ReverseMap : ObjectMapper!(A, B, CamelCaseNamingConvention, M)
                {
                    // alias Mappings = AliasSeq!M;
                    enum bool MustBeReversed = true;
                }
            }

            template SourceMemberNaming(C) if (isNamingConvention!C)
            {
                alias static class SourceMemberNaming : ObjectMapper!(A, B, C, M)
                {
                    // alias Mappings = AliasSeq!M;
                    enum bool MustBeReversed = true;
                }
            }
        }
    }
    // it's a type converter
    else static if (M.length is 0) {
        template ConvertUsing(alias Delegate) if (isCallable!Delegate)
        {
            static assert(is(ReturnType!Delegate == B), "must return a " ~ B.stringof);
            static assert((Parameters!Delegate.length == 1) && is(Parameters!Delegate[0] == A), "must take one argument of type " ~ A.stringof);

            alias static class ConvertUsing : DelegateTypeConverter!(A, B, Delegate)
            {

            }
        }

        template ConvertUsing(Type) if (isTypeConverter!Type)
        {
            alias ConvertUsing = Type;
        }
    }
    else
    {
        static assert(false, "invalid call");
    }
}

///
unittest
{
    class A {
        string foo;
        int bar;
    }

    class B {
        string qux;
        int baz;
    }

   auto am = MapperConfiguration!(
        CreateMap!(A, B)
            .ForMember!("qux", "foo")
            .ForMember!("baz", "foo"))
                .createMapper();
}

///
unittest
{
    import std.datetime;

    class A {
        long timestamp;
    }

    class B {
        SysTime timestamp;
    }

    auto am = MapperConfiguration!(
        CreateMap!(long, SysTime)
            .ConvertUsing!((long ts) => SysTime(ts)),
        CreateMap!(A, B))
            .createMapper();
}

/// Filter Mappers list to return only mapper that match MapperType.
private template getMappersByType(Mappers...) if (allSatisfy!(isObjectMapper, Mappers))
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

private template getMappers(Mappers...)
{
    private template getMappersImpl(size_t idx) {
        static if (idx < Mappers.length) {
            static if (isObjectMapper!(Mappers[idx]))
                alias getMappersImpl = AliasSeq!(Mappers[idx], getMappersImpl!(idx + 1));
            else
                alias getMappersImpl = getMappersImpl!(idx + 1);
        }
        else
            alias getMappersImpl = AliasSeq!();
    }

    alias getMappers = getMappersImpl!0;
}

private template getTypeConverters(Mappers...)
{
    private template getTypeConvertersImpl(size_t idx) {
        static if (idx < Mappers.length) {
            static if (isTypeConverter!(Mappers[idx]))
                alias getTypeConvertersImpl = AliasSeq!(Mappers[idx], getTypeConvertersImpl!(idx + 1));
            else
                alias getTypeConvertersImpl = getTypeConvertersImpl!(idx + 1);
        }
        else
            alias getTypeConvertersImpl = AliasSeq!();
    }

    alias getTypeConverters = getTypeConvertersImpl!0;
}

package template isConfigurationObject(T)
{
    enum bool isConfigurationObject = (
        isObjectMapper!T ||
        isTypeConverter!T ||
        isValueTransformer!T);
}

struct ReverseMapConfig {}

template isReverseMapConfig(T)
{
    enum isReverseMapConfig = is(T : ReverseMapConfig);
}

template CreateMap(A, B, Configs...) if (isClassOrStruct!A && isClassOrStruct!B)
{
    enum bool Reverse = onlyOneExists!(isReverseMapConfig, Configs);
    alias MemberMappings = Filter!(isObjectMemberMapping, Configs);

    alias static class CreateMap : ObjectMapper!(A, B, CamelCaseNamingConvention, MemberMappings)
    {
        enum bool MustBeReversed = Reverse;

        template ReverseMap()
        {
            alias ReverseMap = CreateMap!(A, B, AliasSeq!(Configs, ReverseMapConfig));
        }

        template ForMember(string DestMember, string SrcMember)
        {
            alias ForMember = CreateMap!(A, B, AliasSeq!(Configs,
                ForMemberConfig!(DestMember, SrcMember)));
        }

        template ForMember(string DestMember, alias Delegate)
        {
            alias ForMember = CreateMap!(A, B, AliasSeq!(Configs,
                ForMemberConfig!(DestMember, Delegate)));
        }

        template Ignore(string DestMember)
        {
            alias Ignore = CreateMap!(A, B, AliasSeq!(Configs, IgnoreConfig!DestMember));
        }
    }
}

unittest
{
    static class A {
        string str;
        string bar;
    }

    static class B {
        string str;
        string foo;
    }

   auto am = MapperConfiguration!(
        CreateMap!(A, B)
            .ForMember!("str", "str")
            .ForMember!("foo", "bar"))
                .createMapper();
}

/**
    Allow to create compile-time generated class and struct mapper.
*/
package class ObjectMapper(F, T, C, M...) if (isNamingConvention!C)
{
    alias A = F;
    alias B = T;
    alias Mappings = tryAutoMapUnmappedMembers!(A, B, C, M);

    static B map(AutoMapper)(A a, AutoMapper am)
    {
        import std.algorithm : canFind;

        // init return value
        static if (isClass!B)
            B b = new B();
        else
            B b;

        // auto complete mappping
        alias AutoMapping = Mappings;

        // warn about un-mapped members in B
        static foreach(member; ClassMembers!B) {
            static if (!listMappedObjectMember!(AutoMapping).canFind(member)) {
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
            static if (isObjectMemberMapping!Mapping) {
                static assert(hasNestedMember!(B, Mapping.MapTo), Mapping.MapTo ~ " is not a member of " ~ B.stringof);

                // ForMember - mapMember
                static if (isForMember!(Mapping, ForMemberType.mapMember)) {
                    static assert(hasNestedMember!(A, Mapping.Action), Mapping.Action ~ " is not a member of " ~ A.stringof);

                    // same type
                    static if (is(MemberType!(B, Mapping.MapTo) == MemberType!(A, Mapping.Action))) {
                        mixin(GetMember!(b, Mapping.MapTo)) = am.transform(mixin(GetMember!(a, Mapping.Action))); // b.member = a. member;
                    }
                    // different type: map
                    else {
                        __traits(getMember, b, Mapping.MapTo) = am.map!(
                            MemberType!(B, Mapping.MapTo),
                            MemberType!(A, Mapping.Action))(__traits(getMember, a, Mapping.Action)); // b.member = context.map(a.member);
                    }
                }
                // ForMember - mapDelegate
                else static if (isForMember!(Mapping, ForMemberType.mapDelegate)) {
                    // static assert return type
                    static assert(is(ReturnType!(Mapping.Action) == MemberType!(B, Mapping.MapTo)),
                        "the func in " ~ ForMember.stringof ~ " must return a '" ~
                        MemberType!(B, Mapping.MapTo).stringof ~ "' like " ~ B.stringof ~
                        "." ~ Mapping.MapTo);
                    // static assert parameters
                    static assert(Parameters!(Mapping.Action).length is 1 && is(Parameters!(Mapping.Action)[0] == A),
                        "the func in " ~ ForMember.stringof ~ " must take a value of type '" ~ A.stringof ~"'");
                    __traits(getMember, b, Mapping.MapTo) = Mapping.Action(a);
                }
            }
        }

        return b;
    }
}

package template isObjectMapper(T)
{
    enum bool isObjectMapper = (is(T: ObjectMapper!(A, B, C), A, B, C) ||
        is(T: ObjectMapper!(AB, BB, CB, M), AB, BB, CB, M));
}

unittest
{
    class A {}
    static assert(CreateMap!(A, A).ReverseMap!().MustBeReversed);
    static assert(!CreateMap!(A, A).MustBeReversed);
}


unittest
{
    class A {}
    class B {}
    struct C {}

    static assert(isObjectMapper!(CreateMap!(A, B)));
}

/**
    Base class for custom member mapping.
    Template_Params:
        MT = The member to map in the destination object
**/
package class ObjectMemberMapping(string T)
{
    enum string MapTo = T;
}

package template isObjectMemberMapping(T)
{
    enum bool isObjectMemberMapping = (is(T: ObjectMemberMapping!BM, string BM));
}

/// ForMember mapping type
package enum ForMemberType
{
    mapMember,  // map a member to another member
    mapDelegate // map a member to a delegate
}

/**
    Used to specialized a member mapping.
    Template_Params:
        T = The member name in the destination object
        F = The member name in the source object or a custom delegate
**/
class ForMemberConfig(string T, alias F) : ObjectMemberMapping!(T)
{
    static assert(is(typeof(F) == string) || isCallable!F, ForMemberConfig.stringof ~
        " Action must be a string to map a member to another member or a delegate.");

    static if (is(typeof(F) == string))
        private enum ForMemberType Type = ForMemberType.mapMember;
    else
        private enum ForMemberType Type = ForMemberType.mapDelegate;

    alias Action = F;
}

///
unittest
{
    import automapper;

    class A {
        string foo;
        int bar;
    }

    class B {
        string qux;
        int baz;
        long ts;
    }

   auto am = MapperConfiguration!(
        CreateMap!(A, B)
            .ForMember!("qux", "foo")
            .ForMember!("baz", "foo")
            .ForMember!("ts", (A a) => 123456 ))
                .createMapper();
}


package template isForMember(T, ForMemberType Type)
{
    static if (is(T == ForMemberConfig!(MapTo, Action), string MapTo, alias Action))
        static if (T.Type == Type)
            enum bool isForMember = true;
        else
            enum bool isForMember = false;
    else
        enum bool isForMember = false;
}

/**
    Used to ignore a member in the destination object.
    Template_Params:
        T = The member name in the destination object
**/
class IgnoreConfig(string T) : ObjectMemberMapping!(T)
{
    // do nothing
}

///
unittest
{
    import automapper;

    class A {
        string foo;
        int bar;
    }

    class B {
        string qux;
        int baz;
        long ts;
    }

   auto am = MapperConfiguration!(
        CreateMap!(A, B)
            .ForMember!("qux", "foo")
            .ForMember!("baz", "foo")
            .Ignore!("ts"))
                .createMapper();
}



/**
    List mapped object member.
    Params:
        Mappings = a list of ObjectMemberMapping
    Returns:
        a string[] of mapped member identifer
*/
package template listMappedObjectMember(Mappings...) if (allSatisfy!(isObjectMemberMapping, Mappings))
{
    import std.string : split;

    private template listMappedObjectMemberImpl(size_t idx) {
        static if (idx < Mappings.length)
            static if (isObjectMemberMapping!(Mappings[idx]))
                enum string[] listMappedObjectMemberImpl = Mappings[idx].MapTo ~ Mappings[idx].MapTo.split(".") ~ listMappedObjectMemberImpl!(idx + 1);
            else
                enum string[] listMappedObjectMemberImpl = listMappedObjectMemberImpl!(idx + 1); // skip
        else
            enum string[] listMappedObjectMemberImpl = [];
    }

    enum string[] listMappedObjectMember = listMappedObjectMemberImpl!0;
}

/**
    Try to automatically map unmapper member.

    It:
        * map member with the same name
        * map flattened member to destination object
          e.g: A.foo.bar is mapped to B.fooBar

    Params:
        A = The type to map from
        B = The type to map to
        Mappings = a list of ObjectMemberMapping
    Returns:
        A list of completed ObjectMemberMapping
*/
package template tryAutoMapUnmappedMembers(A, B, C, Mappings...) if
    (isNamingConvention!C && allSatisfy!(isObjectMemberMapping, Mappings))
{
    import std.algorithm : canFind;
    import std.string : join;

    enum MappedMembers = listMappedObjectMember!(Mappings);
    enum Convention = C();

    private template tryAutoMapUnmappedMembersImpl(size_t idx) {
        static if (idx < FlattenedMembers!A.length) {
            enum M = FlattenedMembers!A[idx];

            // un-mapped by user
            static if (!MappedMembers.canFind(M)) {
                // B has this member: B.foo = A.foo
                static if (hasMember!(B, M)) {
                    alias tryAutoMapUnmappedMembersImpl = AliasSeq!(ForMemberConfig!(M, M),
                        tryAutoMapUnmappedMembersImpl!(idx+1));
                }
                // B has this Convention.convert(identifier) class member: B.Convention.convert(identifier) = A.foo.bar
                else static if (hasMember!(B, Convention.convert(M))) {
                    alias tryAutoMapUnmappedMembersImpl = AliasSeq!(ForMemberConfig!(Convention.convert(M), M),
                        tryAutoMapUnmappedMembersImpl!(idx+1));
                }
                else
                    alias tryAutoMapUnmappedMembersImpl = tryAutoMapUnmappedMembersImpl!(idx+1);
            }
            else
                alias tryAutoMapUnmappedMembersImpl = tryAutoMapUnmappedMembersImpl!(idx+1);
        }
        else
            alias tryAutoMapUnmappedMembersImpl = AliasSeq!();
    }

    alias tryAutoMapUnmappedMembers = AliasSeq!(tryAutoMapUnmappedMembersImpl!0, Mappings);
}
