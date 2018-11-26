/**
    Automatic compile-time generated object mapper.

    This module aims to provide a compile-time generated way to
    create object mapper with no runtime overhead.

        Rules for automatic mapping are detailed below:

    Same_type_and_same_name:

	----
	class A
	{
	    int foo;
	}

	class B
	{
	    int foo;
	}

	new AutoMapper!(
        CreateMap!(A, B));
	----

    Same_name:

	You need to define a type converter.

	----
	class A
	{
	    int foo;
	}


	class B
	{
	    long foo;
	}

	new AutoMapper!(
        CreateMap!(int, long,
            (int i) => i.to!long ),
        CreateMap!(User, UserDTO));
	----

	Flattened_member_name:

	A flattened member name is a camel case identifier like: fooBar

	In the exemple below, B.fooBaz is automatically mapped to A.foo.bar
	----
	class Foo
	{
	    int baz;
	}

	class A
	{
	    Foo foo;
	}

	class B
	{
	    int fooBaz;
	}

	new AutoMapper!(
        CreateMap!(A, B));
	----

*/
module automapper;

import automapper.meta;
import automapper.mapper;
import automapper.type.converter;
import automapper.value.transformer;
import automapper.naming;

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
        CreateMap!(User, UserDTO,
            // map member using a delegate
            ForMember!("fullName", (User a) => a.name ~ " " ~ a.lastName ),
            // map UserDTO.email to User.mail
            ForMember!("email", "mail"),
            // ignore UserDTO.context
            Ignore!"context"));
            // other member are automatically mapped

    auto am = MyConfig.createMapper();

    auto user = new User();
    UserDTO dto = am.map!UserDTO(user);

    assert(dto.fullName == user.name ~ " " ~ user.lastName);
    assert(dto.addressCity == user.address.city);
    assert(dto.addressZipcode == user.address.zipcode);
}

package template isConfigurationObject(T)
{
    enum bool isConfigurationObject = (
        isObjectMapper!T ||
        isTypeConverter!T ||
        isValueTransformer!T);
}

