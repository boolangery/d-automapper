/**
    Types converter.
*/
module automapper.type.converter;

import automapper.meta;


interface ITypeConverter(TSource, TDest)
{
    TDest convert(TSource source);
}

template isTypeConverter(T)
{
    enum bool isTypeConverter = (is(T: ITypeConverter!(F, T), F, T));
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
