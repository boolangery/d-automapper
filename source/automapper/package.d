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
import automapper.value.transformer;

public import automapper.api;
public import automapper.type.converter;
public import automapper.mapper;
public import automapper.naming;


/// Is the provided type a configuration object ?
package template isConfigurationObject(T)
{
    enum bool isConfigurationObject = (
        isObjectMapper!T ||
        isTypeConverter!T ||
        isValueTransformer!T);
}

/**
    Define AutoMapper configuration.
*/
class MapperConfiguration(Configs...) if (allSatisfy!(isConfigurationObject, Configs))
{
    // sort configuration object
    private alias ObjectMappers = Filter!(isObjectMapper, Configs);
    alias TypesConverters = Filter!(isTypeConverter, Configs);
    alias ValueTransformers = Filter!(isValueTransformer, Configs);
    // Add reversed mapper to user mapper
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
    AutoMapper entry point.

    Used to create zero runtime overhead mapper for object or struct.
*/
class AutoMapper(MC) if (is(MC : MapperConfiguration!(C), C))
{
    import std.format;

private:
    private alias TypesConverters = MC.TypesConverters;
    private alias ValueTransformers = MC.ValueTransformers;
    private alias FullMappers = MC.FullObjectMappers;
    // debug pragma(msg, "FullMappers: " ~ Mappers.stringof);

    /// run-time
    private string runtimeUniqueMapperIdentifier(TypeInfo a, TypeInfo b)
    {
        import std.string : replace;

        return ("mapper_" ~ a.toString() ~ "_" ~ b.toString()).replace(".", "_");
    }

    /// compile-time
    private template uniqueConverterIdentifier(T)
    {
        import std.string : replace;
        static if (is(T : ITypeConverter!(A, B), A, B))
            enum string uniqueConverterIdentifier = ("conv_" ~ fullyQualifiedName!A ~ "_" ~ fullyQualifiedName!B).replace(".", "_");
    }

    // declare private registered ITypeConverter
    static foreach (Conv; TypesConverters) {
        static if (is(Conv : ITypeConverter!(A, B), A, B)) {
            mixin(q{private ITypeConverter!(%s, %s) %s; }.format(fullyQualifiedName!A, fullyQualifiedName!B, uniqueConverterIdentifier!Conv));
        }
    }

    /// compile-time
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
            mixin(q{%s = new Conv(); }.format(uniqueConverterIdentifier!Conv));

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
        template isRightMapper(T) {
            enum bool isRightMapper = (is(T : ObjectMapper!(A, B, C), C) ||
                is(T : ObjectMapper!(A, B, C, M), M));
        }

        alias M = Filter!(isRightMapper, FullMappers);

        static if (M.length is 0)
            static assert(false, "No mapper found for mapping from " ~ A.stringof ~ " to " ~ B.stringof);
        else
            return M[0].map(a, this);
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
        template isRightConverter(T) {
            enum bool isRightConverter = is(T : ITypeConverter!(A, B));
        }

        alias M = Filter!(isRightConverter, TypesConverters);

        static if (M.length is 0)
            static assert(false, "No type converter found for mapping from " ~ A.stringof ~ " to " ~ B.stringof);
        else
            return __traits(getMember, this, uniqueConverterIdentifier!M).convert(a);
    }

    TValue transform(TValue)(TValue value)
    {
        template isRightTransformer(T) {
            enum bool isRightTransformer = is(T : IValueTransformer!(TValue));
        }

        alias Transformer = Filter!(isRightTransformer, ValueTransformers);

        static if (Transformer.length is 0) {
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
        CreateMap!(User, UserDTO)
            // map member using a delegate
            .ForMember!("fullName", (User a) => a.name ~ " " ~ a.lastName )
            // map UserDTO.email to User.mail
            .ForMember!("email", "mail")
            // ignore UserDTO.context
            .Ignore!"context")
            // other member are automatically mapped
            .createMapper();

    auto user = new User();
    UserDTO dto = am.map!UserDTO(user);

    assert(dto.fullName == user.name ~ " " ~ user.lastName);
    assert(dto.addressCity == user.address.city);
    assert(dto.addressZipcode == user.address.zipcode);
}

// Naming conventions
unittest
{
    static class A {
        int foo_bar_baz = 42;
        string data_processor = "42";
    }

    static class B {
        int fooBarBaz;
        string dataProcessor;
    }

    auto am = MapperConfiguration!(
        CreateMap!(A, B)
            .SourceMemberNaming!LowerUnderscoreNamingConvention
            .DestMemberNaming!CamelCaseNamingConvention)
                .createMapper();

    A a = new A();
    B b = am.map!B(a);
    assert(a.foo_bar_baz == b.fooBarBaz);
    assert(a.data_processor == b.dataProcessor);
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
        CreateMap!(User, UserDTO)
            .ForMember!("fullName", (User a) => a.name ~ " " ~ a.lastName ))
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
        CreateMap!(A, B)
            .ForMember!("addressZipcode", "address.zipcode"))
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
        CreateMap!(Address, AddressDTO)
            .ForMember!("zipcode", "zipcode")
            .ReverseMap!(),
        CreateMap!(A, B)
            .ForMember!("address", "address")
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
        CreateMap!(A, B)
            .ForMember!("str", "str")
            .ForMember!("foo", "foo")
            .Ignore!"bar"
            .ForMember!("mod", (A a) {
                return "modified";
            }))
            .createMapper();


    A a = new A();
    B b = am.map!B(a);
    assert(b.str == a.str);
    assert(a.foo == a.foo);
    assert(b.mod == "modified");
}
