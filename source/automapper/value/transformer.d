/**
    Value tranformer.
**/
module automapper.value.transformer;

import std.meta;


///
template ValueTransformer(T) if (isValueTransformer!T)
{
    alias ValueTransformer = T;
}

///
class ValueTransformer(T, alias D) : IValueTransformer if (isCallable!D)
{
    static assert((Parameters!D.length == 1) && is(Parameters!D[0] == T) && is(ReturnType!D == T),
        "the delegate must take a " ~ T.stringof ~ " and return a " ~ T.stringof);

    ///
    T transform(in T value)
    {
        return D(value);
    }
}

///
template isValueTransformer(T)
{
    enum bool isValueTransformer = (is(T: IValueTransformer!(T), T));
}

///
template isValueTransformerFor(For, T)
{
    enum bool isValueTransformer = (is(T: IValueTransformer!(For)));
}

///
interface IValueTransformer(T)
{
    ///
    T transform(in T value);
}

///
unittest
{
    import automapper : MapperConfiguration, CreateMap;

    static class A {
        string foo;
    }

    static class B {
        string foo;
    }

    static class StringTransformer : IValueTransformer!string
    {
        string transform(in string value)
        {
            return value ~ "!!!";
        }
    }

    auto am = MapperConfiguration!(
        CreateMap!(A, B),
        ValueTransformer!StringTransformer)
            .createMapper();

    A a = new A();
    const B b = am.map!B(a);
    assert(b.foo == "!!!");
}
