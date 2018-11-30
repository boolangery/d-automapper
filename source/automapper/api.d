/**
    AutoMapper API.

    This module is the entry point for building an AutoMapper configuration.
*/
module automapper.api;

import automapper.meta;
import automapper.naming;
public import automapper.config;


/// Entry point for building an object mapper configuration in a fluent way
template CreateMap(TSource, TDest, Configs...) if (isClassOrStruct!TSource && isClassOrStruct!TDest)
{
    import automapper.mapper;
    import automapper.naming;

    enum bool Reverse = onlyOneExists!(isReverseMapConfig, Configs);
    alias MemberMappings = Filter!(isObjectMemberMappingConfig, Configs);
    alias SourceNamingConvention = findOrDefault!(isSourceNamingConventionConfig,
        SourceNamingConventionConfig!CamelCaseNamingConvention, Configs);
    alias DestNamingConvention = findOrDefault!(isDestNamingConventionConfig,
        DestNamingConventionConfig!CamelCaseNamingConvention, Configs);

    // By default we set the CamelCaseNamingConvention
    alias static class CreateMap : ObjectMapperConfig!(TSource, TDest, SourceNamingConvention.Convention,
        DestNamingConvention.Convention, Reverse, MemberMappings)
    {
        /// Tell to reverse the mapper automatically
        template ReverseMap()
        {
            alias ReverseMap = CreateMap!(TSource, TDest, AliasSeq!(Configs, ReverseMapConfig));
        }

        /// Precise a member mapping
        template ForMember(string DestMember, string SrcMember)
        {
            alias ForMember = CreateMap!(TSource, TDest, AliasSeq!(Configs,
                ForMemberConfig!(DestMember, SrcMember)));
        }

        /// Customize member mapping with a delegate
        template ForMember(string DestMember, alias Delegate)
        {
            alias ForMember = CreateMap!(TSource, TDest, AliasSeq!(Configs,
                ForMemberConfig!(DestMember, Delegate)));
        }

        /// Ignore a member
        template Ignore(string DestMember)
        {
            alias Ignore = CreateMap!(TSource, TDest, AliasSeq!(Configs, IgnoreConfig!DestMember));
        }

        /// Set source naming convention
        template SourceMemberNaming(TConv) if (isNamingConvention!TConv)
        {
            alias SourceMemberNaming = CreateMap!(TSource, TDest, AliasSeq!(Configs, SourceNamingConventionConfig!TConv));
        }

        /// Set dest. naming convention
        template DestMemberNaming(TConv) if (isNamingConvention!TConv)
        {
            alias DestMemberNaming = CreateMap!(TSource, TDest, AliasSeq!(Configs, DestNamingConventionConfig!TConv));
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

/// entry point for bulding a type converter configuration
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
