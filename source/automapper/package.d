/**
    Automatic compile-time generated object mapper.

    This module aims to provide a compile-time generated way to
    create object mapper with no runtime overhead.

    Features:

    $(UL
	    $(LI Object and struct automatic mapping: See `AutoMapper`)
	    $(LI Type converter: See `automapper.type.converter`)
	    $(LI Value transformer: See `automapper.value.transformer`)
	)

    To get an AutoMapper instance you need to provide a `automapper.config.MapperConfiguration`.

*/
module automapper;

import automapper.meta;
import automapper.value.transformer;

public import automapper.api;
public import automapper.type.converter;
public import automapper.mapper;
public import automapper.naming;


/**
    AutoMapper entry point.

    Used to create low runtime overhead mapper for object or struct.
*/
class AutoMapper(MC) if (is(MC : MapperConfiguration!(C), C))
{
    import std.format : format;

private:
    alias TypesConverters = MC.TypesConverters;
    alias ValueTransformers = MC.ValueTransformers;

    template completeMapperConfiguration()
    {
        private template completeMapperConfigurationImpl(size_t idx) {
            static if (idx < MC.ObjectMappersConfig.length) {
                alias CurrentConfig = MC.ObjectMappersConfig[idx];

                 // trick to get config specialization
                static if (is(CurrentConfig : ObjectMapperConfig!(TSource, TDest, TSourceConv, 
                    TDestConv, Reverse, Mappings),
                    TSource, TDest, TSourceConv, TDestConv, bool Reverse, Mappings...)) {

                    alias NewConfig = tryAutoMapUnmappedMembers!(TSource, TDest, TSourceConv, TDestConv, Mappings);
                    alias completeMapperConfigurationImpl = AliasSeq!(
                        ObjectMapperConfig!(TSource, TDest, TSourceConv, TDestConv, Reverse, NewConfig),
                        completeMapperConfigurationImpl!(idx + 1));
                }
            }
            else
                alias completeMapperConfigurationImpl = AliasSeq!();
        }

        alias completeMapperConfiguration = completeMapperConfigurationImpl!0;
    }

    alias CompletedConfig = completeMapperConfiguration!();
    alias FullMapperConfigs = AliasSeq!(CompletedConfig, generateReversedMapperConfig!(CompletedConfig));

    template buildMapper()
    {
        private template buildMapperImpl(size_t idx) {
            static if (idx < FullMapperConfigs.length) {
                alias MPC = FullMapperConfigs[idx];

                alias buildMapperImpl = AliasSeq!(
                    ObjectMapper!MPC,
                    buildMapperImpl!(idx + 1));
            }
            else
                alias buildMapperImpl = AliasSeq!();
        }
        alias buildMapper = buildMapperImpl!0;
    }


    alias FullMappers = buildMapper!();


    // run-time
    string runtimeUniqueMapperIdentifier(TypeInfo a, TypeInfo b)
    {
        import std.string : replace;

        return ("mapper_" ~ a.toString() ~ "_" ~ b.toString()).replace(".", "_");
    }

    /// compile-time
    template uniqueConverterIdentifier(T)
    {
        import std.string : replace;
        static if (is(T : ITypeConverter!(A, B), A, B))
            enum string uniqueConverterIdentifier = ("conv_" ~ fullyQualifiedName!A ~ "_" ~ fullyQualifiedName!B)
                .replace(".", "_");
    }

    // declare private registered ITypeConverter
    static foreach (Conv; TypesConverters) {
        static if (is(Conv : ITypeConverter!(A, B), A, B)) {
            mixin(q{private ITypeConverter!(%s, %s) %s; }.format(fullyQualifiedName!A, fullyQualifiedName!B,
                uniqueConverterIdentifier!Conv));
        }
    }

    /// compile-time
    template uniqueTransformerIdentifier(A)
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
    ///
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

    auto createRuntimeContext()
    {
        auto context = new RuntimeAutoMapper();

        // fill mapper
        static foreach (Mapper; FullMappers)
            context.runtimeMappers[typeid(IMapper!(Mapper.TS, Mapper.TD))] = new Mapper(context);

        // fill converters
        static foreach (Conv; TypesConverters)
            static if (is(Conv : ITypeConverter!(TSource, TDest), TSource, TDest))
                context.converters[typeid(ITypeConverter!(TSource, TDest))] = new Conv();

        // fill transformers
        static foreach (Trans; ValueTransformers)
            static if (is(Trans : IValueTransformer!TValue, TValue))
                context.transformers[typeid(IValueTransformer!TValue)] = new Trans();

        return context;
    }   

    /**
        Map an object to another.
        Params:
            source = The type to map
        Retuns:
            The mapped object
    */
    TDest map(TDest, TSource)(TSource source) if (isClassOrStruct!TSource && isClassOrStruct!TDest)
    {
        template isRightMapper(T) {
            enum bool isRightMapper = (isInstanceOf!(ObjectMapper, T) && is(T.TSource : TSource) && 
                is(T.TDest : TDest));
        }

        alias M = Filter!(isRightMapper, FullMappers);

        static if (M.length is 0)
            static assert(false, "No mapper found for mapping from " ~ TSource.stringof ~ " to " ~ TDest.stringof);
        else
            return M[0].map(source, this);
    }

