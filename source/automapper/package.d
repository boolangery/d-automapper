/**
    Automapper.
*/
module automapper;

public import std.variant;


/// A interface that map a variant to another variant.
interface IMapper
{
    Variant map(Variant value);
}

/// A mapper that map from A to B.
abstract class MapperBase(A, B) : IMapper
{
    protected AutoMapper context;

    this(AutoMapper ctx)
    {
        context = ctx;
    }

    final override Variant map(Variant value)
    {
        A input = *(value.peek!A);
        Variant ret = map(input);
        return ret;
    }

    abstract B map(A value);
}

class AutoMapper
{
    import std.conv;

private:
    alias MapperFunc = Object delegate(Object a) @safe;
    alias MapperByType = IMapper[TypeInfo];
    MapperByType[TypeInfo] _mappers;

public:
    IMapper createMap(A, B)()
    {
        debug pragma(msg, __PRETTY_FUNCTION__);

        import automapper.mappers;

        auto mapper = new Mapper!(A, B)(this);

        _mappers[typeid(A)][typeid(B)] = mapper;
        return mapper;
    }

    B map(A, B)(A a)
    {
        debug pragma(msg, __PRETTY_FUNCTION__);

        IMapper mapper = null;

        if (typeid(A) in _mappers) {
            if (typeid(B) in _mappers[typeid(A)]) {
                mapper = _mappers[typeid(A)][typeid(B)];
            }
        }
        // try autoregistration
        else {
            mapper = this.createMap!(A, B);
        }

        if (mapper !is null) {
            Variant value = a;
            return *(mapper.map(value).peek!B);
        }

        throw new Exception("unregistered type");
    }
}

version(unittest)
{
    class ClassA
    {
        string str = "foo";
        long value = 42;
    }

    class ClassB
    {
        string str;
        long value;
    }
}

///
unittest
{
    auto mapper = new AutoMapper();
    mapper.createMap!(ClassA, ClassB)();

    auto classB = mapper.map!(ClassA, ClassB)(new ClassA());

    import std.stdio;
    writeln(classB.str);
    writeln(classB.value);
}
