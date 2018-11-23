/**
    Types converter.
*/
module automapper.type.converter;


interface ITypeConverter(TSource, TDest)
{
    TDest convert(TSource source);
}

abstract class DelegateTypeConverter(TSource, TDest, alias Delegate) : ITypeConverter!(TSource, TDest)
{
    alias A = TSource;
    alias B = TDest;
    alias D = Delegate;

    override TDest convert(TSource source)
    {
        return Delegate(source);
    }
}

template isTypeConverter(T)
{
    enum bool isTypeConverter = (is(T: ITypeConverter!(F, T), F, T));
}
