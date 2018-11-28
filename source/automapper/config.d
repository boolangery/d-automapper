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

class ObjectMapperConfig(TSource, TDest, TSourceConv, TDestConv, bool Reverse, Mappings...) if
    (isClassOrStruct!TSource && isClassOrStruct!TDest &&
    isNamingConvention!TSourceConv && isNamingConvention!TDestConv &&
    allSatisfy!(isObjectMemberMappingConfig, Mappings))
{
    // TODO: to be removed
    alias A = TSource;
    alias B = TDest;
    alias M = Mappings;
    alias R = Reverse;
}


template isObjectMapperConfig(T)
{
    enum bool isObjectMapperConfig = is(T : ObjectMapperConfig!(TSource, TDest, TSourceConv, TDestConv, Reverse, Mappings),
        TSource, TDest, TSourceConv, TDestConv, bool Reverse, Mappings);
}

/**
    Base class for mapping a member in destination object.
    Template_Params:
        MT = The member to map in the destination object
*/
package class ObjectMemberMappingConfig(string T)
{
    enum string DestMember = T;
}

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
    Used to specialized a member mapping.
    Template_Params:
        T = The member name in the destination object
        F = The member name in the source object or a custom delegate
**/
class ForMemberConfig(string T, alias F) : ObjectMemberMappingConfig!(T)
{
    static assert(is(typeof(F) == string) || isCallable!F, ForMemberConfig.stringof ~
        " Action must be a string to map a member to another member or a delegate.");

    static if (is(typeof(F) == string))
        private enum ForMemberConfigType Type = ForMemberConfigType.mapMember;
    else
        private enum ForMemberConfigType Type = ForMemberConfigType.mapDelegate;

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
class IgnoreConfig(string T) : ObjectMemberMappingConfig!(T)
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
    Define AutoMapper configuration.
*/
class MapperConfiguration(Configs...) // if (allSatisfy!(isConfigurationObject, Configs))
{
    // sort configuration object
    alias ObjectMappersConfig = Filter!(isObjectMapperConfig, Configs);
    alias TypesConverters = Filter!(isTypeConverter, Configs);
    alias ValueTransformers = Filter!(isValueTransformer, Configs);
    // Add reversed mapper to user mapper
    // alias FullObjectMappers = AliasSeq!(ObjectMappers, generateReversedMapper!ObjectMappers);

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
