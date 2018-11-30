/**
    AutoMapper naming convention.

    You can create your own naming convetion by defining a struct with this shape:

    ----
    struct MyConvention
    {
        string convert(string identifier)
        {
            ...
        }

        string convertBack(string myConvention)
        {
            ...
        }
    }
    ----
*/
module automapper.naming;

import automapper.meta;

/**
    The camel case naming convetion.
*/
struct CamelCaseNamingConvention
{
    /// Convert from foo.bar.baz to fooBarBaz
    string convert(string flattened)
    {
        import std.string : split, join, capitalize;
        import std.algorithm : map;

        auto sp = flattened.split(".");
        return sp[0] ~ sp[1..$].map!capitalize.join();
    }

    /// Convert from fooBarBaz to foo.bar.baz
    string convertBack(string camelCase)
    {
        import std.string : join;

        return camelCase.splitOnCase().join(".");
    }
}

///
unittest
{
    static assert(CamelCaseNamingConvention().convert("foo.bar.baz") == "fooBarBaz");
    static assert(CamelCaseNamingConvention().convertBack("fooBarBaz") == "foo.bar.baz");
    static assert(CamelCaseNamingConvention().convert("foo") == "foo");
    static assert(CamelCaseNamingConvention().convertBack("foo") == "foo");
}

/**
    The pascal case naming convetion.
*/
struct PascalCaseNamingConvention
{
    /// Convert from foo.bar.baz to fooBarBaz
    string convert(string flattened)
    {
        import std.string : split, join, capitalize;
        import std.algorithm : map;

        auto sp = flattened.split(".");
        return sp.map!capitalize.join();
    }

    /// Convert from fooBarBaz to foo.bar.baz
    string convertBack(string pascalCase)
    {
        import std.string : join;
        import std.string : toLower;

        return pascalCase.splitOnCase().join(".").toLower();
    }
}

///
unittest
{
    static assert(PascalCaseNamingConvention().convert("foo.bar.baz") == "FooBarBaz");
    static assert(PascalCaseNamingConvention().convertBack("FooBarBaz") == "foo.bar.baz");
    static assert(PascalCaseNamingConvention().convert("foo") == "Foo");
    static assert(PascalCaseNamingConvention().convertBack("Foo") == "foo");
}

/**
    The lower undescore naming convetion.
*/
struct LowerUnderscoreNamingConvention
{
    /// Convert from foo.bar.baz to fooBarBaz
    string convert(string flattened)
    {
        import std.string : split, join, capitalize;
        import std.algorithm : map;

        return flattened.split(".").join("_");
    }

    /// Convert from fooBarBaz to foo.bar.baz
    string convertBack(string lowerUnder)
    {
        import std.string : split, join;

        return lowerUnder.split("_").join(".");
    }
}

///
unittest
{
    static assert(LowerUnderscoreNamingConvention().convert("foo.bar.baz") == "foo_bar_baz");
    static assert(LowerUnderscoreNamingConvention().convertBack("foo_bar_baz") == "foo.bar.baz");
    static assert(LowerUnderscoreNamingConvention().convert("foo") == "foo");
    static assert(LowerUnderscoreNamingConvention().convertBack("foo") == "foo");
}

template isNamingConvention(T)
{
    enum isNamingConvention = (
        hasSpecifiedCallable!(T, "convert", string, string) &&
        hasSpecifiedCallable!(T, "convertBack", string, string));
}

///
unittest
{
    static assert(isNamingConvention!CamelCaseNamingConvention);
}