    /// ditto
    TDest map(TDest, TSource)(TSource source) if (isArray!TSource && isArray!TDest)
    {
        TDest ret = TDest.init;

        foreach(ForeachType!TSource elem; source) {
            static if (is(ForeachType!TSource == ForeachType!TDest))
                ret ~= elem; // same array type, just copy
            else
                ret ~= this.map!(ForeachType!TDest)(elem); // else map
        }

        return ret;
    }

    /// ditto
    TDest map(TDest, TSource)(TSource source) if 
        (!isArray!TSource && !isArray!TDest && (!isClassOrStruct!TSource || !isClassOrStruct!TDest))
    {
        template isRightConverter(T) {
            enum bool isRightConverter = is(T : ITypeConverter!(TSource, TDest));
        }

        alias M = Filter!(isRightConverter, TypesConverters);

        static if (M.length is 0)
            static assert(false, "No type converter found for mapping from " ~ TSource.stringof ~ " to " ~ 
                TDest.stringof);
        else
            return __traits(getMember, this, uniqueConverterIdentifier!M).convert(source);
    }

    ///
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

/**
    This is a non templated slower version of AutoMapper.
*/
class RuntimeAutoMapper
{
    public Object[TypeInfo] runtimeMappers;
    public Object[TypeInfo] transformers;
    public Object[TypeInfo] converters;

    IMapper!(TSource, TDest) getMapper(TDest, TSource)()
    {
        alias I = IMapper!(TSource, TDest);
        auto info = typeid(I);

        Object* mapper = (info in runtimeMappers);

        if (mapper !is null) {
            return (cast(I) *mapper);
        }
        else {
            return null;
        }
    }

    TDest map(TDest, TSource)(TSource value)
    {
        // enum id = uniquePairIdentifier!(TSource, TDest);
        alias I = IMapper!(TSource, TDest);
        auto info = typeid(I);

        Object* mapper = (info in runtimeMappers);

        if (mapper !is null) {
            return (cast(I) *mapper).map(value);
        }
        else {
            throw new Exception("No mapper found for mapping from " ~ TSource.stringof ~ " to " ~ TDest.stringof);
        }
    }

    TValue transform(TValue)(TValue value)
    {
        // enum id = uniqueTypeIdentifier!TValue;
        alias I = IValueTransformer!TValue;
        auto info = typeid(I);

        Object* transformer = (info in transformers);

        if (transformer !is null) {
            return (cast(I) *transformer).transform(value);
        }
        else {
            return value;
        }
    }
}

///
unittest
{
    import automapper;

    static class A {
        string foo = "foo";
    }

    static class B {
        string bar;
    }

    auto am = MapperConfiguration!(
        CreateMap!(A, B)
            .ForMember!("bar", "foo"))
                .createMapper().createRuntimeContext();

    const auto b = am.map!B(new A());
}


///
unittest
{
    import std.datetime : SysTime;

    static class Address {
        long zipcode = 42_420;
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
    const UserDTO dto = am.map!UserDTO(user);

    assert(dto.fullName == user.name ~ " " ~ user.lastName);
    assert(dto.addressCity == user.address.city);
    assert(dto.addressZipcode == user.address.zipcode);
}

/// Naming conventions
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
    const B b = am.map!B(a);
    assert(a.foo_bar_baz == b.fooBarBaz);
    assert(a.data_processor == b.dataProcessor);
}

/// Type converters
unittest
{
    import std.datetime: SysTime;

    static class A {
        long timestamp = 1_542_873_605;
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

/// struct
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
    const B b = am.map!B(a);
    assert(b.foo == a.foo);
}

/// reverse flattening
unittest
{
    static class Address {
        int zipcode;
    }

    static class A {
        Address address;
    }

    static class B {
        int addressZipcode = 74_000;
    }

    auto am = MapperConfiguration!(
        CreateMap!(A, B)
            .ReverseMap!())
            .createMapper();

    B b = new B();
    const A a = am.map!A(b);
    assert(b.addressZipcode == a.address.zipcode);
}

/// array
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

    MapperConfiguration!(
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

/// auto
unittest
{
    static class Address {
        long zipcode = 74_000;
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
    const UserDTO dto = am.map!UserDTO(user);

    assert(dto.fullName == user.name ~ " " ~ user.lastName);
    assert(dto.addressCity == user.address.city);
    assert(dto.addressZipcode == user.address.zipcode);

}

/// flattening
unittest
{
    static class Address {
        int zipcode = 74_000;
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
    const B b = am.map!B(a);
    assert(b.addressZipcode == a.address.zipcode);
}

/// nest
unittest
{
    static class Address {
        int zipcode = 74_000;
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
    const B b = am.map!B(a);
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
    const B b = am.map!B(a);
    assert(b.str == a.str);
    assert(a.foo == a.foo);
    assert(b.mod == "modified");
}
