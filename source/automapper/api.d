/**
    AutoMapper API.
*/
module automapper.api;

import automapper.meta;


/// Entry point for building an ObjectMapper in a fluent way
template CreateMap(A, B, Configs...) if (isClassOrStruct!A && isClassOrStruct!B)
{
    import automapper.mapper;
    import automapper.naming;

    enum bool Reverse = onlyOneExists!(isReverseMapConfig, Configs);
    alias MemberMappings = Filter!(isObjectMemberMapping, Configs);

    // By default we set the CamelCaseNamingConvention
    alias static class CreateMap : ObjectMapper!(A, B, CamelCaseNamingConvention, MemberMappings)
    {
        enum bool MustBeReversed = Reverse;

        /// Tell to reverse the mapper automatically
        template ReverseMap()
        {
            alias ReverseMap = CreateMap!(A, B, AliasSeq!(Configs, ReverseMapConfig));
        }

        /// Precise a member mapping
        template ForMember(string DestMember, string SrcMember)
        {
            alias ForMember = CreateMap!(A, B, AliasSeq!(Configs,
                ForMemberConfig!(DestMember, SrcMember)));
        }

        /// Customize member mapping with a delegate
        template ForMember(string DestMember, alias Delegate)
        {
            alias ForMember = CreateMap!(A, B, AliasSeq!(Configs,
                ForMemberConfig!(DestMember, Delegate)));
        }

        /// Ignore a member
        template Ignore(string DestMember)
        {
            alias Ignore = CreateMap!(A, B, AliasSeq!(Configs, IgnoreConfig!DestMember));
        }
    }
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
    }

   auto am = MapperConfiguration!(
        CreateMap!(A, B)
            .ForMember!("qux", "foo")
            .ForMember!("baz", "foo"))
                .createMapper();
}

/// For type converter
template CreateMap(A, B) if (!isClassOrStruct!A || !isClassOrStruct!B)
{
    import automapper.type.converter;

    alias static class CreateMap
    {
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
}

///
unittest
{
    import automapper;
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