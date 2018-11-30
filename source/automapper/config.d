/**
    AutoMapper configuration.
*/
module automapper.config;

import automapper.meta;
import automapper.mapper;
import automapper.type.converter : isTypeConverter;
import automapper.value.transformer : isValueTransformer;
import automapper.naming : isNamingConvention;


/// Is the provided type a configuration object ?
package template isConfigurationObject(T)
{
    enum bool isConfigurationObject = (
        isObjectMapperConfig!T ||
        isTypeConverter!T ||
        isValueTransformer!T);
}

/**
    `ObjectMapper` configuration.
    Params:
        TSrc = The type of source object.
        TDst = The type of destination object.
        TSourceConv = The type of source naming convention to use.
        TDestConv = The type of source naming convention to use.
        Rev = true if we must reverse this mapper.
        Mps = A list of member mapping specialization.
*/
package class ObjectMapperConfig(TSrc, TDst, TSourceConv, TDestConv, bool Rev, Mps...) if
    (isClassOrStruct!TSrc && isClassOrStruct!TDst &&
    isNamingConvention!TSourceConv && isNamingConvention!TDestConv &&
    allSatisfy!(isObjectMemberMappingConfig, Mps))
{
    alias TSource = TSrc;
    alias TDest = TDst;
    alias Mappings = Mps;
    alias Reverse = Rev;
}

/// Tell if it's an `ObjectMapperConfig`
package template isObjectMapperConfig(T)
{
    static if (is(T : ObjectMapperConfig!(TSource, TDest, TSourceConv, TDestConv, Reverse, Mappings),
        TSource, TDest, TSourceConv, TDestConv, bool Reverse, Mappings))
        enum isObjectMapperConfig = true;
    else static if (is(T : ObjectMapperConfig!(TSource, TDest, TSourceConv, TDestConv, Reverse),
        TSource, TDest, TSourceConv, TDestConv, bool Reverse))
        enum isObjectMapperConfig = true;
    else
        enum isObjectMapperConfig = false;
}

/// A struct that act like a flag to indicate that the mapper must be reversed.
package struct ReverseMapConfig
{
    // do nothing
}

/// Tell if its a `ReverseMapConfig`
package template isReverseMapConfig(T)
{
    enum isReverseMapConfig = is(T : ReverseMapConfig);
}

/// A struct to configure the naming convention used in the source object.
package struct SourceNamingConventionConfig(T) if (isNamingConvention!T)
{
    alias Convention = T;
}

/// Tell if its a `SourceNamingConventionConfig`
package template isSourceNamingConventionConfig(T)
{
    enum isSourceNamingConventionConfig = is(T : SourceNamingConventionConfig!C, C);
}

/// Precise the naming convention for dest object in a mapper
package struct DestNamingConventionConfig(T) if (isNamingConvention!T)
{
    alias Convention = T;
}

/// Tell if its a `DestNamingConventionConfig`
package template isDestNamingConventionConfig(T)
{
    enum isDestNamingConventionConfig = is(T : DestNamingConventionConfig!C, C);
}

/**
    Base class for create a config about a member in an object mapper.
    Template_Params:
        T = The member to map in the destination object
*/
package class ObjectMemberMappingConfig(string T)
{
    enum string DestMember = T;
}

/// Tell if its a `ObjectMemberMappingConfig`
package template isObjectMemberMappingConfig(T)
{
    enum bool isObjectMemberMappingConfig = (is(T: ObjectMemberMappingConfig!BM, string BM));
}

/// `ForMemberConfig` mapping type
package enum ForMemberConfigType
{
    mapMember,  // map a member to another member
    mapDelegate // map a member to a delegate
}

/**
    Used to configure object mapper. It tells to map a member from source object
    to a member in dest object.
    Params:
        DestMember = The member name in the destination object
        SourceMember = The member name in the source object or a custom delegate
**/
package class ForMemberConfig(string DestMember, string SourceMember) : ObjectMemberMappingConfig!(DestMember)
{
    enum ForMemberConfigType Type = ForMemberConfigType.mapMember;
    alias Action = SourceMember;
}

/**
    Used to configure object mapper. It tells to map a member from source object
    to a user-defined delegate.
    Params:
        DestMember = The member name in the destination object
        Delegate = A `DestMemberType delegate(TSource)`
**/
package class ForMemberConfig(string DestMember, alias Delegate) : ObjectMemberMappingConfig!(DestMember)
    if (isCallable!Delegate)
{
    enum ForMemberConfigType Type = ForMemberConfigType.mapDelegate;
    alias Action = Delegate;
}

package template isForMember(T, ForMemberConfigType Type)
{
    static if (is(T == ForMemberConfig!(DestMember, Action), string DestMember, alias Action))
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
package class IgnoreConfig(string T) : ObjectMemberMappingConfig!(T)
{
    // do nothing
}

/**
    Define AutoMapper configuration.
*/
class MapperConfiguration(Configs...) // if (allSatisfy!(isConfigurationObject, Configs))
{
    // sort configuration object
    alias ObjectMappersConfig = Filter!(isObjectMapperConfig, Configs);
    alias TypesConverters = Filter!(isTypeConverter, Configs);
    alias ValueTransformers = Filter!(isValueTransformer, Configs);

    static auto createMapper()
    {
        import automapper;
        return new AutoMapper!(typeof(this))();
    }
}

///
unittest
{
    import automapper;
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
