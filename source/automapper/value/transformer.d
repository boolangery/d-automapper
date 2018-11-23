/**
    Value tranformer.
**/
module automapper.value.transformer;

import std.meta;


template ValueTransformers(T) if (isValueTransformers!T)
{
    alias ValueTransformers = T;
}

template ValueTransformers(T, alias D) if (isCallable!D)
{
    static assert((Parameters!D.length == 1) && is(Parameters!D[0] == T) && is(ReturnType!D == T),
        "the delegate must take a " ~ T.stringof ~ " and return a " ~ T.stringof);

    alias static class ValueTransformers : IValueTransformer
    {
        T transform(in T value)
        {
            return D(value);
        }
    }
}

template isValueTransformers(T)
{
    enum bool isValueTransformers = (is(T: IValueTransformer!(T), T));
}

template getValueTransformers(T...)
{
    private template getValueTransformersImpl(size_t idx) {
        static if (idx < T.length) {
            static if (isValueTransformers!(T[idx]))
                alias getValueTransformersImpl = AliasSeq!(T[idx], getValueTransformersImpl!(idx + 1));
            else
                alias getValueTransformersImpl = getValueTransformersImpl!(idx + 1); // continue searching
        }
        else
            alias getValueTransformersImpl = AliasSeq!(); // not found
    }
    alias getValueTransformers = getValueTransformersImpl!0;
}

/// Search for the right converter in a list
template getValueTransformer(TValue, T...)
{
    private template getValueTransformerImpl(size_t idx) {
        static if (idx < T.length) {
            static if (is(T[idx] : IValueTransformer!(TValue)))
                alias getValueTransformerImpl = T[idx];
            else
                alias getValueTransformerImpl = getValueTransformerImpl!(idx + 1); // continue searching
        }
        else
            alias getValueTransformerImpl = void; // not found
    }

    alias getValueTransformer = getValueTransformerImpl!0;
}

///
interface IValueTransformer(T)
{
    T transform(in T value);
}

///
unittest
{
    import automapper;

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
            return "!!!";
        }
    }

    auto am = new AutoMapper!(
        CreateMap!(A, B),
        ValueTransformers!StringTransformer);

    A a = new A();
    B b = am.map!B(a);
    assert(b.foo == "!!!");
}
