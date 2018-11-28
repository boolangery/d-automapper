/**
    AutoMapper configuration.
*/
module automapper.config;

import automapper.meta;
import automapper.api;
import automapper.mapper : isObjectMapper, generateReversedMapper;
import automapper.type.converter : isTypeConverter;
import automapper.value.transformer : isValueTransformer;


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
