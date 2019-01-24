/**
    AutoMapper API.

    This module is the entry point for building an AutoMapper configuration.
*/
module automapper.api;

import automapper.meta;
import automapper.naming;
public import automapper.config;


/// Entry point for building an object mapper configuration in a fluent way
class CreateMap(TSource, TDest, Configs...) : ObjectMapperConfig!(TSource, TDest, 
        findOrDefault!(isSourceNamingConventionConfig,
            SourceNamingConventionConfig!CamelCaseNamingConvention, Configs)
                .Convention,
        findOrDefault!(isDestNamingConventionConfig,
            DestNamingConventionConfig!CamelCaseNamingConvention, Configs)
                .Convention, 
        onlyOneExists!(isReverseMapConfig, Configs), 
        Filter!(isObjectMemberMappingConfig, Configs))
    if (isClassOrStruct!TSource && isClassOrStruct!TDest)
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

///
unittest
{
    import automapper : MapperConfiguration, CreateMap;

    static class A {
        string foo;
        int bar;
    }

    static class B {
        string qux;
        int baz;
    }

    MapperConfiguration!(
        CreateMap!(A, B)
            .ForMember!("qux", "foo")
            .ForMember!("baz", "foo"))
                .createMapper();
}

///




/// entry point for bulding a type converter configuration
class CreateMap(A, B) if (!isClassOrStruct!A || !isClassOrStruct!B)
{
    import automapper.type.converter : DelegateTypeConverter, isTypeConverter;

    ///
    static class ConvertUsing(alias Delegate) : DelegateTypeConverter!(A, B, Delegate) if (isCallable!Delegate)
    {
        static assert(is(ReturnType!Delegate == B), "must return a " ~ B.stringof);
        static assert((Parameters!Delegate.length == 1) && is(Parameters!Delegate[0] == A), 
            "must take one argument of type " ~ A.stringof);
    }

    ///
    template ConvertUsing(Type) if (isTypeConverter!Type)
    {
        alias ConvertUsing = Type;
    }
}


///
unittest
{
    import automapper;
    import std.datetime : SysTime;

    static class A {
        long timestamp;
    }

    static class B {
        SysTime timestamp;
    }

    MapperConfiguration!(
        CreateMap!(long, SysTime)
            .ConvertUsing!((long ts) => SysTime(ts)),
        CreateMap!(A, B))
            .createMapper();
}