template CreateMap(A, B, M...)
{
    // it's a class or struct mapper
    static if (isClassOrStruct!A && isClassOrStruct!B && allSatisfy!(isObjectMemberMapping, M)) {
        alias static class CreateMap : ObjectMapper!(A, B, M)
        {
            // alias Mappings = AliasSeq!M;
            enum bool MustBeReversed = false;

            template ReverseMap()
            {
                alias static class ReverseMap : ObjectMapper!(A, B, M)
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
        CreateMap!(A, B,
            ForMember!("qux", "foo"),
            ForMember!("baz", "foo")))
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

/// Compile-time trick to override MustBeReversed enum.
private class CreateMapWithReverse(F, T, M...) : CreateMap!(F, T, M)
{
    enum bool MustBeReversed = true; // override
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
                        alias reverseMapping = AliasSeq!(ForMember!(MP.Action, MP.MapTo), reverseMapping!(midx + 1));
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
                alias generateReversedMapperImpl = AliasSeq!(CreateMap!(M.B, M.A,
                    tryAutoMapUnmappedMembers!(M.B, M.A, CamelCaseNamingConvention, reverseMapping!0)),
                    generateReversedMapperImpl!(idx + 1));
            else
                alias generateReversedMapperImpl = generateReversedMapperImpl!(idx + 1); // continue
        }
        else
            alias generateReversedMapperImpl = AliasSeq!();
    }

    alias generateReversedMapper = generateReversedMapperImpl!0;
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

/**
    AutoMapper entry point.

    Used to create zero runtime overhead mapper for object or struct.
*/
class AutoMapper(MC) if (is(MC : MapperConfiguration!(C), C))
{
    import std.algorithm : canFind;
    import std.format;

private:
    // sort mapper by type
    private alias TypesConverters = MC.TypesConverters;
    private alias ValueTransformers = MC.ValueTransformers;
    // Generate reversed mapper and complete them too
    private alias FullMappers = MC.FullObjectMappers;

    // debug pragma(msg, "FullMappers: " ~ Mappers.stringof);
    // Find the right mapper in the FullMappers.
    private template getMapperDefinition(A, B)
    {
        private template getMapperDefinitionImpl(size_t idx) {
            static if (idx < FullMappers.length) {
                alias M = FullMappers[idx];
                static if (is(M : ObjectMapper!(A, B))) // Mapper without mapping
                    alias getMapperDefinitionImpl = M;
                else static if (is(M : ObjectMapper!(A, B, T), T)) // Mapper with mapping
                    alias getMapperDefinitionImpl = M;
                else
                    alias getMapperDefinitionImpl = getMapperDefinitionImpl!(idx + 1); // continue searching
            }
            else
                alias getMapperDefinitionImpl = void; // not found
        }

        alias getMapperDefinition = getMapperDefinitionImpl!0;
    }

    // Find the type converter in the TypesConverters.
    private template getTypeConverter(A, B)
    {
        private template getTypeConverterImpl(size_t idx) {
            static if (idx < TypesConverters.length) {
                alias M = TypesConverters[idx];
                static if (is(M : ITypeConverter!(A, B)))
                    alias getTypeConverterImpl = M;
                else
                    alias getTypeConverterImpl = getTypeConverterImpl!(idx + 1); // continue searching
            }
            else
                alias getTypeConverterImpl = void; // not found
        }

        alias getTypeConverter = getTypeConverterImpl!0;
    }

    private template uniqueConverterIdentifier(A, B)
    {
        import std.string : replace;
        enum string uniqueConverterIdentifier = ("conv_" ~ fullyQualifiedName!A ~ "_" ~ fullyQualifiedName!B).replace(".", "_");
    }

    // declare private registered ITypeConverter
    static foreach (Conv; TypesConverters) {
        static if (is(Conv : ITypeConverter!(A, B), A, B)) {
            mixin(q{private ITypeConverter!(A, B) %s; }.format(
                uniqueConverterIdentifier!(A, B)));
        }
    }

    private template uniqueTransformerIdentifier(A)
    {
        import std.string : replace;
        enum string uniqueTransformerIdentifier = ("trans" ~ fullyQualifiedName!A).replace(".", "_");
    }

    // declare private registered IValueTransformer
    static foreach (Trans; ValueTransformers) {
        static if (is(Trans : IValueTransformer!TValue, TValue)) {
            mixin(q{private IValueTransformer!TValue %s; }.format(
                uniqueTransformerIdentifier!TValue));
        }
    }

public:
    this()
    {
        // instanciate registered ITypeConverter
        static foreach (Conv; TypesConverters)
            static if (is(Conv : ITypeConverter!(A, B), A, B))
                mixin(q{%s = new Conv(); }.format(uniqueConverterIdentifier!(A, B)));

        // instanciate registered IValueTransformer
        static foreach (Trans; ValueTransformers)
            static if (is(Trans : IValueTransformer!TValue, TValue))
                mixin(q{%s = new Trans(); }.format(uniqueTransformerIdentifier!TValue));
    }

    /**
        Map a type to another type.
        Params:
            a = The type to map
        Retuns:
            The mapped type
    */
    B map(B, A)(A a) if (isClassOrStruct!A && isClassOrStruct!B)
    {
        alias M = getMapperDefinition!(A, B);

        static if (is(M == void))
            static assert(false, "No mapper found for mapping from " ~ A.stringof ~ " to " ~ B.stringof);
        else
            return M.map(a, this);
    }

    /// ditto
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

    /// ditto
    B map(B, A)(A a) if (!isArray!A && !isArray!B && (!isClassOrStruct!A || !isClassOrStruct!B))
    {
        alias M = getTypeConverter!(A, B);

        static if (is(M == void))
            static assert(false, "No type converter found for mapping from " ~ A.stringof ~ " to " ~ B.stringof);
        else
            return __traits(getMember, this, uniqueConverterIdentifier!(A, B)).convert(a);
    }

    TValue transform(TValue)(TValue value)
    {
        alias Transformer = getValueTransformer!(TValue, ValueTransformers);

        static if (is(Transformer == void)) {
            pragma(inline, true);
            return value;
        }
        else
            return __traits(getMember, this, uniqueTransformerIdentifier!TValue).transform(value);
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

    // we would like to map from User to UserDTO
    auto am = MapperConfiguration!(
        // create a type converter for a long to SysTime
        CreateMap!(long, SysTime)
            .ConvertUsing!((long ts) => SysTime(ts)),
        // create a mapping for User to UserDTO
        CreateMap!(User, UserDTO,
            // map member using a delegate
            ForMember!("fullName", (User a) => a.name ~ " " ~ a.lastName ),
            // map UserDTO.email to User.mail
            ForMember!("email", "mail"),
            // ignore UserDTO.context
            Ignore!"context"))
            // other member are automatically mapped
            .createMapper();

    auto user = new User();
    UserDTO dto = am.map!UserDTO(user);

    assert(dto.fullName == user.name ~ " " ~ user.lastName);
    assert(dto.addressCity == user.address.city);
    assert(dto.addressZipcode == user.address.zipcode);
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

    auto am_delegate = MapperConfiguration!(
        CreateMap!(long, SysTime).ConvertUsing!((long ts) => SysTime(ts)),
        CreateMap!(A, B))
            .createMapper();

    A a = new A();
    B b = am_delegate.map!B(a);
    assert(SysTime(a.timestamp) == b.timestamp);


    static class TimestampToSystime : ITypeConverter!(long, SysTime) {
        override SysTime convert(long ts) {
            return SysTime(ts);
        }
    }

    auto am_class = MapperConfiguration!(
        CreateMap!(long, SysTime).ConvertUsing!TimestampToSystime,
        CreateMap!(A, B))
            .createMapper();

    a = new A();
    b = am_class.map!B(a);
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

    auto am = MapperConfiguration!(
        CreateMap!(A, B))
            .createMapper();

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

    auto am = MapperConfiguration!(
        CreateMap!(A, B)
            .ReverseMap!())
            .createMapper();

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

    auto am = MapperConfiguration!(
        CreateMap!(Data, DataDTO),
        CreateMap!(A, B))
            .createMapper();

    auto am2 = MapperConfiguration!(
        CreateMap!(Data, DataDTO),
        CreateMap!(A, B))
            .createMapper();

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

    auto am = MapperConfiguration!(
        CreateMap!(User, UserDTO,
            ForMember!("fullName", (User a) => a.name ~ " " ~ a.lastName )))
            .createMapper();

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

    auto am = MapperConfiguration!(
        CreateMap!(A, B,
            ForMember!("addressZipcode", "address.zipcode")))
        .createMapper();

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

    auto am = MapperConfiguration!(
        CreateMap!(Address, AddressDTO,
            ForMember!("zipcode", "zipcode"))
                .ReverseMap!(),
        CreateMap!(A, B,
            ForMember!("address", "address"))
                .ReverseMap!())
            .createMapper();

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

   auto am = MapperConfiguration!(
        CreateMap!(A, B,
            ForMember!("str", "str"),
            ForMember!("foo", "foo"),
            Ignore!"bar",
            ForMember!("mod", (A a) {
                return "modified";
            })))
                .createMapper();


    A a = new A();
    B b = am.map!B(a);
    assert(b.str == a.str);
    assert(a.foo == a.foo);
    assert(b.mod == "modified");
}
